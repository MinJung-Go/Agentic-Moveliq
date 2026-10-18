import Combine
import Foundation
import SwiftData

@MainActor
final class ServiceConnectionModel: ObservableObject {
    enum Stage { case selection, progress, result }
    @Published private(set) var stage = Stage.selection
    @Published private(set) var config = CoachPluginConfiguration()
    @Published private(set) var selected: Set<ServiceConnectionTarget> = []
    @Published private(set) var loaded = false
    @Published private(set) var error: String?
    @Published private(set) var revision = 0
    let flow = ServiceConnectionFlow()
    private var context: ModelContext?
    private var token: String?
    private var onboarding = false
    private var work: Task<Void, Never>?

    init() { flow.onChange = { [weak self] in self?.revision += 1 } }
    var busy: Bool { work != nil || flow.isRunning || flow.hasOutstandingRequest }
    var targets: [ServiceConnectionTarget] { ServiceConnectionTarget.allCases.filter { selected.contains($0) } }
    var complete: [ServiceConnectionTarget] { targets.filter { access($0).connected } }
    var pending: [ServiceConnectionTarget] { targets.filter { !access($0).connected } }
    var calendarNeedsSetup: Bool { stage == .result && selected.contains(.calendar) && access(.calendar) == .needsCalendarSelection }

    func load(context: ModelContext, onboarding: Bool) {
        guard !loaded else { refresh(); return }
        self.context = context; self.token = ServiceCredentials.session?.token; self.onboarding = onboarding
        do {
            try validate()
            config = try CoachLifeStore.plugins(context)
            selected = ServiceConnectionSelection.targets(config: config, onboarding: onboarding,
                                                          healthRequested: HealthKitService.shared.hasRequestedAuthorization)
            loaded = true
        } catch { self.error = error.localizedDescription }
    }
    func validate() throws {
        guard let context else { throw CoachPluginError.accountChanged }
        try CoachLifeStore.checkAccount(context: context, token: token)
    }
    func access(_ target: ServiceConnectionTarget) -> ServiceConnectionAccess {
        NativeServiceConnection.inspect(target, config: config)
    }
    func status(_ target: ServiceConnectionTarget) -> String {
        if flow.isRunning, flow.current == target { return "等待系统选择" }
        if case .some(.failed(let message)) = flow.steps[target], access(target).needsRequest { return message }
        let value = access(target)
        switch value {
        case .notDetermined, .upgradeNeeded, .needsActivation: return "尚未连接"
        case .authorized: return target == .browser ? "已启用，无需系统授权" : "已授权"
        case .healthSelectionCompleted: return "已完成授权选择"
        case .needsCalendarSelection: return "请完成日历设置"
        case .denied: return target == .maps ? "定位未允许，可手填地点" : "尚未允许"
        case .restricted: return "系统限制，暂不可用"
        case .unavailable: return target == .alarms ? "需要 iOS 26 或更新版本" : "此设备暂不可用"
        }
    }
    func toggle(_ target: ServiceConnectionTarget) {
        guard loaded, !busy else { return }
        if selected.contains(target) { selected.remove(target) } else { selected.insert(target) }
    }
    func edit() { guard !busy else { return }; stage = .selection; error = nil }
    func start() {
        guard loaded, !busy, !selected.isEmpty, let context else { return }
        do {
            try validate()
            // Rebase only selection onto the latest scope, sync settings and reminders.
            let latest = try CoachLifeStore.plugins(context)
            let value = ServiceConnectionSelection.applying(selected, to: latest)
            try CoachLifeStore.save(plugins: value, in: context)
            config = value
        } catch { self.error = error.localizedDescription; return }
        error = nil; stage = .progress
        work = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.work = nil; self.revision += 1 }
            let client = ServiceConnectionFlow.Client(inspect: { self.access($0) }, request: { target in
                try await NativeServiceConnection.request(target, validate: self.validate)
            }, validate: self.validate, waitUntilActive: NativeServiceConnection.waitUntilActive)
            await self.flow.connect(selected: self.selected, client: client)
            do { try self.validate(); self.stage = .result; self.error = self.flow.failure }
            catch { self.error = error.localizedDescription }
        }
    }
    func pause() {
        guard work != nil || flow.isRunning else { return }
        flow.cancel(); work?.cancel(); stage = .result
    }
    func refresh() {
        guard loaded, !busy, let context else { return }
        do { try validate(); config = try CoachLifeStore.plugins(context); revision += 1 }
        catch { self.error = error.localizedDescription }
    }
    func update(_ transform: (inout CoachPluginConfiguration) -> Void) {
        guard loaded, !busy, let context else { return }
        do {
            try validate()
            var value = try CoachLifeStore.plugins(context)
            transform(&value)
            try CoachLifeStore.save(plugins: value, in: context)
            config = value; error = nil; revision += 1
        } catch { self.error = error.localizedDescription }
    }
    func finish() -> Bool {
        guard loaded, !busy else { return false }
        do {
            try validate()
            // A new account skipping the guide must not inherit device-wide HealthKit consent.
            if onboarding, config.healthEnabled == nil {
                update { $0.healthEnabled = false }
                guard error == nil else { return false }
            }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}

extension ServiceConnectionAccess {
    var connected: Bool {
        switch self {
        case .authorized, .healthSelectionCompleted: return true
        default: return false
        }
    }
}
