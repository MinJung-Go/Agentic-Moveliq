import Foundation

// MARK: - ParserAgent 输出

/// ParserAgent 的整体输出
struct ParserOutput: Decodable, Equatable {
    var records: [ParsedRecord]
}

/// 一条被解析出的记录
struct ParsedRecord: Decodable, Equatable {

    enum Kind: String, Decodable {
        case workout
        case meal
        case metric
        case note
    }

    var kind: Kind
    var workout: ParsedWorkout?
    var meal: ParsedMeal?
    var metric: ParsedMetric?
    var note: String?

    enum CodingKeys: String, CodingKey {
        case type, kind, workout, meal, metric, note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // type 与 kind 两种写法都接受
        let rawKind = Lenient.string(container, .type) ?? Lenient.string(container, .kind) ?? "note"
        self.kind = Kind(rawValue: rawKind.lowercased()) ?? .note

        self.workout = try? container.decodeIfPresent(ParsedWorkout.self, forKey: .workout)
        self.meal = try? container.decodeIfPresent(ParsedMeal.self, forKey: .meal)
        self.metric = try? container.decodeIfPresent(ParsedMetric.self, forKey: .metric)
        self.note = Lenient.string(container, .note)

        // 类型与载荷不一致时以载荷为准
        if workout != nil && kind != .workout { self.kind = .workout }
        if meal != nil && kind != .meal { self.kind = .meal }
        if metric != nil && kind != .metric { self.kind = .metric }
    }

    init(kind: Kind, workout: ParsedWorkout? = nil, meal: ParsedMeal? = nil, metric: ParsedMetric? = nil, note: String? = nil) {
        self.kind = kind
        self.workout = workout
        self.meal = meal
        self.metric = metric
        self.note = note
    }
}

struct ParsedWorkout: Decodable, Equatable {
    var title: String?
    var exercises: [ParsedExercise]
    var rpe: Double?
    var note: String?

    enum CodingKeys: String, CodingKey {
        case title, exercises, rpe, note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = Lenient.string(container, .title)
        self.rpe = Lenient.double(container, .rpe)
        self.note = Lenient.string(container, .note)
        self.exercises = (try? container.decodeIfPresent([ParsedExercise].self, forKey: .exercises)) ?? []
    }

    init(title: String? = nil, exercises: [ParsedExercise], rpe: Double? = nil, note: String? = nil) {
        self.title = title
        self.exercises = exercises
        self.rpe = rpe
        self.note = note
    }
}

struct ParsedExercise: Decodable, Equatable {
    var name: String
    var weightKg: Double?
    var reps: Int?
    var sets: Int?

    enum CodingKeys: String, CodingKey {
        case name, weightKg, weight, reps, sets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = Lenient.string(container, .name) ?? "未知动作"
        self.weightKg = Lenient.double(container, .weightKg) ?? Lenient.double(container, .weight)
        self.reps = Lenient.int(container, .reps)
        self.sets = Lenient.int(container, .sets)
    }

    init(name: String, weightKg: Double? = nil, reps: Int? = nil, sets: Int? = nil) {
        self.name = name
        self.weightKg = weightKg
        self.reps = reps
        self.sets = sets
    }
}

struct ParsedMeal: Decodable, Equatable {
    var mealType: String?
    var items: [ParsedFood]
    var note: String?

    enum CodingKeys: String, CodingKey {
        case mealType, items, note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.mealType = Lenient.string(container, .mealType)
        self.note = Lenient.string(container, .note)
        self.items = (try? container.decodeIfPresent([ParsedFood].self, forKey: .items)) ?? []
    }

    init(mealType: String? = nil, items: [ParsedFood], note: String? = nil) {
        self.mealType = mealType
        self.items = items
        self.note = note
    }
}

struct ParsedFood: Decodable, Equatable {
    var name: String
    var amountText: String?
    var calories: Double?
    var proteinG: Double?
    var carbsG: Double?
    var fatG: Double?

