import Foundation
import SwiftData

// MARK: - 枚举（以 Raw String 存储，对外暴露计算属性，避免 SwiftData 枚举兼容问题）

/// 记录来源
enum RecordSource: String, Codable, CaseIterable {
    case text       // 自然语言解析
    case photo      // 照片估算（P2）
    case manual     // 手动表单
    case healthKit  // HealthKit 同步

    var displayName: String {
        switch self {
        case .text: return "打字"
        case .photo: return "照片"
        case .manual: return "手动"
        case .healthKit: return "Watch"
        }
    }
}

/// 原始笔记的归类状态
enum RawNoteStatus: String, Codable {
    case pending      // 待归类
    case categorized  // 已归类
    case discarded    // 已丢弃

    var displayName: String {
        switch self {
        case .pending: return "待归类"
        case .categorized: return "已归类"
        case .discarded: return "已丢弃"
        }
    }
}

/// 餐次
enum MealType: String, Codable, CaseIterable {
    case breakfast, lunch, dinner, snack

    var displayName: String {
        switch self {
        case .breakfast: return "早餐"
        case .lunch: return "午餐"
        case .dinner: return "晚餐"
        case .snack: return "加餐"
        }
    }

    /// 按当前时间推断餐次
    static func inferred(from date: Date = .now) -> MealType {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<10: return .breakfast
        case 10..<15: return .lunch
        case 15..<21: return .dinner
        default: return .snack
        }
    }
}

/// 身体指标类型
enum MetricKind: String, Codable, CaseIterable {
    case weight, bodyFat, waist

    var displayName: String {
        switch self {
        case .weight: return "体重"
        case .bodyFat: return "体脂率"
        case .waist: return "腰围"
        }
    }

    var unit: String {
        switch self {
        case .weight: return "kg"
        case .bodyFat: return "%"
        case .waist: return "cm"
        }
    }
}

/// 课程表某一天的状态
enum PlanDayStatus: String, Codable {
    case pending, done, skipped

    var displayName: String {
        switch self {
        case .pending: return "待做"
        case .done: return "已完成"
        case .skipped: return "已跳过"
        }
    }
}

/// 教练对话角色
enum ChatRole: String, Codable {
    case user, assistant
}

/// 训练目标
enum TrainingGoal: String, Codable, CaseIterable {
    case muscleGain, fatLoss, strength, general

    var displayName: String {
        switch self {
        case .muscleGain: return "增肌"
        case .fatLoss: return "减脂"
        case .strength: return "力量"
        case .general: return "综合健康"
        }
    }
}

// MARK: - 训练

/// 一次训练（可能包含多个动作的多组记录）
@Model
final class WorkoutSession {
    var durationMinutes: Int?
    var planDayUUID: UUID?
    var uuid: UUID = UUID()
    var date: Date = Date()
    /// 训练主题，如「胸 + 三头」「深蹲日」
    var title: String = ""
    var note: String = ""
    var sourceRaw: String = RecordSource.text.rawValue
    /// HealthKit 同步来源的唯一标识（用于去重）
    var healthKitUUID: String?
    var createdAt: Date = Date()

    var source: RecordSource {
        get { RecordSource(rawValue: sourceRaw) ?? .text }
        set { sourceRaw = newValue.rawValue }
    }

    @Relationship(deleteRule: .cascade, inverse: \ExerciseSet.session)
    var sets: [ExerciseSet] = []

    init(
        date: Date = .now,
        title: String = "",
        note: String = "",
        source: RecordSource = .text,
        healthKitUUID: String? = nil
    ) {
        self.date = date
        self.title = title
        self.note = note
        self.sourceRaw = source.rawValue
        self.healthKitUUID = healthKitUUID
        self.createdAt = .now
    }

    /// 总容量（kg），用于训练量分析
    var totalVolumeKg: Double {
        sets.reduce(0) { $0 + $1.volumeKg }
    }

