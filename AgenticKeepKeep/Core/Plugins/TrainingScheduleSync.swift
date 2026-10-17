import EventKit
import Foundation
import SwiftData

@MainActor
enum TrainingScheduleSync {
    private struct Desired: Codable, Equatable {
        var title: String
        var start: Date
        var minutes: Int
        var remove: Bool
        var calendar: Bool
        var alarm: Bool
        var calendarID: String
        var reminder: Int
        var automationRuleID: UUID?
        var automationRecordID: UUID?
    }
    private static var running = false
    /// Called only after accepting a concrete plan/change, or after explicit retry.
    static func enqueue(planID: UUID, context: ModelContext, dayIDs: Set<UUID>? = nil, automation: CoachAutomationRecord? = nil) throws {
        try context.save()
        do {
            let config = try CoachLifeStore.plugins(context)
            let plans = try context.fetch(FetchDescriptor<Plan>())
            let plan = plans.first { $0.uuid == planID }
            var links = try context.fetch(FetchDescriptor<CoachTrainingLink>()).filter { $0.planID == planID }
            if plan?.isActive == true && (config.syncTrainingCalendar || config.syncTrainingAlarms || !links.isEmpty) {
                for day in plan?.days ?? [] where day.status == .pending {
                    if let dayIDs, !dayIDs.contains(day.uuid) { continue }
                    guard let start = day.scheduledStart, let minutes = day.durationMinutes, start > .now else { continue }
                    if !links.contains(where: { $0.dayID == day.uuid }) {
                        guard config.syncTrainingCalendar || config.syncTrainingAlarms else { continue }
                        let link = CoachTrainingLink(planID: planID, dayID: day.uuid); context.insert(link); links.append(link)
                    }
                    let link = links.first { $0.dayID == day.uuid }!
                    let desired = Desired(title: day.title, start: start, minutes: minutes, remove: false,
                        calendar: config.syncTrainingCalendar, alarm: config.syncTrainingAlarms,
                        calendarID: config.writeCalendarID, reminder: config.reminderMinutes,
                        automationRuleID: automation?.ruleID, automationRecordID: automation?.uuid)
                    let json = try CoachLifeStore.encode(desired)
                    if desired.calendar {
                        if !link.eventLookupDates.contains(start) { link.eventLookupDates.append(start) }
                        if link.eventCalendarID.isEmpty { link.eventCalendarID = desired.calendarID }
                    }
                    let previous = CoachLifeStore.decode(Desired.self, link.desiredJSON)
                    if previous != desired {
                        link.desiredJSON = json; link.pending = true; link.calendarReceipt = ""; link.alarmReceipt = ""; link.error = ""
                        let alarmChanged = previous?.alarm != desired.alarm || previous?.start != desired.start || previous?.title != desired.title || previous?.reminder != desired.reminder || previous?.remove == true
                        if alarmChanged {
                            if let old = link.alarmID, !link.retiredAlarmIDs.contains(old) { link.retiredAlarmIDs.append(old) }
                            link.alarmID = desired.alarm ? UUID() : nil
                        }
                    }
                }
            }
            for link in links {
                if let dayIDs, !dayIDs.contains(link.dayID) { continue }
                let day = plan?.days.first { $0.uuid == link.dayID }
                guard day == nil || day?.status == .skipped || plan?.isActive != true else { continue }
                guard var desired = CoachLifeStore.decode(Desired.self, link.desiredJSON), !desired.remove else { continue }
                guard desired.start > .now, day?.status != .done else { continue }
                desired.remove = true; desired.automationRuleID = automation?.ruleID; desired.automationRecordID = automation?.uuid
                link.desiredJSON = try CoachLifeStore.encode(desired)
                link.pending = true; link.calendarReceipt = ""; link.alarmReceipt = ""
            }
            try context.save()
        } catch { context.rollback(); throw error }
    }
    static func retry(context: ModelContext) async -> String {
        guard !running else { return "正在同步，请稍后。" }
        running = true; defer { running = false }
        let token = ServiceCredentials.session?.token
        do {
            try CoachLifeStore.checkAccount(context: context, token: token)
            let links = try context.fetch(FetchDescriptor<CoachTrainingLink>()).filter(\.pending).sorted {
                let a = CoachLifeStore.decode(Desired.self, $0.desiredJSON)?.remove == true
                let b = CoachLifeStore.decode(Desired.self, $1.desiredJSON)?.remove == true
                return a != b ? a : $0.uuid.uuidString < $1.uuid.uuidString
            }
            var failures = 0, successes = 0
            for link in links {
                do {
                    try Task.checkCancellation(); try CoachLifeStore.checkAccount(context: context, token: token)
                    guard let desired = CoachLifeStore.decode(Desired.self, link.desiredJSON) else { throw CoachPluginError.invalid }
                    try validateCurrent(link, desired: desired, context: context)
                    if (desired.calendar || !link.eventID.isEmpty || !link.eventLookupDates.isEmpty) && link.calendarReceipt.isEmpty {
                        try CoachLifeStore.require(.calendar, context: context, token: token)
                        try syncCalendar(link, desired: desired)
                        link.calendarReceipt = desired.remove || !desired.calendar ? "关联日程已移除" : "日历已同步"
                        try context.save()
                    }
                    if (desired.alarm || link.alarmID != nil || !link.retiredAlarmIDs.isEmpty) && link.alarmReceipt.isEmpty {
                        try validateCurrent(link, desired: desired, context: context)
                        try CoachLifeStore.require(.alarms, context: context, token: token)
                        if desired.remove || !desired.alarm {
                            if let id = link.alarmID { try AlarmPluginService.cancel(id) }
                        } else {
                            guard let id = link.alarmID else { throw CoachPluginError.invalid }
                            let at = desired.start.addingTimeInterval(-Double(desired.reminder * 60))
                            guard at > .now else { throw CoachPluginError.unavailable("训练提醒时间已过，未补建过期闹钟，请重新安排。") }
                            let request = AlarmChangeRequest(action: "create", title: desired.title, date: CoachLifeTime.iso(at))
                            try await AlarmPluginService.schedule(request, id: id)
                            // The stable alarm ID makes a retry safe even if authority changes while awaiting the API.
                            try CoachLifeStore.require(.alarms, context: context, token: token)
                            try validateCurrent(link, desired: desired, context: context)
                        }
                        for old in link.retiredAlarmIDs { try AlarmPluginService.cancel(old) }
                        link.retiredAlarmIDs = []
                        if desired.remove || !desired.alarm { link.alarmID = nil }
                        link.alarmReceipt = desired.remove || !desired.alarm ? "关联闹钟已取消" : "闹钟已安排"
                        try context.save()
                    }
                    link.pending = false; link.error = ""; try context.save(); successes += 1
                } catch {
                    link.error = error.localizedDescription; try? context.save(); failures += 1
                    if token != ServiceCredentials.session?.token { break }
                }
            }
            return links.isEmpty ? "没有待同步项目。" : "同步完成\(successes)项，\(failures)项待处理。课程表已保留；失败项可单独重试。"
        } catch { return "同步未完成：\(error.localizedDescription)" }
    }
    private static func validateCurrent(_ link: CoachTrainingLink, desired: Desired, context: ModelContext) throws {
        let plan = try context.fetch(FetchDescriptor<Plan>()).first { $0.uuid == link.planID }
        try validateAutomationAuthority(link, context: context)
        let day = plan?.days.first { $0.uuid == link.dayID }
        if desired.remove {
            guard desired.start > .now, day == nil || day?.status == .skipped || plan?.isActive != true else { throw CoachPluginError.stale }
        } else {
            guard plan?.isActive == true, day?.status == .pending, day?.scheduledStart == desired.start,
                  day?.durationMinutes == desired.minutes, day?.title == desired.title else { throw CoachPluginError.stale }
            let moving = Set(try context.fetch(FetchDescriptor<CoachTrainingLink>()).filter(\.pending).map(\.dayID))
            try CoachScheduleGuard.validate(start: desired.start, minutes: desired.minutes, excluding: link.dayID, excludingCalendarDayIDs: moving, context: context)
        }
        let config = try CoachLifeStore.plugins(context)
        if desired.calendar, !desired.remove {
            guard config.syncTrainingCalendar, config.writeCalendarID == desired.calendarID else { throw CoachPluginError.stale }
            if !link.calendarReceipt.isEmpty, !link.eventID.isEmpty {
                guard let event = CalendarPluginService.shared.store.event(withIdentifier: link.eventID),
                      CalendarPluginService.shared.version(event) == link.eventVersion else { throw CoachPluginError.stale }
            }
        }
        if desired.alarm, !desired.remove, !config.syncTrainingAlarms { throw CoachPluginError.stale }
    }
    static func validateAutomationAuthority(_ link: CoachTrainingLink, context: ModelContext) throws {
        guard let desired = CoachLifeStore.decode(Desired.self, link.desiredJSON) else { throw CoachPluginError.invalid }
        let plan = try context.fetch(FetchDescriptor<Plan>()).first { $0.uuid == link.planID }
        if let ruleID = desired.automationRuleID {
            let rules = try CoachLifeStore.automationRules(context)
            let record = try context.fetch(FetchDescriptor<CoachAutomationRecord>()).first { $0.uuid == desired.automationRecordID }
            guard rules.enabled, rules.isValid, rules.revision == ruleID,
                  rules.validUntil == nil || rules.validUntil! > .now,
                  rules.planIDs.contains(link.planID), record?.restoredAt == nil,
                  let plan, record?.afterRevision == PlanMutationStore.revision(plan),
                  (!desired.calendar && link.eventID.isEmpty && link.eventLookupDates.isEmpty || rules.syncCalendar),
                  (!desired.alarm && link.alarmID == nil && link.retiredAlarmIDs.isEmpty || rules.syncAlarms) else {
                throw CoachPluginError.unavailable("自动同步授权已变化或失效。课程表和已完成步骤保留，请查看本次结果后单次确认剩余同步。")
            }
        }
    }

