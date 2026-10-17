import Foundation
import Combine
import WidgetKit

@MainActor
final class AuthStore: ObservableObject {
    static let shared = AuthStore()
    enum Phase { case restoring, signedOut, signedIn, failed }
    @Published private(set) var phase: Phase = .restoring
    @Published private(set) var user: ServiceUser?
    @Published private(set) var configuration: ServiceConfiguration?
    @Published var message: String?
    @Published private(set) var busy = false
    private var generation = UUID()
    private var expiredObserver: AnyCancellable?
    init() {
        expiredObserver = NotificationCenter.default.publisher(for: ServiceTransport.expired)
            .receive(on: DispatchQueue.main).sink { [weak self] note in
                guard let token = note.object as? String, token == ServiceCredentials.session?.token else { return }
                self?.lockSession(message: "登录已失效，请重新登录。")
            }
    }
    func restore() async {
        guard !busy else { return }
        guard let stored = ServiceCredentials.session else { phase = .signedOut; return }
        let marker = generation
        busy = true; phase = .restoring; message = nil
        defer { if marker == generation { busy = false } }
        do {
            struct Me: Decodable { let user: ServiceUser }
            let data = try await AuthAPI.request("/auth/me", token: stored.token)
            let me = try JSONDecoder().decode(Me.self, from: data)
            guard me.user.id == stored.user.id else { throw AuthServiceError(status: 401, message: "账号状态异常，请重新登录。") }
            let config = try await fetchConfiguration(stored.token)
            guard marker == generation else { return }
            user = me.user; configuration = config; ServiceRuntime.shared.configuration = config; phase = .signedIn
            LLMSettings.shared.objectWillChange.send()
        } catch {
            guard marker == generation else { return }
            if (error as? AuthServiceError)?.status == 401 { lockSession(message: "登录已失效，请重新登录。") }
            else { phase = .failed; message = "暂时无法恢复登录，请检查网络后重试。\n\(error.localizedDescription)" }
        }
    }
    func authenticate(username: String, password: String, invite: String?) async {
        guard !busy else { return }
        let marker = generation
        busy = true; message = nil
        defer { if marker == generation { busy = false } }
        do {
            var body = ["username": AuthInputPolicy.username(username), "password": password]
            if let invite { body["inviteCode"] = AuthInputPolicy.inviteCode(invite) }
            let data = try await AuthAPI.request(invite == nil ? "/auth/login" : "/auth/register", method: "POST", body: body)
            let session = try JSONDecoder().decode(ServiceSession.self, from: data)
            guard UUID(uuidString: session.user.id) != nil else { throw AuthServiceError(status: 0, message: "账号标识无效。") }
            guard marker == generation else { return }
            try ServiceCredentials.save(session)
            let config = try await fetchConfiguration(session.token)
            guard marker == generation else { return }
            user = session.user; configuration = config; ServiceRuntime.shared.configuration = config; phase = .signedIn
            LLMSettings.shared.objectWillChange.send()
        } catch {
            guard marker == generation else { return }
            message = error.localizedDescription
            if ServiceCredentials.session != nil { phase = .failed }
        }
    }
    private func fetchConfiguration(_ token: String) async throws -> ServiceConfiguration {
        let data = try await AuthAPI.request("/config", token: token)
        let config = try JSONDecoder().decode(ServiceConfiguration.self, from: data)
        guard config.validBudget else {
            throw AuthServiceError(status: 0, message: "服务配置异常，请联系管理员。")
        }
        return config
    }
    func logout() async {
        let token = ServiceCredentials.session?.token
        lockSession(message: nil)
        if let token { _ = try? await AuthAPI.request("/auth/logout", method: "POST", token: token) }
    }
    func lockSession(message: String?) {
        generation = UUID(); busy = false
        CoachAutomationCoordinator.shared.invalidate()
        ServiceCredentials.clear(); ServiceTransport.shared.cancelAll()
        CalendarPluginService.shared.reset()
        MapsPluginService.shared.reset()
        MusicPluginService.shared.reset()
        SiriEntryRouter.shared.pending = nil
        ExerciseTutorialStore.shared.stopAll()
        AccountPreferences().deactivate()
        LLMSettings.shared.reloadAccountUsage()
        HealthKitService.shared.reloadAccountMetadata()
        AppModelContainer.active = nil
        AppModelContainer.lockWidget()
        user = nil; configuration = nil; ServiceRuntime.shared.configuration = nil; self.message = message; phase = .signedOut
        LLMSettings.shared.objectWillChange.send()
    }
}