    /// 涉及的动作品名（去重、按录入顺序）
    var exerciseNames: [String] {
        var seen = Set<String>()
        return sets
            .sorted { $0.order < $1.order }
            .compactMap { seen.insert($0.exerciseName).inserted ? $0.exerciseName : nil }
    }
}

/// 一个动作的一组记录（同重量同次数可记 setCount 组）
@Model
final class ExerciseSet {
    var uuid: UUID = UUID()
    var exerciseName: String = ""
    var weightKg: Double = 0
    var reps: Int = 0
    /// 组数：「5×5」→ reps 5，setCount 5
    var setCount: Int = 1
    /// 主观疲劳度 1–10
    var rpe: Double?
    var order: Int = 0
    var session: WorkoutSession?

    /// 逐组的实情（训练执行页打勾产生的）。
    /// 汇总字段（weightKg / reps / setCount）仍然是主展示字段 ——
    /// 记录列表不该为了一次减重就把一个动作展开成五行。
    @Relationship(deleteRule: .cascade, inverse: \SetLog.exerciseSet)
    var setLogs: [SetLog] = []

    init(
        exerciseName: String,
        weightKg: Double,
        reps: Int,
        setCount: Int = 1,
        rpe: Double? = nil,
        order: Int = 0
    ) {
        self.exerciseName = exerciseName
        self.weightKg = weightKg
        self.reps = reps
        self.setCount = setCount
        self.rpe = rpe
        self.order = order
    }

    /// 本组总容量（kg）
    var volumeKg: Double {
        weightKg * Double(reps * setCount)
    }

    /// Epley 公式估算的 1RM
    var estimatedOneRepMax: Double {
        guard weightKg > 0, reps > 0 else { return 0 }
        return weightKg * (1 + Double(reps) / 30)
    }

    /// 「100kg × 5次 × 5组」样式描述
    var displayText: String {
        var text = "\(formattedWeight) × \(reps)次"
        if setCount > 1 { text += " × \(setCount)组" }
        return text
    }

    var formattedWeight: String {
        weightKg.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(weightKg))kg"
            : String(format: "%.1fkg", weightKg)
    }
}

// MARK: - 饮食

/// 一餐记录
@Model
final class MealEntry {
    var uuid: UUID = UUID()
    var date: Date = Date()
    var mealTypeRaw: String = MealType.lunch.rawValue
    var note: String = ""
    var sourceRaw: String = RecordSource.text.rawValue
    /// 照片原图（照片识别时写入，externalStorage 存外部文件）
    @Attribute(.externalStorage) var photoData: Data?
    /// 是否带照片。列表里只读这个轻量标记，避免为了判断有无照片而加载全部原图
    var hasPhoto: Bool = false
    var createdAt: Date = Date()

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .lunch }
        set { mealTypeRaw = newValue.rawValue }
    }

    var source: RecordSource {
        get { RecordSource(rawValue: sourceRaw) ?? .text }
        set { sourceRaw = newValue.rawValue }
    }

    @Relationship(deleteRule: .cascade, inverse: \FoodItem.meal)
    var items: [FoodItem] = []

    init(
        date: Date = .now,
        mealType: MealType? = nil,
        note: String = "",
        source: RecordSource = .text
    ) {
        self.date = date
        self.mealTypeRaw = (mealType ?? MealType.inferred(from: date)).rawValue
        self.note = note
        self.sourceRaw = source.rawValue
        self.createdAt = .now
    }

    var totalCalories: Double { items.reduce(0) { $0 + $1.calories } }
    var totalProteinG: Double { items.reduce(0) { $0 + $1.proteinG } }
    var totalCarbsG: Double { items.reduce(0) { $0 + $1.carbsG } }
    var totalFatG: Double { items.reduce(0) { $0 + $1.fatG } }
    /// 是否含 AI 估算项（界面上标「AI 估算」徽标）
    var containsEstimate: Bool { items.contains { $0.isEstimated } }

    /// 「牛肉面 等 2 项」样式摘要
    var summary: String {
        guard let first = items.first?.name else { return note.isEmpty ? "未命名" : note }
        return items.count > 1 ? "\(first) 等 \(items.count) 项" : first
    }
}

