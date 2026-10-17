import Foundation

/// 解析结果的可编辑草稿。
/// 设计原则：AI 不直接写库——所有字段都要经过确认卡片，用户可逐项修改。
struct LogDraft: Identifiable {

    enum Kind: String, CaseIterable {
        case workout, meal, metric, note

        var headerTitle: String {
            switch self {
            case .workout: return "力量训练"
            case .meal: return "饮食"
            case .metric: return "身体指标"
            case .note: return "随笔"
            }
        }

        var recordKind: RecordKind {
            switch self {
            case .workout: return .workout
            case .meal: return .meal
            case .metric: return .body
            case .note: return .note
            }
        }
    }

    let id = UUID()
    var kind: Kind
    var workout: WorkoutDraft = WorkoutDraft()
    var meal: MealDraft = MealDraft()
    var metric: MetricDraft = MetricDraft()
    var note: NoteDraft = NoteDraft()

    init(kind: Kind) {
        self.kind = kind
    }

    /// 从解析结果构造草稿；无法构造时返回 nil
    static func from(_ record: ParsedRecord) -> LogDraft? {
        switch record.kind {
        case .workout:
            guard let workout = record.workout else { return nil }
            var draft = LogDraft(kind: .workout)
            draft.workout = WorkoutDraft(from: workout)
            return draft

        case .meal:
            guard let meal = record.meal else { return nil }
            var draft = LogDraft(kind: .meal)
            draft.meal = MealDraft(from: meal)
            return draft

        case .metric:
            guard let metric = record.metric else { return nil }
            var draft = LogDraft(kind: .metric)
            draft.metric = MetricDraft(from: metric)
            return draft

        case .note:
            let text = record.note ?? ""
            guard !text.isEmpty else { return nil }
            var draft = LogDraft(kind: .note)
            draft.note = NoteDraft(text: text)
            return draft
        }
    }

    /// 转回解析结构，交给 RecordImporter 入库
    func toParsedRecord() -> ParsedRecord {
        switch kind {
        case .workout:
            return ParsedRecord(kind: .workout, workout: workout.toParsed())
        case .meal:
            return ParsedRecord(kind: .meal, meal: meal.toParsed())
        case .metric:
            return ParsedRecord(kind: .metric, metric: metric.toParsed())
        case .note:
            return ParsedRecord(kind: .note, note: note.text)
        }
    }

    var isEmpty: Bool {
        switch kind {
        case .workout:
            return workout.exercises.allSatisfy { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        case .meal:
            return meal.items.allSatisfy { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        case .metric:
            return metric.valueText.trimmingCharacters(in: .whitespaces).isEmpty
        case .note:
            return note.text.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }
}

// MARK: - 训练

struct WorkoutDraft {
    var title: String = ""
    var exercises: [ExerciseDraft] = [ExerciseDraft()]
    var rpeText: String = ""
    var note: String = ""

    init() {}

    init(from parsed: ParsedWorkout) {
        self.title = parsed.title ?? ""
        self.rpeText = parsed.rpe.map { Format.number($0) } ?? ""
        self.note = parsed.note ?? ""
        self.exercises = parsed.exercises.isEmpty
            ? [ExerciseDraft()]
            : parsed.exercises.map(ExerciseDraft.init(from:))
    }

    func toParsed() -> ParsedWorkout {
        ParsedWorkout(
            title: title.trimmingCharacters(in: .whitespaces).isEmpty ? nil : title,
            exercises: exercises.map { $0.toParsed() }.filter { !$0.name.isEmpty },
            rpe: ParsedInput.double(rpeText),
            note: note
        )
    }
}

struct ExerciseDraft: Identifiable {
    let id = UUID()
    var name: String = ""
    var weightText: String = ""
    var repsText: String = ""
    var setsText: String = ""

    init() {}

    init(from parsed: ParsedExercise) {
        self.name = parsed.name
        self.weightText = parsed.weightKg.map { ParsedInput.text($0) } ?? ""
        self.repsText = parsed.reps.map(String.init) ?? ""
        self.setsText = parsed.sets.map(String.init) ?? ""
    }

    func toParsed() -> ParsedExercise {
        ParsedExercise(
            name: name.trimmingCharacters(in: .whitespaces),
            weightKg: ParsedInput.double(weightText),
            reps: ParsedInput.int(repsText),
            sets: ParsedInput.int(setsText)
        )
    }
}

// MARK: - 饮食

struct MealDraft {
    var mealType: MealType = .lunch
    var items: [FoodDraft] = [FoodDraft()]
    var note: String = ""
    /// 照片识别时附带的原图（保存后写入记录）
    var photoData: Data?

    init() {
        self.mealType = MealType.inferred()
    }

    init(from parsed: ParsedMeal) {
        self.mealType = parsed.mealType.flatMap(MealType.init(rawValue:)) ?? MealType.inferred()
        self.note = parsed.note ?? ""
        self.items = parsed.items.isEmpty ? [FoodDraft()] : parsed.items.map(FoodDraft.init(from:))
    }

    var totalCalories: Double {
        items.compactMap { ParsedInput.double($0.caloriesText) }.reduce(0, +)
    }

    var totalProtein: Double {
        items.compactMap { ParsedInput.double($0.proteinText) }.reduce(0, +)
    }

    func toParsed() -> ParsedMeal {
        ParsedMeal(
            mealType: mealType.rawValue,
            items: items.map { $0.toParsed() }.filter { !$0.name.isEmpty },
            note: note
        )
    }
}

struct FoodDraft: Identifiable {
    let id = UUID()
    var name: String = ""
    var amountText: String = ""
    var caloriesText: String = ""
    var proteinText: String = ""
    var carbsText: String = ""
    var fatText: String = ""

    init() {}

    init(from parsed: ParsedFood) {
        self.name = parsed.name
        self.amountText = parsed.amountText ?? ""
        self.caloriesText = parsed.calories.map { Format.number($0) } ?? ""
        self.proteinText = parsed.proteinG.map { Format.number($0) } ?? ""
        self.carbsText = parsed.carbsG.map { Format.number($0) } ?? ""
        self.fatText = parsed.fatG.map { Format.number($0) } ?? ""
    }

    func toParsed() -> ParsedFood {
        ParsedFood(
            name: name.trimmingCharacters(in: .whitespaces),
            amountText: amountText.isEmpty ? nil : amountText,
            calories: ParsedInput.double(caloriesText),
            proteinG: ParsedInput.double(proteinText),
            carbsG: ParsedInput.double(carbsText),
            fatG: ParsedInput.double(fatText)
        )
    }
}

// MARK: - 指标与随笔

struct MetricDraft {
    var kind: MetricKind = .weight
    var valueText: String = ""
    var note: String = ""

    init() {}

    init(from parsed: ParsedMetric) {
        self.kind = MetricKind(rawValue: parsed.kind) ?? .weight
        self.valueText = ParsedInput.text(parsed.value)
    }

    func toParsed() -> ParsedMetric {
        ParsedMetric(kind: kind.rawValue, value: ParsedInput.double(valueText) ?? 0)
    }
}

struct NoteDraft {
    var text: String = ""
    /// A failed fallback save remains an editable draft, including its original attachment.
    var photoData: Data? = nil
    var failureReason: String = ""
}

// MARK: - 文本 ↔ 数值

enum ParsedInput {

    static func double(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "，", with: "")
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }

    static func int(_ text: String) -> Int? {
        guard let value = double(text) else { return nil }
        return Int(value.rounded())
    }

    /// 整数不带小数点，其余保留一位
    static func text(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
