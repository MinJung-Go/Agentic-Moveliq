import Foundation
import CryptoKit
import SwiftData

@MainActor
enum PlanMutationStore {
    enum MutationError: LocalizedError {
        case invalid, missing, stale
        var errorDescription: String? {
            switch self {
            case .invalid: return "操作参数不完整或不受支持，请让教练重新查询课程表并生成建议。"
            case .missing: return "目标课程表或训练日已不存在，没有执行操作。"
            case .stale: return "课程表已经变化，请让教练重新查询后再调整。"
            }
        }
    }

    /// Includes editable content and completion state; never trusts a model-provided title as identity.
    static func revision(_ plan: Plan) -> String {
        var hash = SHA256()
        func add(_ fields: [String]) {
            for field in fields { hash.update(data: Data("\(field.utf8.count):\(field)".utf8)) }
        }
        add([plan.uuid.uuidString, plan.title, plan.goalRaw, String(plan.startDate.timeIntervalSince1970),
             String(plan.weeks), plan.note, String(plan.isActive)])
        for day in plan.days.sorted(by: { $0.uuid.uuidString < $1.uuid.uuidString }) {
            add([day.uuid.uuidString, day.title, String(day.date.timeIntervalSince1970), day.statusRaw, String(day.order), day.note,
                 day.scheduledStart.map { String($0.timeIntervalSince1970) } ?? "nil", day.durationMinutes.map(String.init) ?? "nil"])
            for exercise in day.exercises.sorted(by: { $0.uuid.uuidString < $1.uuid.uuidString }) {
                add([exercise.uuid.uuidString, exercise.name, exercise.setsText,
                     exercise.targetWeightKg.map { String($0) } ?? "nil", String(exercise.order)])
            }
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func plan(id: UUID, context: ModelContext) throws -> Plan {
        var descriptor = FetchDescriptor<Plan>(predicate: #Predicate { $0.uuid == id })
        descriptor.fetchLimit = 2
        let matches = try context.fetch(descriptor)
        guard matches.count == 1, let plan = matches.first else { throw MutationError.missing }
        return plan
    }

    /// Called by UI confirmation or after trusted local automation policy validation.
    @discardableResult
    static func apply(message: ChatMessage, context: ModelContext, now: Date = .now, audit: CoachAutomationRecord? = nil) throws -> String? {
        guard message.hasPendingAdjustment else { return nil }
        guard let json = message.pendingAdjustmentJSON, json.utf8.count <= 32_768,
              let draft = try? JSONDecoder().decode(PlanAdjustmentDraft.self, from: Data(json.utf8)),
              let rawID = draft.planID, let id = UUID(uuidString: rawID),
              let expected = draft.revision else { throw MutationError.invalid }
        let plan = try plan(id: id, context: context)
        guard revision(plan) == expected else { throw MutationError.stale }
        let prepared = try validate(draft.changes, plan: plan)
        let canUndo = prepared.allSatisfy { $0.change.action == "reschedule" && $0.change.title == nil && $0.change.exercises == nil && $0.change.startTime == nil && $0.change.durationMinutes == nil && $0.day?.scheduledStart == nil }
        let previousDates = canUndo ? prepared.compactMap { item in
            item.day.map { RescheduleUndo.Day(id: $0.uuid, date: $0.date, note: $0.note) }
        } : []
        let deletesPlan = draft.changes.contains { $0.action == "delete_plan" }
        let receipt = deletesPlan ? "已删除课程表《\(plan.title)》，训练记录已保留。" : "已更新课程表《\(plan.title)》：\(prepared.count) 项调整。"
        // Flush unrelated edits before beginning this all-or-nothing mutation.
        try context.save()
        do {
            for item in prepared {
                let change = item.change
                switch change.action {
                case "delete_plan": context.delete(plan)
                case "rename_plan": plan.title = change.title!.trimmingCharacters(in: .whitespacesAndNewlines)
                case "delete_day":
                    let day = item.day!
                    plan.days.removeAll { $0.uuid == day.uuid }
                    context.delete(day)
                case "add_day":
                    let day = PlanDay(date: item.date!, title: change.title!, order: (plan.days.map(\.order).max() ?? -1) + 1)
                    day.durationMinutes = change.durationMinutes
                    if let minute = change.startTime.flatMap(CoachLifeTime.minute) { day.scheduledStart = CoachLifeTime.at(minute: minute, on: day.date) }
                    day.plan = plan
                    context.insert(day)
                    setExercises(change.exercises!, day: day, context: context)
                    day.note = change.detail
                default:
                    let day = item.day!
                    if let title = change.title { day.title = title }
                    if let date = item.date { day.date = date }
                    if let minute = change.startTime.flatMap(CoachLifeTime.minute) {
                        day.scheduledStart = CoachLifeTime.at(minute: minute, on: day.date)
                    } else if item.date != nil, let start = day.scheduledStart {
                        let minute = Calendar.current.component(.hour, from: start) * 60 + Calendar.current.component(.minute, from: start)
                        day.scheduledStart = CoachLifeTime.at(minute: minute, on: day.date)
                    }
                    if let duration = change.durationMinutes { day.durationMinutes = duration }
                    if let exercises = change.exercises { setExercises(exercises, day: day, context: context) }
                    if change.action == "skip" { day.status = .skipped }
                    if change.action == "deload" {
                        for exercise in day.exercises {
                            if let weight = exercise.targetWeightKg, weight.isFinite, weight > 0 {
                                exercise.targetWeightKg = (weight * 0.85 * 2).rounded() / 2
                            }
                        }
                    }
                    day.note = change.detail
                }
            }
            if !previousDates.isEmpty {
                let undo = RescheduleUndo(planID: plan.uuid, revision: revision(plan), days: previousDates)
                message.adjustmentUndoJSON = String(decoding: try JSONEncoder().encode(undo), as: UTF8.self)
            }
            message.adjustmentDecisionRaw = "applied"
            message.adjustmentAppliedAt = now
            message.content += (message.content.isEmpty ? "" : "\n\n") + receipt
            if let audit {
                audit.afterRevision = revision(plan)
                context.insert(audit)
            }
            try context.save()
            return receipt
        } catch { context.rollback(); throw error }
    }

    private struct RescheduleUndo: Codable {
        struct Day: Codable { let id: UUID; let date: Date; let note: String }
        let planID: UUID
        let revision: String
        let days: [Day]
    }

    /// Undo only a pure date move, and only while the plan still matches the saved receipt.
    @discardableResult
    static func undoReschedule(message: ChatMessage, context: ModelContext) throws -> Bool {
        guard message.adjustmentDecisionRaw == "applied", let json = message.adjustmentUndoJSON else { return false }
        guard let undo = try? JSONDecoder().decode(RescheduleUndo.self, from: Data(json.utf8)),
              !undo.days.isEmpty, undo.days.count <= 14 else { throw MutationError.invalid }
        let plan = try plan(id: undo.planID, context: context)
        guard revision(plan) == undo.revision else { throw MutationError.stale }
        let pairs = try undo.days.map { old -> (PlanDay, RescheduleUndo.Day) in
            guard let day = plan.days.first(where: { $0.uuid == old.id }) else { throw MutationError.missing }
            return (day, old)
        }
        try context.save()
        do {
            for (day, old) in pairs { day.date = old.date; day.note = old.note }
            message.adjustmentDecisionRaw = "undone"
            message.adjustmentUndoJSON = nil
            message.content += "\n\n已撤销本次改期，恢复原训练日期。"
            try context.save()
            return true
        } catch { context.rollback(); throw error }
    }

    /// Manual deletion uses the same persistence boundary; workout logs have no cascade relationship to Plan.
    static func delete(id: UUID, context: ModelContext) throws {
        let target = try plan(id: id, context: context)
        try context.save()
        do { context.delete(target); try context.save() }
        catch { context.rollback(); throw error }
    }

    private struct Prepared {
        var change: PlanAdjustmentChange
        var day: PlanDay?
        var date: Date?
    }

    private static func validate(_ changes: [PlanAdjustmentChange], plan: Plan) throws -> [Prepared] {
        guard !changes.isEmpty, changes.count <= 14 else { throw MutationError.invalid }
        var seen = Set<String>()
        return try changes.map { change in
            guard change.detail.utf8.count <= 1500 else { throw MutationError.invalid }
            if let time = change.startTime, CoachLifeTime.minute(time) == nil { throw MutationError.invalid }
            if let duration = change.durationMinutes, !(10...180).contains(duration) { throw MutationError.invalid }
            if let title = change.title {
                guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 100 else { throw MutationError.invalid }
            }
            if let exercises = change.exercises {
                guard !exercises.isEmpty, exercises.count <= 20,
                      exercises.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 80 && $0.setsText.count <= 100 &&
                          ($0.targetWeightKg == nil || ($0.targetWeightKg!.isFinite && (0...2000).contains($0.targetWeightKg!))) }) else { throw MutationError.invalid }
            }
            let newDate: Date?
            if let text = change.date {
                guard let parsed = localDate(text) else { throw MutationError.invalid }
                newDate = parsed
            } else { newDate = nil }
            if ["delete_plan", "delete_day", "skip", "deload"].contains(change.action) {
                guard change.title == nil, change.date == nil, change.exercises == nil, change.startTime == nil, change.durationMinutes == nil else { throw MutationError.invalid }
            }
            if change.action == "replace" {
                guard change.title == nil, change.date == nil else { throw MutationError.invalid }
            }
            if change.action == "reschedule" {
                guard change.title == nil, change.exercises == nil else { throw MutationError.invalid }
            }
            if ["add_day", "rename_plan", "delete_plan"].contains(change.action) {
                guard change.dayID == nil else { throw MutationError.invalid }
            }
            switch change.action {
            case "delete_plan":
                guard changes.count == 1 else { throw MutationError.invalid }
                return Prepared(change: change)
            case "rename_plan":
                guard change.title != nil, change.date == nil, change.exercises == nil, change.startTime == nil, change.durationMinutes == nil, seen.insert("rename_plan").inserted else { throw MutationError.invalid }
                return Prepared(change: change)
            case "add_day":
                guard change.title != nil, newDate != nil, change.exercises != nil else { throw MutationError.invalid }
                if let minute = change.startTime.flatMap(CoachLifeTime.minute) {
                    guard change.durationMinutes != nil, CoachLifeTime.at(minute: minute, on: newDate!) != nil else { throw MutationError.invalid }
                }
                return Prepared(change: change, date: newDate)
            case "update", "replace", "reschedule", "deload", "skip", "delete_day":
                guard let raw = change.dayID, let id = UUID(uuidString: raw), seen.insert(id.uuidString).inserted,
                      let day = plan.days.first(where: { $0.uuid == id }) else { throw MutationError.missing }
                guard day.status != .done else { throw MutationError.stale }
                if change.action == "deload" {
                    guard day.exercises.allSatisfy({ $0.targetWeightKg == nil || ($0.targetWeightKg!.isFinite && (0...2000).contains($0.targetWeightKg!)) }) else { throw MutationError.invalid }
                }
                if change.action == "replace" && change.exercises == nil { throw MutationError.invalid }
                if change.action == "reschedule" && newDate == nil && change.startTime == nil { throw MutationError.invalid }
                if change.action == "update" && change.title == nil && change.exercises == nil && newDate == nil && change.startTime == nil && change.durationMinutes == nil { throw MutationError.invalid }
                if change.startTime != nil && change.durationMinutes == nil && day.durationMinutes == nil { throw MutationError.invalid }
                let minute = change.startTime.flatMap(CoachLifeTime.minute) ?? day.scheduledStart.map {
                    Calendar.current.component(.hour, from: $0) * 60 + Calendar.current.component(.minute, from: $0)
                }
                if let minute, CoachLifeTime.at(minute: minute, on: newDate ?? day.date) == nil { throw MutationError.invalid }
                return Prepared(change: change, day: day, date: newDate)
            default: throw MutationError.invalid
            }
        }
    }

    private static func setExercises(_ values: [PlanExerciseDraft], day: PlanDay, context: ModelContext) {
        let previous = Array(day.exercises)
        day.exercises.removeAll()
        for existing in previous { context.delete(existing) }
        for (index, value) in values.enumerated() {
            let exercise = PlanExercise(name: value.name, setsText: value.setsText, targetWeightKg: value.targetWeightKg, order: index)
            exercise.day = day
            context.insert(exercise)
        }
    }

    static func localDate(_ text: String) -> Date? {
        let bytes = Array(text.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ $0.offset == 4 || $0.offset == 7 || (48...57).contains($0.element) }) else { return nil }
        let fields = text.split(separator: "-").compactMap { Int($0) }
        guard fields.count == 3, (2000...2100).contains(fields[0]) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = DateComponents(year: fields[0], month: fields[1], day: fields[2])
        guard components.isValidDate(in: calendar), let date = calendar.date(from: components) else { return nil }
        let actual = calendar.dateComponents([.year, .month, .day], from: date)
        guard actual.year == fields[0], actual.month == fields[1], actual.day == fields[2] else { return nil }
        return date
    }
}