/// 单个食物项
@Model
final class FoodItem {
    var uuid: UUID = UUID()
    var name: String = ""
    /// 分量描述，如「1 碗」「200g」
    var amountText: String = ""
    var calories: Double = 0
    var proteinG: Double = 0
    var carbsG: Double = 0
    var fatG: Double = 0
    /// 是否为 AI 估算值（用户可修正）
    var isEstimated: Bool = true
    var meal: MealEntry?

    init(
        name: String,
        amountText: String = "",
        calories: Double = 0,
        proteinG: Double = 0,
        carbsG: Double = 0,
        fatG: Double = 0,
        isEstimated: Bool = true
    ) {
        self.name = name
        self.amountText = amountText
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.isEstimated = isEstimated
    }
}

// MARK: - 身体指标

/// 体重 / 体脂 / 腰围（时间序列）
@Model
final class BodyMetric {
    var uuid: UUID = UUID()
    var date: Date = Date()
    var kindRaw: String = MetricKind.weight.rawValue
    var value: Double = 0
    var note: String = ""

    var kind: MetricKind {
        get { MetricKind(rawValue: kindRaw) ?? .weight }
        set { kindRaw = newValue.rawValue }
    }

    init(date: Date = .now, kind: MetricKind = .weight, value: Double, note: String = "") {
        self.date = date
        self.kindRaw = kind.rawValue
        self.value = value
        self.note = note
    }
}

// MARK: - 健康数据（HealthKit 只读同步）

/// 每日健康快照
@Model
final class HealthSnapshot {
    /// 当天 00:00（唯一键，用于按天 upsert）
    @Attribute(.unique) var day: Date = Date()
    var sleepHours: Double = 0
    var hrvMs: Double = 0
    var restingHeartRate: Double = 0
    var steps: Int = 0
    var activeEnergyKcal: Double = 0
    var updatedAt: Date = Date()

    init(
        day: Date,
        sleepHours: Double = 0,
        hrvMs: Double = 0,
        restingHeartRate: Double = 0,
        steps: Int = 0,
        activeEnergyKcal: Double = 0
    ) {
        self.day = Calendar.current.startOfDay(for: day)
        self.sleepHours = sleepHours
        self.hrvMs = hrvMs
        self.restingHeartRate = restingHeartRate
        self.steps = steps
        self.activeEnergyKcal = activeEnergyKcal
        self.updatedAt = .now
    }

    /// 恢复质量粗判：睡眠 < 6.5h 或 HRV 明显偏低时提示
    var recoveryHint: String? {
        if sleepHours > 0 && sleepHours < 6.5 { return "睡眠偏低" }
        if hrvMs > 0 && hrvMs < 35 { return "HRV 偏低" }
        return nil
    }
}

/// HealthKit 同步的运动记录（只读，不可编辑）
@Model
final class HealthWorkout {
    var uuid: UUID = UUID()
    /// HealthKit 侧的唯一标识（去重用）
    @Attribute(.unique) var healthKitUUID: String = ""
    var date: Date = Date()
    /// 运动类型名，如「户外跑步」
    var activityName: String = ""
    var durationMinutes: Double = 0
    var distanceKm: Double?
    var averageHeartRate: Double?
    /// 数据来源 App 名（如 Apple Watch）
    var sourceName: String = ""

    init(
        healthKitUUID: String,
        date: Date,
        activityName: String,
        durationMinutes: Double,
        distanceKm: Double? = nil,
        averageHeartRate: Double? = nil,
        sourceName: String = "Apple Watch"
    ) {
        self.healthKitUUID = healthKitUUID
        self.date = date
        self.activityName = activityName
        self.durationMinutes = durationMinutes
        self.distanceKm = distanceKm
        self.averageHeartRate = averageHeartRate
        self.sourceName = sourceName
    }

