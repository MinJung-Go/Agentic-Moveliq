import Foundation
import SwiftData

/// 把 ParserAgent 的解析结果写入 SwiftData。
/// 解析成功但无法归类的随笔也会落成 RawNote，不丢用户数据。
@MainActor
enum RecordImporter {

    struct Summary: Equatable {
        var workouts = 0
        var meals = 0
        var metrics = 0
        var notes = 0

        var total: Int { workouts + meals + metrics + notes }
    }

    struct Input {
        let record: ParsedRecord
        var photoData: Data? = nil
        var failureReason: String = ""
    }

    @discardableResult
    static func apply(
        _ records: [ParsedRecord],
        to context: ModelContext,
        date: Date = .now,
        source: RecordSource = .text
    ) throws -> Summary {
        try applyBatch(records.map { Input(record: $0) }, to: context, date: date, source: source)
    }

    /// Flush unrelated edits first, then commit all records and their attachments together.
    /// On failure only this batch is rolled back, so retrying cannot duplicate partial inserts.
    @discardableResult
    static func applyBatch(
        _ inputs: [Input],
        to context: ModelContext,
        date: Date = .now,
        source: RecordSource = .text,
        persist: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> Summary {
        guard !inputs.isEmpty else { return Summary() }
        try context.save()
        do {
            var summary = Summary()

            for input in inputs {
                let record = input.record
                switch record.kind {
                case .workout:
                    guard let workout = record.workout else { continue }
                    importWorkout(workout, into: context, date: date, source: source)
                    summary.workouts += 1

                case .meal:
                    guard let meal = record.meal else { continue }
                    importMeal(meal, into: context, date: date, source: source, photoData: input.photoData)
                    summary.meals += 1

                case .metric:
                    guard let metric = record.metric else { continue }
                    importMetric(metric, into: context, date: date)
                    summary.metrics += 1

                case .note:
                    let text = record.note ?? ""
                    guard !text.isEmpty else { continue }
                    let note = RawNote(text: text, date: date, failureReason: input.failureReason)
                    note.photoData = input.photoData
                    context.insert(note)
                    summary.notes += 1
                }
            }

            try persist(context)
            return summary
        } catch {
            context.rollback()
            throw error
        }
    }

    /// 解析失败时调用：原文存为待归类笔记
    static func storeRawNote(
        _ text: String,
        failureReason: String,
        to context: ModelContext,
        date: Date = .now,
        photoData: Data? = nil,
        persist: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        try context.save()
        let note = RawNote(text: text.isEmpty && photoData != nil ? "待整理的照片" : text, date: date, failureReason: failureReason)
        note.photoData = photoData
        context.insert(note)
        do { try persist(context) }
        catch { context.rollback(); throw error }
    }

    // MARK: - 内部

    private static func importWorkout(
        _ workout: ParsedWorkout,
        into context: ModelContext,
        date: Date,
        source: RecordSource
    ) {
        let session = WorkoutSession(
            date: date,
            title: workout.title?.isEmpty == false ? workout.title! : defaultTitle(for: workout),
            note: workout.note ?? "",
            source: source
        )
        context.insert(session)

        for (index, exercise) in workout.exercises.enumerated() {
            let set = ExerciseSet(
                exerciseName: exercise.name,
                weightKg: exercise.weightKg ?? 0,
                reps: exercise.reps ?? 0,
                setCount: max(1, exercise.sets ?? 1),
                rpe: workout.rpe,
                order: index
            )
            set.session = session
            context.insert(set)
        }
    }

    private static func importMeal(
        _ meal: ParsedMeal,
        into context: ModelContext,
        date: Date,
        source: RecordSource,
        photoData: Data?
    ) {
        let entry = MealEntry(
            date: date,
            mealType: meal.mealType.flatMap(MealType.init(rawValue:)),
            note: meal.note ?? "",
            source: photoData == nil ? source : .photo
        )
        entry.photoData = photoData
        entry.hasPhoto = photoData != nil
        context.insert(entry)

        for item in meal.items {
            let food = FoodItem(
                name: item.name,
                amountText: item.amountText ?? "",
                calories: item.calories ?? 0,
                proteinG: item.proteinG ?? 0,
                carbsG: item.carbsG ?? 0,
                fatG: item.fatG ?? 0,
                isEstimated: true
            )
            food.meal = entry
            context.insert(food)
        }
    }

    private static func importMetric(_ metric: ParsedMetric, into context: ModelContext, date: Date) {
        context.insert(BodyMetric(
            date: date,
            kind: MetricKind(rawValue: metric.kind) ?? .weight,
            value: metric.value
        ))
    }

    /// 未给标题时，用动作名生成一个
    private static func defaultTitle(for workout: ParsedWorkout) -> String {
        let names = workout.exercises.map(\.name).filter { !$0.isEmpty }
        switch names.count {
        case 0: return "训练"
        case 1: return names[0]
        default: return "\(names[0])、\(names[1]) 等 \(names.count) 个动作"
        }
    }
}
