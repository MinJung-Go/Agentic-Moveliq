import Combine
import CryptoKit
import EventKit
import Foundation

@MainActor
final class CalendarPluginService: ObservableObject {
    static let shared = CalendarPluginService()
    let store = EKEventStore()
    @Published private(set) var revision = UUID()
    private var observer: AnyCancellable?
    private var snapshots: [String: CalendarEventSnapshot] = [:]
    private init() {
        observer = NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: store)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in
                self?.revision = UUID()
                NotificationCenter.default.post(name: .coachLifeChanged, object: nil)
            }
    }
    var fullAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    var status: String {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return "完整访问"
        case .writeOnly: return "仅允许添加"
        case .notDetermined: return "尚未授权"
        case .denied: return "访问被拒绝"
        case .restricted: return "访问受限制"
        default: return "请重新授权"
        }
    }
    func authorize() async throws { _ = try await store.requestFullAccessToEvents(); revision = UUID() }
    func reset() { snapshots.removeAll(); revision = UUID() }
    var calendars: [EKCalendar] { fullAccess ? store.calendars(for: .event).sorted { $0.title < $1.title } : [] }
    func selected(_ config: CoachPluginConfiguration) throws -> [EKCalendar] {
        guard fullAccess else { throw CoachPluginError.unavailable("日历查询和管理需要完整访问，请在插件设置中授权。") }
        guard !config.calendarIDs.isEmpty else { throw CoachPluginError.unavailable("请先选择允许查询的日历。") }
        let values = config.calendarIDs.compactMap { store.calendar(withIdentifier: $0) }
        guard values.count == config.calendarIDs.count else { throw CoachPluginError.unavailable("选定日历已失效，请重新选择。") }
        return values
    }
    func events(start: Date, end: Date, config: CoachPluginConfiguration) throws -> [EKEvent] {
        guard end > start, end.timeIntervalSince(start) <= 32 * 86400 else { throw CoachPluginError.invalid }
        let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: try selected(config)))
        guard events.count <= 500 else { throw CoachPluginError.unavailable("日程过多，请缩小查询日期范围。") }
        return events.sorted { $0.startDate < $1.startDate }
    }
    func snapshot(_ event: EKEvent, token: String = UUID().uuidString) -> CalendarEventSnapshot {
        CalendarEventSnapshot(token: token, identifier: event.eventIdentifier ?? "", calendarID: event.calendar.calendarIdentifier,
                              calendarTitle: event.calendar.title, title: event.title ?? "未命名日程", start: event.startDate,
                              end: event.endDate, allDay: event.isAllDay, recurring: event.hasRecurrenceRules, version: version(event))
    }
    func version(_ event: EKEvent) -> String {
        func numbers(_ values: [NSNumber]?) -> String { (values ?? []).map(\.stringValue).joined(separator: ",") }
        let recurrence = (event.recurrenceRules ?? []).map { rule in
            [String(rule.frequency.rawValue), String(rule.interval), String(rule.firstDayOfTheWeek),
             (rule.daysOfTheWeek ?? []).map { "\($0.dayOfTheWeek.rawValue):\($0.weekNumber)" }.joined(separator: ","),
             numbers(rule.daysOfTheMonth), numbers(rule.daysOfTheYear), numbers(rule.weeksOfTheYear), numbers(rule.monthsOfTheYear), numbers(rule.setPositions),
             rule.recurrenceEnd?.endDate.map(CoachLifeTime.iso) ?? "", String(rule.recurrenceEnd?.occurrenceCount ?? 0)].joined(separator: "|")
        }.joined(separator: ";")
        let alarms = (event.alarms ?? []).map { "\($0.relativeOffset)|\($0.absoluteDate.map(CoachLifeTime.iso) ?? "")" }.sorted().joined(separator: ";")
        let fields = [event.eventIdentifier ?? "", event.calendar.calendarIdentifier, event.title ?? "",
                      CoachLifeTime.iso(event.startDate), CoachLifeTime.iso(event.endDate), String(event.isAllDay),
                      event.lastModifiedDate.map(CoachLifeTime.iso) ?? "", event.location ?? "", event.notes ?? "",
                      recurrence, alarms]
        return SHA256.hash(data: Data(fields.map { "\($0.utf8.count):\($0)" }.joined().utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func query(start: Date, end: Date, config: CoachPluginConfiguration, profile: CoachLifeProfile) throws -> String {
        let values = try events(start: start, end: end, config: config)
        // Tokens live only in this account's process; event details stay out of long-term memory.
        if snapshots.count > 1000 { snapshots.removeAll() }
        var lines = ["日历查询于\(CoachLifeTime.iso(.now))；范围\(CoachLifeTime.iso(start))至\(CoachLifeTime.iso(end))；仅覆盖选定日历；共\(values.count)项。"]
        for event in values.prefix(60) {
            let item = snapshot(event); snapshots[item.token] = item
            lines.append("eventToken=\(item.token)；\(String(item.title.prefix(80)))；\(CoachLifeTime.iso(item.start))至\(CoachLifeTime.iso(item.end))；全天=\(item.allDay)；重复=\(item.recurring)")
        }
        if values.count > 60 { lines.append("事件列表截断，不代表完整日程；空闲计算仍使用本次全部\(values.count)项。") }
        let busy = values.map { CoachTimeSlot(start: $0.startDate, end: $0.endDate) }
        var day = Calendar.current.startOfDay(for: start)
        while day < end {
            let slots = CoachLifeTime.freeSlots(on: day, profile: profile, busy: busy)
            for slot in slots.prefix(4) where min(slot.end, end) > max(slot.start, start) {
                lines.append("可用候选（已按用户时段/缓冲扣除忙碌）：\(CoachLifeTime.iso(max(slot.start, start)))至\(CoachLifeTime.iso(min(slot.end, end)))")
            }
            guard let next = Calendar.current.date(byAdding: .day, value: 1, to: day) else { break }; day = next
        }
        if !profile.confirmed || profile.windows.isEmpty { lines.append("训练时段未确认，不能从空白日历推断可训练时间。") }
        return CoachToolClient.bounded(lines.joined(separator: "\n"), bytes: 12_000)
    }
    func resolve(token: String, config: CoachPluginConfiguration) throws -> CalendarEventSnapshot {
        guard let item = snapshots[token], config.calendarIDs.contains(item.calendarID) else { throw CoachPluginError.stale }
        _ = try current(item)
        return item
    }
    func current(_ item: CalendarEventSnapshot) throws -> EKEvent {
        guard fullAccess, let calendar = store.calendar(withIdentifier: item.calendarID) else { throw CoachPluginError.stale }
        let predicate = store.predicateForEvents(withStart: item.start.addingTimeInterval(-1), end: item.end.addingTimeInterval(1), calendars: [calendar])
        guard let event = store.events(matching: predicate).first(where: { $0.eventIdentifier == item.identifier && abs($0.startDate.timeIntervalSince(item.start)) < 1 }),
              version(event) == item.version else { throw CoachPluginError.stale }
        return event
    }
    func validate(_ request: CalendarChangeRequest, target: CalendarEventSnapshot?) throws {
        guard ["create", "update", "delete"].contains(request.action),
              (request.title?.count ?? 0) <= 120, (request.location?.count ?? 0) <= 300,
              request.reminderMinutes == nil || (0...10080).contains(request.reminderMinutes!) else { throw CoachPluginError.invalid }
        if let title = request.title, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw CoachPluginError.invalid }
        if request.action == "create" {
            guard target == nil, let title = request.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  request.start != nil, request.end != nil else { throw CoachPluginError.invalid }
        } else { guard target != nil else { throw CoachPluginError.stale } }
        if request.start != nil || request.end != nil {
            guard let a = request.start.flatMap(CoachLifeTime.date), let b = request.end.flatMap(CoachLifeTime.date),
                  b > a, b.timeIntervalSince(a) <= 32 * 86400 else { throw CoachPluginError.invalid }
        }
        if let recurrence = request.recurrence, recurrence != "none" {
            guard request.action == "create", ["daily", "weekly"].contains(recurrence),
                  let start = request.start.flatMap(CoachLifeTime.date), let until = request.repeatUntil.flatMap(CoachLifeTime.date),
                  until > start, until.timeIntervalSince(start) <= 366 * 86400 else { throw CoachPluginError.invalid }
        }
        if request.repeatUntil != nil, request.recurrence != "daily" && request.recurrence != "weekly" { throw CoachPluginError.invalid }
        if request.action == "delete", request.title != nil || request.start != nil || request.end != nil || request.location != nil || request.recurrence != nil || request.allDay != nil || request.reminderMinutes != nil { throw CoachPluginError.invalid }
        if request.action == "update", request.title == nil && request.start == nil && request.location == nil && request.allDay == nil && request.reminderMinutes == nil { throw CoachPluginError.invalid }
    }
    /// Called only by explicit confirmation, with scope chosen in the card for recurring events.
    func apply(_ request: CalendarChangeRequest, target: CalendarEventSnapshot?, config: CoachPluginConfiguration,
               scope: String, operationID: UUID) throws -> String {
        try validate(request, target: target)
        guard fullAccess else { throw CoachPluginError.unavailable("日历完整访问未授权。") }
        let event: EKEvent
        if request.action == "create" {
            guard let calendar = store.calendar(withIdentifier: config.writeCalendarID), calendar.allowsContentModifications else {
                throw CoachPluginError.unavailable("请在插件设置中选择可写入的日历。")
            }
            let marker = URL(string: "moveliq://calendar/\(operationID.uuidString)")!
            let start = request.start.flatMap(CoachLifeTime.date)!, end = request.end.flatMap(CoachLifeTime.date)!
            if let existing = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: [calendar])).first(where: { $0.url == marker }) {
                return "日程已保存：\(existing.title ?? "日程")，未重复创建。"
            }
            event = EKEvent(eventStore: store); event.calendar = calendar; event.url = marker
        } else {
            guard let target, config.calendarIDs.contains(target.calendarID) else { throw CoachPluginError.stale }
            event = try current(target)
            guard event.calendar.allowsContentModifications else { throw CoachPluginError.unavailable("此日历为只读，未执行修改。") }
        }
        let span: EKSpan
        if event.hasRecurrenceRules {
            guard ["this", "future"].contains(scope) else { throw CoachPluginError.unavailable("请明确选择仅此次或此次及以后。") }
            span = scope == "future" ? .futureEvents : .thisEvent
        } else { span = .thisEvent }
        if request.action == "delete" { try store.remove(event, span: span, commit: true); return "已删除所确认范围的日程。" }
        if let title = request.title { event.title = title }
        if let start = request.start.flatMap(CoachLifeTime.date), let end = request.end.flatMap(CoachLifeTime.date) { event.startDate = start; event.endDate = end }
        if let allDay = request.allDay { event.isAllDay = allDay }
        if let location = request.location { event.location = location }
        if let minutes = request.reminderMinutes { event.alarms = [EKAlarm(relativeOffset: -Double(minutes * 60))] }
        if let recurrence = request.recurrence, recurrence != "none", let until = request.repeatUntil.flatMap(CoachLifeTime.date) {
            event.recurrenceRules = [EKRecurrenceRule(recurrenceWith: recurrence == "daily" ? .daily : .weekly, interval: 1, end: EKRecurrenceEnd(end: until))]
        }
        try store.save(event, span: span, commit: true)
        return "已\(request.action == "create" ? "创建" : "修改")日程：\(event.title ?? "日程")。"
    }
}