    var durationText: String {
        let minutes = Int(durationMinutes.rounded())
        if minutes >= 60 {
            return "\(minutes / 60) 小时 \(minutes % 60) 分"
        }
        return "\(minutes) 分钟"
    }

    var paceText: String? {
        guard let km = distanceKm, km > 0, durationMinutes > 0 else { return nil }
        let secondsPerKm = Int((durationMinutes * 60 / km).rounded())
        return String(format: "%d'%02d\"", secondsPerKm / 60, secondsPerKm % 60)
    }
}

// MARK: - 原始笔记（解析失败的降级存储）

/// 自然语言原文。解析失败也会留存，绝不丢用户数据
@Model
final class RawNote {
    @Attribute(.externalStorage) var photoData: Data?
    var uuid: UUID = UUID()
    var text: String = ""
    var date: Date = Date()
    var statusRaw: String = RawNoteStatus.pending.rawValue
    /// 解析失败原因（用于事后排查）
    var failureReason: String = ""
    var createdAt: Date = Date()

    var status: RawNoteStatus {
        get { RawNoteStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    init(text: String, date: Date = .now, failureReason: String = "") {
        self.text = text
        self.date = date
        self.failureReason = failureReason
        self.createdAt = .now
    }
}

// MARK: - 分析报告

/// AI 生成的周报 / 月报
@Model
final class AnalysisReport {
    var uuid: UUID = UUID()
    var periodStart: Date = Date()
    var periodEnd: Date = Date()
    /// 一句话结论（列表页展示）
    var headline: String = ""
    /// 报告正文
    var body: String = ""
    /// 标签，以逗号分隔存储（如「平台期,恢复警告」）
    var tagsText: String = ""
    /// 生成时引用的数据摘要（透明展示 AI 依据）
    var citedDataText: String = ""
    var createdAt: Date = Date()

    init(
        periodStart: Date,
        periodEnd: Date,
        headline: String,
        body: String,
        tags: [String] = [],
        citedDataText: String = ""
    ) {
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.headline = headline
        self.body = body
        self.tagsText = tags.joined(separator: ",")
        self.citedDataText = citedDataText
        self.createdAt = .now
    }

    var tags: [String] {
        tagsText.split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }

    var periodText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return "\(formatter.string(from: periodStart)) – \(formatter.string(from: periodEnd))"
    }
}

// MARK: - 课程表（P1）

/// 一份课程计划
@Model
final class Plan {
    var uuid: UUID = UUID()
    var title: String = ""
    var goalRaw: String = TrainingGoal.muscleGain.rawValue
    var startDate: Date = Date()
    var weeks: Int = 4
    var note: String = ""
    var isActive: Bool = true
    var createdAt: Date = Date()

    var goal: TrainingGoal {
        get { TrainingGoal(rawValue: goalRaw) ?? .general }
        set { goalRaw = newValue.rawValue }
    }

    @Relationship(deleteRule: .cascade, inverse: \PlanDay.plan)
    var days: [PlanDay] = []

    init(
        title: String,
        goal: TrainingGoal = .muscleGain,
        startDate: Date = .now,
        weeks: Int = 4,
        note: String = ""
    ) {
        self.title = title
        self.goalRaw = goal.rawValue
        self.startDate = startDate
        self.weeks = weeks
        self.note = note
        self.createdAt = .now
    }

    var sortedDays: [PlanDay] {
        days.sorted { $0.date < $1.date }
    }

    /// 今天对应的训练日
    func day(on date: Date = .now) -> PlanDay? {
        let calendar = Calendar.current
        return days.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    var completedCount: Int { days.filter { $0.status == .done }.count }
}

/// 课程表中的一天
@Model
final class PlanDay {
    var uuid: UUID = UUID()
    var date: Date = Date()
    /// Optional exact start; old date-only plans remain readable without invented times.
    var scheduledStart: Date?
    var durationMinutes: Int?
    var title: String = ""
    var statusRaw: String = PlanDayStatus.pending.rawValue
    var order: Int = 0
    /// 备注（教练调整说明、用户自己的提醒）
    var note: String = ""
    var plan: Plan?

