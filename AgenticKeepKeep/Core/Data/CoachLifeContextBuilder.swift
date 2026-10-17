import CryptoKit
import Foundation
import SwiftData

@MainActor
enum CoachLifeContextBuilder {
    static func revision(context: ModelContext, now: Date = .now, includePlans: Bool = true, includeCalendarRevision: Bool = true) throws -> String {
        let workspace = try CoachLifeStore.workspace(context)
        let checks = try context.fetch(FetchDescriptor<CoachCheckIn>()).filter { $0.kind == "feedback" || ($0.kind == "temporary" && $0.expiresAt > now) }
        let plans = try context.fetch(FetchDescriptor<Plan>()).filter(\.isActive)
        let fields = [workspace.profileJSON, workspace.pluginsJSON, workspace.automationJSON, CoachLifeTime.iso(Calendar.current.startOfDay(for: now)), HealthKitService.shared.lastSyncDate.map(CoachLifeTime.iso) ?? ""]
            + checks.sorted { $0.uuid.uuidString < $1.uuid.uuidString }.map { "\($0.uuid)|\($0.minutes)|\($0.availableMinutes ?? -1)|\($0.difficulty)|\($0.timing)|\($0.expiresAt.timeIntervalSince1970)|\($0.kind == "temporary" ? $0.note : "")" }
        let state = fields + (includeCalendarRevision ? [CalendarPluginService.shared.revision.uuidString] : []) + (includePlans ? plans.map { PlanMutationStore.revision($0) }.sorted() : [])
        var digest = try DataAggregator.digest(days: 14, endingAt: now, context: context)
        digest.trends.sort { $0.name < $1.name }
        let data = state.map { "\($0.utf8.count):\($0)" }.joined() + (try CoachLifeStore.encode(digest))
        return SHA256.hash(data: Data(data.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func summary(context: ModelContext, days: Int = 7, now: Date = .now) throws -> String {
        guard (1...14).contains(days) else { throw CoachPluginError.invalid }
        let profile = try CoachLifeStore.profile(context), config = try CoachLifeStore.plugins(context)
        var lines = ["本次生活摘要时间：\(CoachLifeTime.iso(now))", profile.summary]
        lines.append(try CoachLifeStore.automationRules(context).summary)
        let checks = try context.fetch(FetchDescriptor<CoachCheckIn>(sortBy: [SortDescriptor(\.date, order: .reverse)]))
        let active = checks.filter { $0.kind == "temporary" && $0.expiresAt > now }.prefix(5)
        lines += active.map { "用户临时反馈（至\(CoachLifeTime.iso($0.expiresAt))有效）：\(String($0.note.prefix(300)))\($0.availableMinutes.map { "；单次最多\($0)分钟" } ?? "")" }
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        let recent = checks.filter { $0.kind == "feedback" && $0.date >= weekAgo }.prefix(7)
        if !recent.isEmpty {
            lines.append("近7天共\(recent.count)次训练反馈，\(recent.filter { $0.difficulty == "偏难" }.count)次偏难，\(recent.filter { $0.timing != "合适" && !$0.timing.isEmpty }.count)次时间安排需改善；文字反馈保留本机，不上传逐条原文。")
        }
        let health = try CoachContextBuilder.profileText(context: context, days: 14, now: now)
        lines.append(CoachToolClient.bounded(health, bytes: 6500))
        if config.enabled.contains(.calendar) {
            let start = Calendar.current.startOfDay(for: now)
            let end = Calendar.current.date(byAdding: .day, value: days, to: start) ?? now
            do { lines.append(try CalendarPluginService.shared.query(start: start, end: end, config: config, profile: profile)) }
            catch { lines.append("日历未获取：\(error.localizedDescription)。不能声称已核对冲突。") }
        } else { lines.append("日历插件关闭，仅依据用户已确认的训练时段；未核对外部日程。") }
        lines.append("规划时遵守硬限制与缓冲，不挤满空白；疲惫/疼痛以用户反馈为准，不生成伪精确恢复分。不堆叠补课。提案确认前未更改任何计划/日程。")
        return CoachToolClient.bounded(lines.joined(separator: "\n"), bytes: 22_000)
    }

    struct Signal: Identifiable {
        var id: String
        var title: String
        var detail: String
        var prompt: String
    }
    static func signals(context: ModelContext, now: Date = .now) throws -> [Signal] {
        let profile = try CoachLifeStore.profile(context), config = try CoachLifeStore.plugins(context)
        guard profile.confirmed else { return [Signal(id: "profile", title: "先了解你的日常", detail: "确认目标、器械和可用时段，再安排可执行的训练。", prompt: "先帮我了解目标与生活约束，每次只问最关键的一两个问题，再规划训练。")] }
        let start = Calendar.current.startOfDay(for: now)
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? now
        let plans = try context.fetch(FetchDescriptor<Plan>()).filter(\.isActive)
        let days = plans.flatMap(\.days).filter { $0.status == .pending && $0.date < end }.sorted { $0.date < $1.date }
        var signals: [Signal] = []
        let links = try context.fetch(FetchDescriptor<CoachTrainingLink>())
        if config.enabled.contains(.calendar), CalendarPluginService.shared.fullAccess {
            do {
                let events = try CalendarPluginService.shared.events(start: start, end: end, config: config)
                for day in days {
                    guard let at = day.scheduledStart, let minutes = day.durationMinutes, at > now else { continue }
                    let own = links.first { $0.dayID == day.uuid }
                    if let own, !own.pending, !own.eventID.isEmpty {
                        let linked = CalendarPluginService.shared.store.event(withIdentifier: own.eventID)
                        if linked == nil || linked.map({ CalendarPluginService.shared.version($0) }) != own.eventVersion {
                            signals.append(Signal(id: "linked-\(own.uuid)-\(CalendarPluginService.shared.revision)", title: "关联训练日程已变化", detail: "\(day.title)的系统日程被修改或移除，请先核对，避免覆盖你的安排。", prompt: "先查询最新课程表、生活摘要与日历，和我核对训练日\(day.uuid)关联日程的外部变化，只提出必要调整，等待确认。"))
                        }
                    }
                    let conflicts = events.filter { event in
                        !(event.eventIdentifier == own?.eventID && abs(event.startDate.timeIntervalSince(own?.eventStart ?? .distantPast)) < 1)
                        && event.startDate < at.addingTimeInterval(Double((minutes + profile.bufferMinutes) * 60))
                        && event.endDate > at.addingTimeInterval(-Double(profile.bufferMinutes * 60))
                    }
                    if !conflicts.isEmpty {
                        let signature = conflicts.map { CalendarPluginService.shared.version($0) }.sorted().joined()
                        let hash = SHA256.hash(data: Data(signature.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
                        signals.append(Signal(id: "conflict-\(day.uuid)-\(hash)", title: "\(day.title)与日程冲突", detail: "\(CoachLifeTime.display(at)) 的训练或准备时间被占用。", prompt: "重新查询最新生活/日历和课程表，检查训练日\(day.uuid)的时间冲突，只调整受影响的未来安排并解释变化，等待我确认。"))
                    }
                }
            } catch { signals.append(Signal(id: "calendar-unavailable", title: "日历检查尚未完成", detail: error.localizedDescription, prompt: "结合已确认的约束规划，明确当前日历数据未取得，不声称已经核对冲突。")) }
        }
        for day in days where day.date < start {
            signals.append(Signal(id: "unconfirmed-\(day.uuid)", title: "\(day.title)尚未确认完成", detail: "先核对是漏记还是未训练，再决定后续安排。", prompt: "训练日\(day.uuid)仍待完成，请先问我实际是否练过，再根据最新日常约束调整，不能把漏记当作没运动，不堆叠补课。"))
        }
        let checks = try context.fetch(FetchDescriptor<CoachCheckIn>(sortBy: [SortDescriptor(\.date, order: .reverse)]))
        for check in checks.filter({ $0.kind == "temporary" && $0.expiresAt > now }).prefix(3) {
            signals.append(Signal(id: "temporary-\(check.uuid)", title: "今天的情况有变化", detail: check.note, prompt: "根据仍有效的临时反馈重新查询生活摘要和计划，只提出必要调整，保留原计划选项。"))
        }
        if let recent = checks.first(where: { $0.kind == "feedback" && $0.date >= start && ($0.difficulty == "偏难" || $0.timing != "合适") }) {
            signals.append(Signal(id: "feedback-\(recent.uuid)", title: "下一次安排可以再优化", detail: "你反馈了本次难度或时间安排需要调整。", prompt: "先查询最新生活摘要与训练后反馈汇总，和我核对下一次的时长、难度和安排，仅生成必要的待确认调整。"))
        }
        let dismissed = Set(checks.filter { $0.kind == "dismissed" && $0.expiresAt > now }.map(\.note))
        return Array(signals.filter { !dismissed.contains($0.id) }.prefix(6))
    }
    static func dismiss(_ signal: Signal, context: ModelContext) throws {
        let value = CoachCheckIn(kind: "dismissed", note: signal.id, expiresAt: Date().addingTimeInterval(7 * 86400))
        context.insert(value); try context.save()
    }
}

@MainActor
enum CoachScheduleGuard {
    static func validate(start: Date, minutes: Int, excluding dayID: UUID? = nil, excludingDayIDs: Set<UUID> = [], excludingCalendarDayIDs: Set<UUID> = [], context: ModelContext) throws {
        let profile = try CoachLifeStore.profile(context), config = try CoachLifeStore.plugins(context)
        guard profile.confirmed, profile.isValid, (10...180).contains(minutes), start > .now,
              let window = profile.windows.first(where: { $0.weekday == Calendar.current.component(.weekday, from: start) }),
              let earliest = CoachLifeTime.at(minute: window.startMinute, on: start), let latest = CoachLifeTime.at(minute: window.endMinute, on: start),
              start >= earliest.addingTimeInterval(Double(profile.bufferMinutes * 60)),
              start.addingTimeInterval(Double((minutes + profile.bufferMinutes) * 60)) <= latest else {
            throw CoachPluginError.unavailable("具体时段不符合已确认的训练窗口/准备缓冲，或时间已过，请重新安排。")
        }
        let weekday = Calendar.current.component(.weekday, from: start)
        let from = start.addingTimeInterval(-Double(profile.bufferMinutes * 60))
        let until = start.addingTimeInterval(Double((minutes + profile.bufferMinutes) * 60))
        for protected in profile.protectedTimes where protected.weekday == weekday {
            if let a = CoachLifeTime.at(minute: protected.startMinute, on: start), let b = CoachLifeTime.at(minute: protected.endMinute, on: start), from < b, until > a {
                throw CoachPluginError.unavailable("训练或准备时间占用了你保护的时段：\(protected.label)。请重新安排。")
            }
        }
        let temporary = try context.fetch(FetchDescriptor<CoachCheckIn>()).filter { $0.kind == "temporary" && $0.date <= start && $0.expiresAt > start }
        if let limit = temporary.compactMap(\.availableMinutes).min(), minutes > limit {
            throw CoachPluginError.unavailable("当前有效反馈限定单次最多\(limit)分钟，请缩短训练或重新确认限制。")
        }
        let otherDays = try context.fetch(FetchDescriptor<Plan>()).filter(\.isActive).flatMap(\.days)
        for other in otherDays where other.status == .pending && other.uuid != dayID && !excludingDayIDs.contains(other.uuid) {
            if let at = other.scheduledStart, let duration = other.durationMinutes,
               at < until, at.addingTimeInterval(Double(duration * 60)) > from {
                throw CoachPluginError.unavailable("训练或准备时间与其他已确认训练重叠，请重新安排。")
            }
        }
        guard config.enabled.contains(.calendar) else { return }
        let links = try context.fetch(FetchDescriptor<CoachTrainingLink>())
        let own = links.filter { $0.dayID == dayID || excludingDayIDs.contains($0.dayID) || excludingCalendarDayIDs.contains($0.dayID) }
        for link in own where !link.eventID.isEmpty {
            guard let event = CalendarPluginService.shared.store.event(withIdentifier: link.eventID),
                  CalendarPluginService.shared.version(event) == link.eventVersion else { throw CoachPluginError.stale }
        }
        let events = try CalendarPluginService.shared.events(start: from, end: until, config: config)
        guard !events.contains(where: { event in
            !own.contains(where: { event.eventIdentifier == $0.eventID && abs(event.startDate.timeIntervalSince($0.eventStart ?? .distantPast)) < 1 })
            && event.startDate < until && event.endDate > from
        }) else { throw CoachPluginError.unavailable("相关日历现在有冲突，请重新查询后调整时间。") }
    }
    static func validate(_ draft: PlanDraft, context: ModelContext) throws {
        var proposed: [CoachTimeSlot] = []
        let replacedDays = Set(try context.fetch(FetchDescriptor<Plan>()).filter(\.isActive).flatMap(\.days).filter { $0.status == .pending }.map(\.uuid))
        for day in draft.days {
            guard let text = day.startTime else { continue }
            guard let minute = CoachLifeTime.minute(text), let duration = day.durationMinutes,
                  let date = Calendar.current.date(byAdding: .day, value: day.dayOffset, to: Calendar.current.startOfDay(for: .now)),
                  let start = CoachLifeTime.at(minute: minute, on: date) else { throw CoachPluginError.invalid }
            try validate(start: start, minutes: duration, excludingDayIDs: replacedDays, context: context)
            let slot = CoachTimeSlot(start: start, end: start.addingTimeInterval(Double(duration * 60)))
            guard !proposed.contains(where: { $0.start < slot.end && $0.end > slot.start }) else { throw CoachPluginError.invalid }
            proposed.append(slot)
        }
    }
    static func validate(_ draft: PlanAdjustmentDraft, context: ModelContext) throws {
        let plans = try context.fetch(FetchDescriptor<Plan>())
        guard let plan = plans.first(where: { $0.uuid.uuidString.caseInsensitiveCompare(draft.planID ?? "") == .orderedSame }) else { throw CoachPluginError.stale }
        let changing = Set(draft.changes.filter { ["update", "reschedule", "skip", "delete_day"].contains($0.action) }.compactMap { $0.dayID.flatMap(UUID.init(uuidString:)) })
        var finalSlots = plan.days.filter { !changing.contains($0.uuid) && $0.status == .pending }.compactMap { day -> CoachTimeSlot? in
            guard let start = day.scheduledStart, let minutes = day.durationMinutes, start > .now else { return nil }
            return CoachTimeSlot(start: start, end: start.addingTimeInterval(Double(minutes * 60)))
        }
        for change in draft.changes where change.action == "reschedule" || change.action == "update" || change.action == "add_day" {
            let day = plan.days.first { $0.uuid.uuidString.caseInsensitiveCompare(change.dayID ?? "") == .orderedSame }
            let date = change.date.flatMap(PlanMutationStore.localDate) ?? day?.date
            let oldMinute = day?.scheduledStart.map { Calendar.current.component(.hour, from: $0) * 60 + Calendar.current.component(.minute, from: $0) }
            guard let minute = change.startTime.flatMap(CoachLifeTime.minute) ?? oldMinute else { continue }
            guard let date, let start = CoachLifeTime.at(minute: minute, on: date), let duration = change.durationMinutes ?? day?.durationMinutes else { throw CoachPluginError.invalid }
            try validate(start: start, minutes: duration, excluding: day?.uuid, excludingDayIDs: changing, context: context)
            let slot = CoachTimeSlot(start: start, end: start.addingTimeInterval(Double(duration * 60)))
            guard !finalSlots.contains(where: { $0.start < slot.end && $0.end > slot.start }) else { throw CoachPluginError.unavailable("调整后的训练互相重叠，请重新安排。") }
            finalSlots.append(slot)
        }
    }
}
