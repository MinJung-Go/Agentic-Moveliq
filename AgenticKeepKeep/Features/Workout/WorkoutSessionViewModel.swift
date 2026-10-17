import Foundation
import SwiftData
import SwiftUI

/// 训练执行页的状态。
///
/// 把「纯逻辑的 `WorkoutSessionEngine`」和「落库的草稿」缝在一起：
/// - 推进规则全在引擎里（可单测）
/// - 这里只负责把每次打勾写进 `SetLog`、把草稿读回引擎
@MainActor
final class WorkoutSessionViewModel: ObservableObject {

    @Published private(set) var engine: WorkoutSessionEngine
    /// 当前这一组待提交的重量 / 次数（默认取自计划，可直接改）
    @Published var draftWeightText: String
    @Published var draftRepsText: String
    @Published var isSummaryPresented = false
    @Published private(set) var completedSessionID: UUID?
    @Published private(set) var completionError: String?

    let draft: WorkoutSessionDraft
    /// 计划日已被删除 / 没有动作时给出说明
    let unavailableReason: String?

    private let context: ModelContext

    // MARK: - 构造

    init(planDay: PlanDay, context: ModelContext) {
        self.context = context

        let ordered = planDay.sortedExercises
        let exercises = ordered.map { exercise -> WorkoutSessionEngine.Exercise in
            let parsed = SetSpecParser.parse(exercise.setsText)
            return WorkoutSessionEngine.Exercise(
                id: exercise.uuid,
                name: exercise.name,
                plannedSets: parsed?.sets,
                plannedReps: parsed?.reps,
                plannedWeightKg: exercise.targetWeightKg,
                setsText: exercise.setsText
            )
        }

        self.unavailableReason = exercises.isEmpty ? "这个训练日还没有动作，先在课程表里加上。" : nil

        // 已有草稿就接着练（中断恢复），没有就新建
        let existing = Self.findDraft(for: planDay, in: context)
        let draft = existing ?? WorkoutSessionDraft(planDayUUID: planDay.uuid, title: planDay.title)
        if existing == nil { context.insert(draft) }
        self.draft = draft

        let completed = draft.logs.compactMap { log -> WorkoutSessionEngine.CompletedSet? in
            guard let exerciseUUID = log.exerciseUUID else { return nil }
            return WorkoutSessionEngine.CompletedSet(
                exerciseID: exerciseUUID,
                setIndex: log.setIndex,
                weightKg: log.weightKg,
                reps: log.reps,
                completedAt: log.completedAt
            )
        }

        self.engine = WorkoutSessionEngine(
            exercises: exercises,
            startedAt: draft.startedAt,
            completed: completed,
            currentIndex: draft.currentIndex
        )

        let current = exercises.indices.contains(draft.currentIndex) ? exercises[draft.currentIndex] : nil
        self.draftWeightText = current?.plannedWeightKg.map { Format.number($0, decimals: $0.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1) } ?? ""
        self.draftRepsText = current?.plannedReps.map(String.init) ?? ""
    }

    // MARK: - 查询

    var currentExercise: WorkoutSessionEngine.Exercise? { engine.currentExercise }

    var elapsedText: String {
        let minutes = Int(engine.summary().duration / 60)
        return minutes < 1 ? "刚开始" : "已练 \(minutes) 分钟"
    }

    var positionText: String {
        guard !engine.exercises.isEmpty else { return "" }
        return "第 \(engine.currentIndex + 1) / \(engine.exercises.count) 个动作"
    }

    func completedSets(for exercise: WorkoutSessionEngine.Exercise) -> [WorkoutSessionEngine.CompletedSet] {
        engine.sets(for: exercise)
    }

    /// 当前该做第几组。这个动作做完了就返回 nil
    func currentSetIndex(for exercise: WorkoutSessionEngine.Exercise) -> Int? {
        engine.isExerciseFinished(exercise) ? nil : engine.nextSetIndex(for: exercise)
    }

    var hasAnyProgress: Bool { !engine.completed.isEmpty }

    // MARK: - 推进

    /// 勾掉当前这一组。用输入框里的重量次数，空着就用计划值
    func completeCurrentSet() {
        guard let exercise = currentExercise else { return }

        let weight = ParsedInput.double(draftWeightText) ?? exercise.plannedWeightKg ?? 0
        let reps = ParsedInput.int(draftRepsText) ?? exercise.plannedReps ?? 0
        guard reps > 0 else { return }

        let setIndex = engine.nextSetIndex(for: exercise)
        let log = SetLog(
            exerciseUUID: exercise.id,
            setIndex: setIndex,
            weightKg: weight,
            reps: reps
        )
        log.draft = draft
        context.insert(log)

        let finishedExercise = engine.completeSet(weightKg: weight, reps: reps)
        try? context.save()
        Haptics.tap()

        if finishedExercise || engine.isExerciseFinished(exercise) {
            engine.advanceToNextUnfinished()
            draft.currentIndex = engine.currentIndex
            try? context.save()
        }

        syncDraftFields()
    }

