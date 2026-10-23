import Foundation
import SwiftData

@MainActor
enum CoachLifeStore {
    static func workspace(_ context: ModelContext) throws -> CoachWorkspace {
        var fetch = FetchDescriptor<CoachWorkspace>(); fetch.fetchLimit = 1
        if let value = try context.fetch(fetch).first { return value }
        let value = CoachWorkspace(); context.insert(value); try context.save(); return value
    }
    static func profile(_ context: ModelContext) throws -> CoachLifeProfile {
        decode(CoachLifeProfile.self, try workspace(context).profileJSON) ?? CoachLifeProfile()
    }
    static func plugins(_ context: ModelContext) throws -> CoachPluginConfiguration {
        decode(CoachPluginConfiguration.self, try workspace(context).pluginsJSON) ?? CoachPluginConfiguration()
    }
    static func automationRules(_ context: ModelContext) throws -> CoachAutomationRules {
        decode(CoachAutomationRules.self, try workspace(context).automationJSON) ?? CoachAutomationRules()
    }
    /// Saved only by the user-owned settings adapter, never an Agent tool.
    static func save(automationRules rules: CoachAutomationRules, in context: ModelContext) throws {
        guard rules.isValid else { throw CoachPluginError.invalid }
        let value = try workspace(context), previous = value.automationJSON
        var updated = rules; updated.revision = UUID()
        value.automationJSON = try encode(updated)
        do { try context.save() } catch { value.automationJSON = previous; throw error }
        NotificationCenter.default.post(name: .coachLifeChanged, object: nil)
    }
    static func save(profile: CoachLifeProfile, in context: ModelContext) throws {
        guard profile.isValid else { throw CoachPluginError.invalid }
        let value = try workspace(context); let previous = value.profileJSON
        value.profileJSON = try encode(profile); value.updatedAt = .now
        do { try context.save() } catch { value.profileJSON = previous; throw error }
        NotificationCenter.default.post(name: .coachLifeChanged, object: nil)
    }
    static func save(plugins: CoachPluginConfiguration, in context: ModelContext) throws {
        guard plugins.calendarIDs.count <= 30, (0...120).contains(plugins.reminderMinutes) else { throw CoachPluginError.invalid }
        let value = try workspace(context); let previous = value.pluginsJSON
        value.pluginsJSON = try encode(plugins); value.updatedAt = .now
        do { try context.save() } catch { value.pluginsJSON = previous; throw error }
        NotificationCenter.default.post(name: .coachLifeChanged, object: nil)
    }
    static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
    static func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T? { try? JSONDecoder().decode(type, from: Data(json.utf8)) }
    static func action(kind: String, payload: CoachActionPayload, in context: ModelContext, conversationID: UUID? = nil) throws -> CoachActionRecord {
        let json = try encode(payload)
        guard json.utf8.count <= 24_000 else { throw CoachPluginError.invalid }
        func identity(_ value: CoachActionPayload) -> CoachActionPayload {
            var value = value; value.reason = ""; value.event?.token = ""; value.calendar?.eventToken = nil
            return value
        }
        let candidates = try context.fetch(FetchDescriptor<CoachActionRecord>())
        if let existing = candidates.first(where: { $0.conversationID == conversationID && $0.kind == kind && decode(CoachActionPayload.self, $0.payloadJSON).map(identity) == identity(payload) && $0.state == "pending" && $0.expiresAt > .now }) { return existing }
        let value = CoachActionRecord(kind: kind, payloadJSON: json)
        value.conversationID = conversationID
        context.insert(value)
        do { try context.save() } catch { context.delete(value); throw error }
        return value
    }
    static func checkAccount(context: ModelContext, token: String?) throws {
        guard token != nil, token == ServiceCredentials.session?.token, AppModelContainer.active === context.container else { throw CoachPluginError.accountChanged }
    }
    static func require(_ plugin: CoachPlugin, context: ModelContext, token: String?) throws {
        try checkAccount(context: context, token: token)
        guard try plugins(context).enabled.contains(plugin) else { throw CoachPluginError.unavailable("\(plugin.title)插件未启用。") }
    }
}

extension Notification.Name {
    static let coachLifeChanged = Notification.Name("moveliq.coach.life.changed")
}
