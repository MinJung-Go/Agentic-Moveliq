import Foundation
import SwiftData

@MainActor
enum CoachPlanImporter {
    /// 保留确认回执，重复点击不会再次创建计划。
    static func accept(_ draft: PlanDraft, message: ChatMessage, context: ModelContext, now: Date = .now) throws -> Plan? {
        guard message.hasPendingPlan else { return nil }
        guard (1...52).contains(draft.weeks), !draft.days.isEmpty, draft.days.count <= 100,
              draft.days.allSatisfy({ (0...365).contains($0.dayOffset) &&
                  ($0.startTime == nil || CoachLifeTime.minute($0.startTime!) != nil) &&
                  ($0.durationMinutes == nil || (10...180).contains($0.durationMinutes!)) &&
                  ($0.startTime == nil || $0.durationMinutes != nil) }) else { throw CoachPluginError.invalid }
        try context.save()
        do {
            let plan = Plan(
                title: draft.title,
                goal: TrainingGoal(rawValue: draft.goal) ?? .general,
                startDate: now,
                weeks: max(1, draft.weeks)
            )
            context.insert(plan)

            let calendar = Calendar.current
            let today = calendar.startOfDay(for: now)

            for (dayIndex, dayDraft) in draft.days.enumerated() {
                let date = calendar.date(byAdding: .day, value: dayDraft.dayOffset, to: today) ?? today
                let day = PlanDay(date: date, title: dayDraft.title, order: dayIndex)
                if let minute = dayDraft.startTime.flatMap(CoachLifeTime.minute) {
                    guard let start = CoachLifeTime.at(minute: minute, on: date) else { throw CoachPluginError.invalid }
                    day.scheduledStart = start
                }
                day.durationMinutes = dayDraft.durationMinutes
                day.plan = plan
                context.insert(day)

                for (exerciseIndex, exerciseDraft) in dayDraft.exercises.enumerated() {
                    let exercise = PlanExercise(
                        name: exerciseDraft.name,
                        setsText: exerciseDraft.setsText,
                        targetWeightKg: exerciseDraft.targetWeightKg,
                        order: exerciseIndex
                    )
                    exercise.day = day
                    context.insert(exercise)
                }
            }

            // 已有计划置为非激活，保持单一进行中的计划
            do {
                let existing = try context.fetch(FetchDescriptor<Plan>())
                for other in existing where other.id != plan.id {
                    other.isActive = false
                }
            }

            message.planAcceptedAt = now
            try context.save()
            return plan
        } catch { context.rollback(); throw error }

    }
}