    enum CodingKeys: String, CodingKey {
        case name, amountText, calories, proteinG, carbsG, fatG
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = Lenient.string(container, .name) ?? "未知食物"
        self.amountText = Lenient.string(container, .amountText)
        self.calories = Lenient.double(container, .calories)
        self.proteinG = Lenient.double(container, .proteinG)
        self.carbsG = Lenient.double(container, .carbsG)
        self.fatG = Lenient.double(container, .fatG)
    }

    init(
        name: String,
        amountText: String? = nil,
        calories: Double? = nil,
        proteinG: Double? = nil,
        carbsG: Double? = nil,
        fatG: Double? = nil
    ) {
        self.name = name
        self.amountText = amountText
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
    }
}

struct ParsedMetric: Decodable, Equatable {
    var kind: String
    var value: Double

    enum CodingKeys: String, CodingKey {
        case kind, value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = Lenient.string(container, .kind) ?? "weight"
        self.value = Lenient.double(container, .value) ?? 0
    }

    init(kind: String, value: Double) {
        self.kind = kind
        self.value = value
    }
}

// MARK: - AnalystAgent 输出

/// 发给 LLM 的分析摘要（**只有这个会离开设备**，原始记录不出本机）
struct AnalysisDigest: Codable, Equatable {
    var periodStart: Date
    var periodEnd: Date
    var workoutCount: Int = 0
    var totalVolumeKg: Double = 0
    var trends: [ExerciseTrend] = []
    var sleepAvgHours: Double = 0
    var sleepMinHours: Double = 0
    var hrvAvg: Double = 0
    var restingHeartRateAvg: Double = 0
    var stepsAvgPerDay: Int = 0
    var healthActivity: HealthActivityDigest?

    var hasData: Bool {
        workoutCount > 0 || nutrition.daysLogged > 0 || sleepAvgHours > 0 ||
        hrvAvg > 0 || restingHeartRateAvg > 0 || stepsAvgPerDay > 0 ||
        healthActivity?.hasData == true
    }
    var nutrition: NutritionDigest = NutritionDigest()

    /// 压缩成人类可读的文本，直接进 prompt（省 token 且比 JSON 更好理解）
    func summaryText() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        var lines: [String] = []
        lines.append("统计区间：\(formatter.string(from: periodStart)) 至 \(formatter.string(from: periodEnd))")

        if workoutCount > 0 {
            lines.append("训练：共 \(workoutCount) 次，总容量 \(Int(totalVolumeKg.rounded())) kg")
            for trend in trends.prefix(8) {
                var line = "  - \(trend.name)：\(trend.sessions) 次；最佳估算 1RM \(Int(trend.bestE1RM.rounded()))kg；最近 \(Int(trend.recentE1RM.rounded()))kg"
                if trend.stalledWeeks >= 2 {
                    line += "；已停滞 \(trend.stalledWeeks) 周"
                }
                lines.append(line)
            }
        } else {
            lines.append("Moveliq 内训练：本区间没有训练记录（不含 Apple 健康运动）")
        }

        if let healthActivity, healthActivity.hasData {
            lines.append(healthActivity.summaryText)
        }

        if sleepAvgHours > 0 {
            lines.append("睡眠：日均 \(String(format: "%.1f", sleepAvgHours)) 小时，最低 \(String(format: "%.1f", sleepMinHours)) 小时")
        }
        if hrvAvg > 0 {
            lines.append("HRV：日均 \(Int(hrvAvg.rounded())) ms")
        }
        if restingHeartRateAvg > 0 {
            lines.append("静息心率：日均 \(Int(restingHeartRateAvg.rounded())) bpm")
        }
        if stepsAvgPerDay > 0 {
            lines.append("步数：日均 \(stepsAvgPerDay) 步")
        }

