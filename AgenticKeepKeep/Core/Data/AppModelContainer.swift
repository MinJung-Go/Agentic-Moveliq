import Foundation
import SwiftData
import CryptoKit
import WidgetKit

/// SwiftData 容器工厂。SwiftData 是全 App 唯一数据源。
enum AppModelContainer {

    /// App Group：让桌面小组件能读到同一份数据。
    /// 需要最终签名包含 App Group 能力；没有该能力时会退回本地容器（App 照常可用，小组件显示空态）。
    static let appGroupID = "group.com.minjung.keepkeep"

    /// 先用 FileManager 探测 App Group 容器是否真的可用。
    /// 必须探测：没有该 entitlement 时，SwiftData 的 groupContainer 会直接 fatalError（不可捕获），
    /// 而 containerURL 在同样条件下只是返回 nil。
    static var appGroupAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil
    }

    /// 全部模型类型（新增模型时在此登记）
    static var schema: Schema {
        Schema([
            WorkoutSession.self,
            ExerciseTutorialCache.self,
            ExerciseSet.self,
            MealEntry.self,
            FoodItem.self,
            BodyMetric.self,
            HealthSnapshot.self,
            HealthWorkout.self,
            RawNote.self,
            AnalysisReport.self,
            Plan.self,
            PlanDay.self,
            PlanExercise.self,
            ChatMessage.self,
            SetLog.self,
            WorkoutSessionDraft.self,
            CoachWorkspace.self, CoachCheckIn.self, CoachActionRecord.self, CoachTrainingLink.self, CoachAutomationRecord.self
        ])
    }

    private static let widgetStoreKey = "auth.widget.store"
    private static let widgetExpiryKey = "auth.widget.expires"
    private static let legacyOwnerKey = "auth.legacy.owner"
    private static let legacyPathKey = "auth.legacy.path"
    static var active: ModelContainer?
    static var shared: ModelContainer {
        guard let active else { fatalError("Account container requested before authentication") }
        return active
    }

    static func accountKey(userID: String, server: String) -> String {
        SHA256.hash(data: Data((server + "\n" + userID.lowercased()).utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
    private static var localBase: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
    private static var groupBase: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }
    private static func legacyURL() -> URL? {
        var candidates: [URL] = []
        if appGroupAvailable { candidates.append(ModelConfiguration(groupContainer: .identifier(appGroupID)).url) }
        candidates.append(ModelConfiguration(groupContainer: .none).url)
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
    static func needsLegacyClaim(account: String) -> Bool {
        UserDefaults.standard.string(forKey: legacyOwnerKey) == nil && legacyURL() != nil
    }
    static func open(account: String, claimLegacy: Bool = false) throws -> ModelContainer {
        let defaults = UserDefaults.standard
        var owner = defaults.string(forKey: legacyOwnerKey)
        var legacy = defaults.string(forKey: legacyPathKey).map { URL(fileURLWithPath: $0) }
        let claiming = claimLegacy && owner == nil
        if claiming { legacy = legacyURL(); owner = account }
        let url: URL
        if let saved = defaults.dictionary(forKey: "auth.store." + account),
           let relative = saved["relative"] as? String, let location = saved["location"] as? String {
            guard let base = location == "group" ? groupBase : localBase else {
                throw CocoaError(.fileReadNoPermission)
            }
            url = base.appendingPathComponent(relative)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw CocoaError(.fileReadNoSuchFile)
            }
        } else if owner == account, let legacy { url = legacy }
        else {
            let folder = (groupBase ?? localBase).appendingPathComponent("Accounts", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            url = folder.appendingPathComponent(account + ".store")
        }
        let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: config)
        // Persist ownership only after successfully opening the existing store. No files are moved or deleted.
        if claiming, let legacy {
            defaults.set(account, forKey: legacyOwnerKey)
            defaults.set(legacy.path, forKey: legacyPathKey)
            defaults.set(defaults.bool(forKey: "hasCompletedOnboarding"), forKey: "onboarding." + account)
        }
        let inGroup = groupBase.map { url.path.hasPrefix($0.path + "/") } ?? false
        let base = inGroup ? groupBase! : localBase
        defaults.set(["location": inGroup ? "group" : "local",
                      "relative": String(url.path.dropFirst(base.path.count + 1))], forKey: "auth.store." + account)
        active = container
        return container
    }
    static func unlockWidget(expiresAt: String) {
        guard let active, let groupBase,
              active.configurations.first?.url.path.hasPrefix(groupBase.path + "/") == true,
              let date = ISO8601DateFormatter().date(from: expiresAt)
                ?? ISO8601DateFormatter.fractional.date(from: expiresAt) else { lockWidget(); return }
        let defaults = UserDefaults(suiteName: appGroupID)
        defaults?.set(active.configurations.first?.url.path, forKey: widgetStoreKey)
        defaults?.set(date.timeIntervalSince1970, forKey: widgetExpiryKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
    static func lockWidget() {
        let defaults = UserDefaults(suiteName: appGroupID)
        defaults?.removeObject(forKey: widgetStoreKey)
        defaults?.removeObject(forKey: widgetExpiryKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
    static func widgetContainer() -> ModelContainer? {
        guard let groupBase, let defaults = UserDefaults(suiteName: appGroupID),
              defaults.double(forKey: widgetExpiryKey) > Date().timeIntervalSince1970,
              let path = defaults.string(forKey: widgetStoreKey),
              URL(fileURLWithPath: path).standardizedFileURL.path.hasPrefix(groupBase.path + "/"),
              FileManager.default.fileExists(atPath: path) else { return nil }
        let config = ModelConfiguration(schema: schema, url: URL(fileURLWithPath: path), allowsSave: false, cloudKitDatabase: .none)
        return try? ModelContainer(for: schema, configurations: config)
    }

    /// 测试 / 预览用内存容器
    static func inMemory() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: config)
    }
}

private extension ISO8601DateFormatter {
    static var fractional: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