    func undoLastSet() {
        guard let exercise = currentExercise else { return }
        guard let last = engine.sets(for: exercise).last else { return }

        if let log = draft.logs.first(where: { $0.exerciseUUID == exercise.id && $0.setIndex == last.setIndex }) {
            context.delete(log)
        }
        engine.undoSet(for: exercise)
        try? context.save()
        Haptics.warning()
        syncDraftFields()
    }

    func moveTo(index: Int) {
        engine.moveTo(index: index)
        draft.currentIndex = engine.currentIndex
        try? context.save()
        syncDraftFields()
    }

    /// 切到下一个还没做完的动作。
    /// `engine` 对外是只读的，所以推进要由这里代劳，不能让视图直接改。
    func advanceToNextUnfinished() {
        engine.advanceToNextUnfinished()
        draft.currentIndex = engine.currentIndex
        try? context.save()
        syncDraftFields()
    }

    var isAllFinished: Bool { engine.isFinished }

    /// 切到动作 / 撤回之后，把输入框重置成「这个动作下一组」的计划值
    private func syncDraftFields() {
        guard let exercise = currentExercise else {
            draftWeightText = ""
            draftRepsText = ""
            return
        }
        draftWeightText = exercise.plannedWeightKg.map {
            Format.number($0, decimals: $0.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)
        } ?? ""
        draftRepsText = exercise.plannedReps.map(String.init) ?? ""
    }

    // MARK: - 结束

    /// 汇总
    var summary: WorkoutSessionEngine.Summary { engine.summary() }

    /// 写回正式记录，并把训练日标为已完成。返回是否真的写了
    @discardableResult
    func finish(planDay: PlanDay?) -> Bool {
        guard completedSessionID == nil else { return false }
        let summary = engine.summary()
        guard summary.setCount > 0 else {
            discard()
            return false
        }

        do {
            try context.save()
            let session = WorkoutSession(date: draft.startedAt, title: draft.title)
            session.planDayUUID = planDay?.uuid
            session.durationMinutes = max(1, Int(summary.duration / 60))
            context.insert(session)

            // 每个动作合并成一行：取**最重的一组**当代表，组数按实际
            // （逐组的实情留在 SetLog 里，记录列表不该展开成几十行）
            for (order, exercise) in engine.exercises.enumerated() {
                let sets = engine.sets(for: exercise)
                guard !sets.isEmpty else { continue }

                let representative = sets.max { $0.weightKg < $1.weightKg } ?? sets[0]
                let record = ExerciseSet(
                    exerciseName: exercise.name,
                    weightKg: representative.weightKg,
                    reps: representative.reps,
                    setCount: sets.count,
                    order: order
                )
                record.session = session
                context.insert(record)

                // 把逐组明细挂到这一行上 —— 从草稿转正
                for log in draft.logs where log.exerciseUUID == exercise.id {
                    log.exerciseSet = record
                    log.draft = nil
                }
            }

            planDay?.status = .done
            context.delete(draft)
            try context.save()
            completedSessionID = session.uuid
            completionError = nil
            NotificationCenter.default.post(name: .coachLifeChanged, object: nil)

            Haptics.success()
            return true
        } catch { context.rollback(); completionError = "训练尚未保存，请重试。\(error.localizedDescription)"; return false }
    }

    /// 一组都没勾就退出：不留痕迹
    func discard() {
        context.delete(draft)
        try? context.save()
    }

    // MARK: - 草稿查找与清理

    static func findDraft(for planDay: PlanDay, in context: ModelContext) -> WorkoutSessionDraft? {
        let uuid = planDay.uuid
        let descriptor = FetchDescriptor<WorkoutSessionDraft>(
            predicate: #Predicate { $0.planDayUUID == uuid }
        )
        return try? context.fetch(descriptor).first
    }

    /// 超过 24 小时没动过的草稿视为放弃。
    /// 不做这一步的话，用户半途而废的训练会在库里堆着，下次进来还会被问「继续吗」。
    @discardableResult
    static func purgeStaleDrafts(in context: ModelContext, olderThan hours: Double = 24) -> Int {
        let cutoff = Date().addingTimeInterval(-hours * 3_600)
        let descriptor = FetchDescriptor<WorkoutSessionDraft>(
            predicate: #Predicate { $0.startedAt < cutoff }
        )
        let stale = (try? context.fetch(descriptor)) ?? []
        for draft in stale { context.delete(draft) }
        if !stale.isEmpty { try? context.save() }
        return stale.count
    }
}