    var status: PlanDayStatus {
        get { PlanDayStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    @Relationship(deleteRule: .cascade, inverse: \PlanExercise.day)
    var exercises: [PlanExercise] = []

    init(date: Date, title: String, order: Int = 0) {
        self.date = date
        self.title = title
        self.order = order
    }

    var sortedExercises: [PlanExercise] {
        exercises.sorted { $0.order < $1.order }
    }

    var exerciseSummary: String {
        let names = sortedExercises.prefix(2).map(\.name).joined(separator: "、")
        let suffix = exercises.count > 2 ? " 等 \(exercises.count) 个动作" : ""
        return names.isEmpty ? "暂无动作" : names + suffix
    }
}

/// 课程表中的动作
@Model
final class PlanExercise {
    var uuid: UUID = UUID()
    var name: String = ""
    /// 组次描述，如「4×10」
    var setsText: String = ""
    var targetWeightKg: Double?
    var order: Int = 0
    var day: PlanDay?

    init(name: String, setsText: String = "", targetWeightKg: Double? = nil, order: Int = 0) {
        self.name = name
        self.setsText = setsText
        self.targetWeightKg = targetWeightKg
        self.order = order
    }
}

// MARK: - 教练对话（P1）

/// 与 CoachAgent 的一条消息
@Model
final class ChatMessage {
    var conversationID: UUID?
    var isRealtime: Bool = false
    var pendingLifeRevision: String?
    var uuid: UUID = UUID()
    var roleRaw: String = ChatRole.user.rawValue
    var content: String = ""
    var date: Date = Date()
    /// function call 返回、等待用户确认的计划 JSON
    var pendingPlanJSON: String?
    /// 待确认计划的展示标题
    var pendingPlanTitle: String?
    /// 已确认的计划仍保留 JSON，供聊天历史回看。
    var planAcceptedAt: Date? = nil
    var planDecisionRaw: String? = nil
    var adjustmentDecisionRaw: String? = nil
    var adjustmentAppliedAt: Date? = nil
    /// 本机生成的纯改期撤销凭据，模型不能写入。
    var adjustmentUndoJSON: String? = nil
    /// 仅首条消息存储本会话的可重建上下文记忆，旧数据库缺省为 nil。
    var coachMemoryJSON: String? = nil
    /// function call 返回、等待用户确认的计划调整 JSON
    var pendingAdjustmentJSON: String?
    /// 模型的思考过程（有就存，用于回看）
    var toolActivityJSON: String? = nil
    var reasoningText: String?

    var role: ChatRole {
        get { ChatRole(rawValue: roleRaw) ?? .user }
        set { roleRaw = newValue.rawValue }
    }

    var hasPendingPlan: Bool { pendingPlanJSON != nil && planAcceptedAt == nil && planDecisionRaw == nil }
    var hasPendingAdjustment: Bool { pendingAdjustmentJSON != nil && adjustmentDecisionRaw == nil }

    init(
        role: ChatRole,
        content: String,
        pendingPlanJSON: String? = nil,
        pendingPlanTitle: String? = nil,
        pendingAdjustmentJSON: String? = nil,
        reasoningText: String? = nil
    ) {
        self.roleRaw = role.rawValue
        self.content = content
        self.pendingPlanJSON = pendingPlanJSON
        self.pendingPlanTitle = pendingPlanTitle
        self.pendingAdjustmentJSON = pendingAdjustmentJSON
        self.reasoningText = reasoningText
        self.date = .now
    }
}

/// Tutorial metadata only. No video, thumbnail, or webpage body is stored.
@Model
final class ExerciseTutorialCache {
    var key: String = ""
    var resultsJSON: String = "[]"
    var selectedURL: String? = nil
    var rejectedURLsJSON: String = "[]"
    var activityJSON: String? = nil
    var checkedAt: Date = Date.distantPast
    var status: String = "idle"
    init(key: String) { self.key = key }
}
