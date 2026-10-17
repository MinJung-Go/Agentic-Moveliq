import Foundation
import SwiftData

@MainActor
enum CoachPlanContext {
    static func build(context: ModelContext, query: String, now: Date = .now, limit: Int = 2_000) throws -> String {
        let plans = try context.fetch(FetchDescriptor<Plan>(sortBy: [SortDescriptor(\Plan.createdAt, order: .reverse)]))
        guard let plan = plans.first(where: \.isActive) else { return "没有进行中的课程表；历史建议不代表当前计划。" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        var result = "planID=\(plan.uuid.uuidString)；revision=\(PlanMutationStore.revision(plan))\n《\(String(plan.title.prefix(80)))》已生效；完成 \(plan.completedCount)/\(plan.days.count) 天。\n"
        let term = ExerciseNameMatcher.normalize(query)
        let ordered = plan.days.sorted { lhs, rhs in
            func rank(_ day: PlanDay) -> Int {
                day.exercises.contains { !term.isEmpty && term.contains(ExerciseNameMatcher.normalize($0.name)) } ? 0 : 1
            }
            if rank(lhs) != rank(rhs) { return rank(lhs) < rank(rhs) }
            let left = abs(lhs.date.timeIntervalSince(now)), right = abs(rhs.date.timeIntervalSince(now))
            return left == right ? lhs.order < rhs.order : left < right
        }
        var included = 0
        let total = ordered.reduce(0) { $0 + max(1, $1.exercises.count) }
        for day in ordered {
            let prefix = "dayID=\(day.uuid.uuidString) \(formatter.string(from: day.date)) \(String(day.title.prefix(60))) [\(day.statusRaw)]"
                + (day.scheduledStart.map { " 开始=\(CoachLifeTime.iso($0))" } ?? " 未设具体时间")
                + (day.durationMinutes.map { " 时长=\($0)分钟" } ?? "")
            let exercises = day.exercises.sorted { $0.order < $1.order }
            let rows = exercises.isEmpty ? [prefix] : exercises.map { exercise in
                prefix + "：\(String(exercise.name.prefix(80))) \(String(exercise.setsText.prefix(60)))" +
                    (exercise.targetWeightKg.map { " \($0)kg" } ?? "")
            }
            for row in rows {
                if result.utf8.count + row.utf8.count + 100 > limit { continue }
                result += row + "\n"
                included += 1
            }
        }
        if included < total { result += "已省略 \(total - included) 项，以上为与问题相关/临近日期的部分计划，不代表全部。" }
        return result
    }
}