        if nutrition.daysLogged > 0 {
            lines.append("饮食（\(nutrition.daysLogged) 天有记录）：日均 \(Int(nutrition.avgCalories.rounded())) kcal，蛋白质 \(Int(nutrition.avgProteinG.rounded()))g，碳水 \(Int(nutrition.avgCarbsG.rounded()))g，脂肪 \(Int(nutrition.avgFatG.rounded()))g")
        } else {
            lines.append("饮食：本区间没有记录")
        }

        return lines.joined(separator: "\n")
    }
}

/// 单个动作的趋势
struct ExerciseTrend: Codable, Equatable {
    var name: String
    var sessions: Int = 0
    var bestE1RM: Double = 0
    var recentE1RM: Double = 0
    /// 重量停滞的周数（最近提升距今）
    var stalledWeeks: Int = 0
}

/// 饮食聚合
struct NutritionDigest: Codable, Equatable {
    var daysLogged: Int = 0
    var avgCalories: Double = 0
    var avgProteinG: Double = 0
    var avgCarbsG: Double = 0
    var avgFatG: Double = 0
}

/// AnalystAgent 生成的报告草稿
struct AnalysisReportDraft: Decodable, Equatable {
    var headline: String
    var body: String
    var tags: [String]
    var citedData: String

    enum CodingKeys: String, CodingKey {
        case headline, body, tags, citedData, cited_data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.headline = Lenient.string(container, .headline) ?? "本期分析"
        self.body = Lenient.string(container, .body) ?? ""
        self.tags = Lenient.strings(container, .tags) ?? []
        self.citedData = Lenient.string(container, .citedData)
            ?? Lenient.string(container, .cited_data)
            ?? ""
    }

    init(headline: String, body: String, tags: [String], citedData: String) {
        self.headline = headline
        self.body = body
        self.tags = tags
        self.citedData = citedData
    }
}

// MARK: - CoachAgent 输出

/// 对话中的一轮（与 SwiftData 解耦）
struct CoachTurn: Equatable {
    var role: ChatRole
    var content: String
    var id: UUID? = nil
    var date: Date? = nil
}

/// 教练上下文（用户画像与近期情况，注入 system prompt）
struct CoachContext: Equatable {
    var persona = MiloPersona()
    var goal: String = ""
    var availableEquipment: String = ""
    var daysPerWeek: Int = 0
    /// 一行式近期摘要（保留兼容）
    var recentSummary: String = ""
    /// 结构化的个人概况：训练 / 恢复 / 饮食 / 身体 / 课程表
    /// 由 CoachContextBuilder 从本地聚合生成，只有聚合结果会发给模型
    var profileText: String = ""
    /// 当前数据库状态，不由历史摘要覆盖。
    var planState: String = ""
    var lifeContext: String = ""
}

/// 计划草稿（function call 返回，确认后入库）
struct PlanDraft: Decodable, Equatable {
    var title: String
    var goal: String
    var weeks: Int
    var days: [PlanDayDraft]

    enum CodingKeys: String, CodingKey {
        case title, goal, weeks, days
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = Lenient.string(container, .title) ?? "课程计划"
        self.goal = Lenient.string(container, .goal) ?? "general"
        self.weeks = Lenient.int(container, .weeks) ?? 4
        self.days = (try? container.decodeIfPresent([PlanDayDraft].self, forKey: .days)) ?? []
    }

    init(title: String, goal: String, weeks: Int, days: [PlanDayDraft]) {
        self.title = title
        self.goal = goal
        self.weeks = weeks
        self.days = days
    }
}

struct PlanDayDraft: Decodable, Equatable {
    /// 相对今天的天数偏移（0 = 今天）
    var dayOffset: Int
    var title: String
    var exercises: [PlanExerciseDraft]
    var startTime: String? = nil
    var durationMinutes: Int? = nil