    /// Explicit confirmation of a displayed result grants only this batch's remaining steps.
    static func confirmRemaining(_ record: CoachAutomationRecord, context: ModelContext) throws {
        try CoachLifeStore.checkAccount(context: context, token: ServiceCredentials.session?.token)
        guard let plan = try context.fetch(FetchDescriptor<Plan>()).first(where: { $0.uuid == record.planID }),
              plan.isActive, PlanMutationStore.revision(plan) == record.afterRevision,
              record.restoredAt == nil,
              let days = CoachLifeStore.decode([CoachAutomationDay].self, record.afterJSON) else { throw CoachPluginError.stale }
        let IDs = Set(days.map(\.id))
        let links = try context.fetch(FetchDescriptor<CoachTrainingLink>()).filter { IDs.contains($0.dayID) && $0.pending }
        // Recover a local commit whose queue could not be saved; no local mutation is repeated.
        if links.isEmpty { try enqueue(planID: plan.uuid, context: context, dayIDs: IDs); return }
        try context.save()
        do {
            for link in links {
                guard var desired = CoachLifeStore.decode(Desired.self, link.desiredJSON),
                      desired.automationRecordID == nil || desired.automationRecordID == record.uuid else { throw CoachPluginError.stale }
                desired.automationRuleID = nil; desired.automationRecordID = nil
                try validateCurrent(link, desired: desired, context: context)
                link.desiredJSON = try CoachLifeStore.encode(desired)
            }
            try context.save()
        } catch { context.rollback(); throw error }
    }
    private static func syncCalendar(_ link: CoachTrainingLink, desired: Desired) throws {
        let service = CalendarPluginService.shared, store = service.store
        guard service.fullAccess else { throw CoachPluginError.unavailable("日历完整访问未授权，课程表已保留。") }
        let marker = URL(string: "moveliq://training/\(link.uuid.uuidString)")!
        let event: EKEvent
        if !link.eventID.isEmpty {
            guard let existing = store.event(withIdentifier: link.eventID), existing.url == marker,
                  service.version(existing) == link.eventVersion, !existing.hasRecurrenceRules else { throw CoachPluginError.stale }
            event = existing
        } else {
            let lookupIDs = Set([link.eventCalendarID, desired.calendarID].filter { !$0.isEmpty })
            let lookupCalendars = lookupIDs.compactMap { store.calendar(withIdentifier: $0) }
            guard !lookupCalendars.isEmpty, lookupCalendars.count == lookupIDs.count else { throw CoachPluginError.stale }
            var found: [String: EKEvent] = [:]
            for date in Set(link.eventLookupDates + [desired.start]) {
                let predicate = store.predicateForEvents(withStart: date.addingTimeInterval(-86400), end: date.addingTimeInterval(2 * 86400), calendars: lookupCalendars)
                for candidate in store.events(matching: predicate) where candidate.url == marker { found[candidate.eventIdentifier ?? ""] = candidate }
            }
            guard found.count <= 1 else { throw CoachPluginError.stale }
            if let recovered = found.values.first { event = recovered }
            else {
                if desired.remove || !desired.calendar { link.eventLookupDates = []; return }
                guard let calendar = store.calendar(withIdentifier: desired.calendarID), calendar.allowsContentModifications else {
                    throw CoachPluginError.unavailable("关联日历不可写，请重新选择。")
                }
                event = EKEvent(eventStore: store)
                event.calendar = calendar; event.url = marker
            }
        }
        guard event.calendar.allowsContentModifications else { throw CoachPluginError.unavailable("关联日历只读。") }
        if desired.remove || !desired.calendar {
            try store.remove(event, span: .thisEvent, commit: true)
            link.eventID = ""; link.eventVersion = ""; link.eventStart = nil; link.eventLookupDates = []; return
        }
        guard desired.start > .now else { throw CoachPluginError.unavailable("训练时间已过，请重新确认未来安排。") }
        guard let calendar = store.calendar(withIdentifier: desired.calendarID), calendar.allowsContentModifications else {
            throw CoachPluginError.unavailable("所选日历不可写，请重新选择后安排。")
        }
        event.calendar = calendar
        event.title = desired.title; event.startDate = desired.start
        event.endDate = desired.start.addingTimeInterval(Double(desired.minutes * 60))
        event.alarms = [EKAlarm(relativeOffset: -Double(desired.reminder * 60))]
        try store.save(event, span: .thisEvent, commit: true)
        link.eventID = event.eventIdentifier ?? ""; link.eventCalendarID = event.calendar.calendarIdentifier
        link.eventStart = event.startDate; link.eventVersion = service.version(event)
        link.eventLookupDates = [desired.start]
    }
}
