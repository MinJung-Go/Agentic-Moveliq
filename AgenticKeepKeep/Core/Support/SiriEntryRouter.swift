import AppIntents
import Combine
import Foundation

@MainActor
final class SiriEntryRouter: ObservableObject {
    static let shared = SiriEntryRouter()
    struct Entry { var accountID: String; var route: String; var text: String = "" }
    @Published var pending: Entry?
    func prepare(_ route: String, text: String = "") throws {
        guard let session = ServiceCredentials.session else { throw CoachPluginError.unavailable("请先打开 Moveliq 登录，再使用此动作。") }
        guard text.count <= 4000 else { throw CoachPluginError.invalid }
        pending = Entry(accountID: AppModelContainer.accountKey(userID: session.user.id, server: ServiceEndpoint.baseURL), route: route, text: text)
    }
}

struct OpenMiloIntent: AppIntent {
    static var title: LocalizedStringResource = "打开 Milo"
    static var description = IntentDescription("打开 Moveliq，与 Milo 继续对话。")
    static var openAppWhenRun = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @MainActor func perform() async throws -> some IntentResult {
        try SiriEntryRouter.shared.prepare("chat"); return .result()
    }
}

struct OpenTodayTrainingIntent: AppIntent {
    static var title: LocalizedStringResource = "查看今日训练"
    static var description = IntentDescription("打开当前账号的今日训练安排。")
    static var openAppWhenRun = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @MainActor func perform() async throws -> some IntentResult {
        try SiriEntryRouter.shared.prepare("today"); return .result()
    }
}

struct PrepareMoveliqRecordIntent: AppIntent {
    static var title: LocalizedStringResource = "记一笔"
    static var description = IntentDescription("在 Moveliq 准备记录草稿，核对后保存。")
    static var openAppWhenRun = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "记录内容", default: "") var text: String
    @MainActor func perform() async throws -> some IntentResult {
        try SiriEntryRouter.shared.prepare("record", text: text); return .result()
    }
}

struct MoveliqAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenMiloIntent(), phrases: ["用\(.applicationName)打开Milo"], shortTitle: "打开 Milo", systemImageName: "bubble.left")
        AppShortcut(intent: OpenTodayTrainingIntent(), phrases: ["用\(.applicationName)查看今日训练"], shortTitle: "今日训练", systemImageName: "calendar")
        AppShortcut(intent: PrepareMoveliqRecordIntent(), phrases: ["用\(.applicationName)记一笔"], shortTitle: "记一笔", systemImageName: "square.and.pencil")
    }
}