    enum CodingKeys: String, CodingKey {
        case dayOffset, day_offset, title, exercises, startTime, durationMinutes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.dayOffset = Lenient.int(container, .dayOffset) ?? Lenient.int(container, .day_offset) ?? 0
        self.title = Lenient.string(container, .title) ?? "训练日"
        self.exercises = (try? container.decodeIfPresent([PlanExerciseDraft].self, forKey: .exercises)) ?? []
        self.startTime = try container.decodeIfPresent(String.self, forKey: .startTime)
        self.durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes)
    }

    init(dayOffset: Int, title: String, exercises: [PlanExerciseDraft]) {
        self.dayOffset = dayOffset
        self.title = title
        self.exercises = exercises
    }
}

struct PlanExerciseDraft: Decodable, Equatable {
    var name: String
    var setsText: String
    var targetWeightKg: Double?

    enum CodingKeys: String, CodingKey {
        case name, setsText, sets, targetWeightKg
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = Lenient.string(container, .name) ?? "未知动作"
        self.setsText = Lenient.string(container, .setsText) ?? Lenient.string(container, .sets) ?? ""
        self.targetWeightKg = Lenient.double(container, .targetWeightKg)
    }

    init(name: String, setsText: String = "", targetWeightKg: Double? = nil) {
        self.name = name
        self.setsText = setsText
        self.targetWeightKg = targetWeightKg
    }
}

/// 计划调整建议（function call 返回）
struct PlanAdjustmentDraft: Decodable, Equatable {
    var planID: String? = nil
    var revision: String? = nil
    var summary: String
    var changes: [PlanAdjustmentChange]

    enum CodingKeys: String, CodingKey {
        case summary, changes, planID, revision
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.planID = try container.decodeIfPresent(String.self, forKey: .planID)
        self.revision = try container.decodeIfPresent(String.self, forKey: .revision)
        self.summary = Lenient.string(container, .summary) ?? "调整建议"
        self.changes = try container.decode([PlanAdjustmentChange].self, forKey: .changes)
    }

    init(summary: String, changes: [PlanAdjustmentChange], planID: String? = nil, revision: String? = nil) {
        self.planID = planID
        self.revision = revision
        self.summary = summary
        self.changes = changes
    }
}

struct PlanAdjustmentChange: Decodable, Equatable {
    var dayID: String? = nil
    var title: String? = nil
    var date: String? = nil
    var exercises: [PlanExerciseDraft]? = nil
    var startTime: String? = nil
    var durationMinutes: Int? = nil
    var weightReductionPercent: Int? = nil
    /// 相对今天的天数偏移
    var dayOffset: Int
    var action: String
    var detail: String

    enum CodingKeys: String, CodingKey {
        case dayOffset, day_offset, action, detail, dayID, title, date, exercises, startTime, durationMinutes, weightReductionPercent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.dayID = try container.decodeIfPresent(String.self, forKey: .dayID)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.date = try container.decodeIfPresent(String.self, forKey: .date)
        self.exercises = try container.decodeIfPresent([PlanExerciseDraft].self, forKey: .exercises)
        self.startTime = try container.decodeIfPresent(String.self, forKey: .startTime)
        self.durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes)
        self.weightReductionPercent = try container.decodeIfPresent(Int.self, forKey: .weightReductionPercent)
        self.dayOffset = Lenient.int(container, .dayOffset) ?? Lenient.int(container, .day_offset) ?? 0
        self.action = Lenient.string(container, .action) ?? "adjust"
        self.detail = Lenient.string(container, .detail) ?? ""
    }

    init(dayOffset: Int, action: String, detail: String) {
        self.dayOffset = dayOffset
        self.action = action
        self.detail = detail
    }
}

/// CoachAgent 的一次回复
struct CoachReply: Equatable {
    var text: String?
    /// 思考内容（有就带出，用于落库回看）
    var reasoning: String? = nil
    var planDraft: PlanDraft?
    var adjustmentDraft: PlanAdjustmentDraft?
    /// function call 的原始参数 JSON（用于持久化待确认的计划）
    var planArgumentsJSON: String?
    var adjustmentArgumentsJSON: String?

    var isEmpty: Bool {
        (text?.isEmpty ?? true) && planDraft == nil && adjustmentDraft == nil
    }
}
