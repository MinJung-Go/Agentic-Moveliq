import Foundation
import SwiftUI
#if canImport(AlarmKit)
import AlarmKit

@available(iOS 26.0, *)
private struct MoveliqAlarmMetadata: AlarmMetadata { var title: String }
#endif

@MainActor
enum AlarmPluginService {
    static var available: Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }
    static var status: String {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            switch AlarmManager.shared.authorizationState {
            case .authorized: return "已授权"
            case .denied: return "访问被拒绝"
            case .notDetermined: return "尚未授权"
            @unknown default: return "暂不可用"
            }
        }
        #endif
        return "需要 iOS 26 或更新版本"
    }
    static var connectionAccess: ServiceConnectionAccess {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            switch AlarmManager.shared.authorizationState {
            case .authorized: return .authorized
            case .denied: return .denied
            case .notDetermined: return .notDetermined
            @unknown default: return .unavailable
            }
        }
        #endif
        return .unavailable
    }
    static func authorize() async throws {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { _ = try await AlarmManager.shared.requestAuthorization(); return }
        #endif
        throw CoachPluginError.unavailable(status)
    }
    static func scheduledIDs() throws -> Set<UUID> {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return Set(try AlarmManager.shared.alarms.map(\.id)) }
        #endif
        throw CoachPluginError.unavailable(status)
    }
    static func cancel(_ id: UUID) throws {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            if try scheduledIDs().contains(id) { try AlarmManager.shared.cancel(id: id) }; return
        }
        #endif
        throw CoachPluginError.unavailable(status)
    }
    static func validate(_ request: AlarmChangeRequest) throws {
        guard ["create", "cancel", "update"].contains(request.action), (request.title?.count ?? 0) <= 120 else { throw CoachPluginError.invalid }
        if request.action == "cancel" { guard request.alarmID.flatMap(UUID.init(uuidString:)) != nil else { throw CoachPluginError.invalid }; return }
        if request.action == "update", request.alarmID.flatMap(UUID.init(uuidString:)) == nil { throw CoachPluginError.invalid }
        guard let title = request.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CoachPluginError.invalid }
        if let minutes = request.countdownMinutes {
            guard (1...1440).contains(minutes), request.date == nil, request.time == nil, request.weekdays?.isEmpty != false else { throw CoachPluginError.invalid }
        } else if let weekdays = request.weekdays, !weekdays.isEmpty {
            guard weekdays.count <= 7, Set(weekdays).count == weekdays.count, weekdays.allSatisfy({ (1...7).contains($0) }),
                  request.time.flatMap(CoachLifeTime.minute) != nil, request.date == nil else { throw CoachPluginError.invalid }
        } else {
            guard request.time == nil, let date = request.date.flatMap(CoachLifeTime.date), date > .now, date.timeIntervalSinceNow < 366 * 86400 else { throw CoachPluginError.invalid }
        }
    }
    /// Countdown requests use a fixed alarm, so no unsupported countdown Live Activity is advertised.
    static func schedule(_ request: AlarmChangeRequest, id: UUID) async throws {
        try validate(request)
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            guard AlarmManager.shared.authorizationState == .authorized else { throw CoachPluginError.unavailable("请先在插件设置中允许闹钟提醒。") }
            if try scheduledIDs().contains(id) { return } // idempotent resume after a saved system write
            let schedule: Alarm.Schedule
            if let minutes = request.countdownMinutes { schedule = .fixed(Date().addingTimeInterval(Double(minutes * 60))) }
            else if let days = request.weekdays, !days.isEmpty, let minute = request.time.flatMap(CoachLifeTime.minute) {
                let mapping: [Int: Locale.Weekday] = [1: .sunday, 2: .monday, 3: .tuesday, 4: .wednesday, 5: .thursday, 6: .friday, 7: .saturday]
                schedule = .relative(.init(time: .init(hour: minute / 60, minute: minute % 60), repeats: .weekly(days.compactMap { mapping[$0] })))
            } else { schedule = .fixed(request.date.flatMap(CoachLifeTime.date)!) }
            let title = request.title ?? "Moveliq"
            let alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: title),
                stopButton: AlarmButton(text: "停止", textColor: .white, systemImageName: "stop.fill"))
            let attributes = AlarmAttributes(presentation: AlarmPresentation(alert: alert), metadata: MoveliqAlarmMetadata(title: title), tintColor: Color.orange)
            let configuration = AlarmManager.AlarmConfiguration.alarm(schedule: schedule, attributes: attributes)
            _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
            return
        }
        #endif
        throw CoachPluginError.unavailable(status)
    }
}
