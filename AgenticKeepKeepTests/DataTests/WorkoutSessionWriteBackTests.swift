import SwiftData
import XCTest
@testable import AgenticKeepKeep

/// 训练执行页的**落库**部分：草稿写入、写回正式记录、中断恢复、过期清理。
///
/// 引擎的推进规则在 `WorkoutSessionEngineTests` 里测；这里测的是它跟 SwiftData 的接缝 ——
/// 这一轮是本项目第一次改数据模型，接缝处出错最容易，也最难在界面上看出来。
@MainActor
final class WorkoutSessionWriteBackTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try AppModelContainer.inMemory())
    }

    /// 造一个「胸 + 三头 / 卧推 4×8 @60kg」的训练日
    private func makePlanDay(in context: ModelContext, setsText: String = "4×8") -> PlanDay {
        let plan = Plan(title: "测试计划")
        context.insert(plan)

        let day = PlanDay(date: .now, title: "胸 + 三头")
        day.plan = plan
        context.insert(day)

        let exercise = PlanExercise(name: "杠铃卧推", setsText: setsText, targetWeightKg: 60, order: 0)
        exercise.day = day
        context.insert(exercise)

        try? context.save()
        return day
    }

    // MARK: - 打勾落库

    func testCompletingSetWritesLogToDraft() throws {
        let context = try makeContext()
        let day = makePlanDay(in: context)
        let model = WorkoutSessionViewModel(planDay: day, context: context)

        model.completeCurrentSet()
        model.completeCurrentSet()

        XCTAssertEqual(model.draft.logs.count, 2, "每次打勾都要落一条 SetLog")
        XCTAssertEqual(model.completedSets(for: model.engine.exercises[0]).count, 2)
    }

    func testCompleteSetUsesPlannedDefaultsWithoutInput() throws {
        let context = try makeContext()
        let day = makePlanDay(in: context)
        let model = WorkoutSessionViewModel(planDay: day, context: context)

        model.completeCurrentSet()   // 不碰输入框

        let log = model.draft.logs[0]
        XCTAssertEqual(log.weightKg, 60, "默认应当沿用计划的 60kg")
        XCTAssertEqual(log.reps, 8, "默认应当沿用计划的 8 次")
    }

    func testCompleteSetUsesEditedValues() throws {
        let context = try makeContext()
        let day = makePlanDay(in: context)
        let model = WorkoutSessionViewModel(planDay: day, context: context)

        model.draftWeightText = "55"
        model.draftRepsText = "6"
        model.completeCurrentSet()

        XCTAssertEqual(model.draft.logs[0].weightKg, 55)
        XCTAssertEqual(model.draft.logs[0].reps, 6)
    }

    /// 计划里没写重量时不编造（FR7.4）
    func testMissingPlannedWeightStaysZero() throws {
        let context = try makeContext()
        let plan = Plan(title: "无重量的计划")
        context.insert(plan)
        let day = PlanDay(date: .now, title: "自重日")
        day.plan = plan
        context.insert(day)
        let exercise = PlanExercise(name: "俯卧撑", setsText: "3×15", targetWeightKg: nil, order: 0)
        exercise.day = day
        context.insert(exercise)
        try? context.save()

        let model = WorkoutSessionViewModel(planDay: day, context: context)
        model.completeCurrentSet()

        XCTAssertEqual(model.draft.logs[0].weightKg, 0, "计划没写重量就留空，不该编一个出来")
        XCTAssertEqual(model.draft.logs[0].reps, 15)
    }

    func testUndoDeletesLog() throws {
        let context = try makeContext()
        let day = makePlanDay(in: context)
        let model = WorkoutSessionViewModel(planDay: day, context: context)

        model.completeCurrentSet()
        model.completeCurrentSet()
        model.undoLastSet()

        XCTAssertEqual(model.draft.logs.count, 1)
    }

    // MARK: - 写回

    func testFinishCreatesSessionAndMarksDayDone() throws {
        let context = try makeContext()
        let day = makePlanDay(in: context)
        let model = WorkoutSessionViewModel(planDay: day, context: context)

        for _ in 0..<4 { model.completeCurrentSet() }
        XCTAssertTrue(model.finish(planDay: day))

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].title, "胸 + 三头")
        XCTAssertEqual(sessions[0].sets.count, 1, "一个动作合并成一行")
        XCTAssertEqual(sessions[0].sets[0].setCount, 4)
        XCTAssertEqual(day.status, .done)

        // 草稿用完即删
        XCTAssertTrue(try context.fetch(FetchDescriptor<WorkoutSessionDraft>()).isEmpty)
    }

    func testFinishedWorkoutHasLifeFeedbackIdentityAndCannotBeSavedTwice() throws {
        let context = try makeContext(), day = makePlanDay(in: context)
        let model = WorkoutSessionViewModel(planDay: day, context: context)
        model.completeCurrentSet(); XCTAssertTrue(model.finish(planDay: day))
        let session = try XCTUnwrap(context.fetch(FetchDescriptor<WorkoutSession>()).first)
        XCTAssertEqual(session.planDayUUID, day.uuid); XCTAssertEqual(session.uuid, model.completedSessionID)
        XCTAssertGreaterThan(try XCTUnwrap(session.durationMinutes), 0)
        XCTAssertFalse(model.finish(planDay: day)); XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
    }

    /// 第 4 组减重：汇总行取**最重的那组**当代表，逐组实情留在 SetLog 上
    func testRepresentativeWeightIsTheHeaviestSet() throws {
        let context = try makeContext()
        let day = makePlanDay(in: context)
        let model = WorkoutSessionViewModel(planDay: day, context: context)

        model.completeCurrentSet()          // 60 × 8
        model.draftWeightText = "50"        // 减重
        model.completeCurrentSet()          // 50 × 8
        model.finish(planDay: day)

        let session = try context.fetch(FetchDescriptor<WorkoutSession>()).first
        let record = try XCTUnwrap(session?.sets.first)
        XCTAssertEqual(record.weightKg, 60, "汇总行取最重的一组")
        XCTAssertEqual(record.setCount, 2)
        XCTAssertEqual(record.setLogs.count, 2, "逐组实情挂在汇总行上")
        XCTAssertEqual(Set(record.setLogs.map(\.weightKg)), [60, 50])
    }

    /// 一组都没勾就结束：不留任何痕迹（FR5.4）
    func testFinishWithNoSetsDiscardsDraft() throws {
        let context = try makeContext()
        let day = makePlanDay(in: context)
        let model = WorkoutSessionViewModel(planDay: day, context: context)

        XCTAssertFalse(model.finish(planDay: day))
        XCTAssertTrue(try context.fetch(FetchDescriptor<WorkoutSession>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<WorkoutSessionDraft>()).isEmpty)
        XCTAssertEqual(day.status, .pending, "没练就不该标成已完成")
    }

    // MARK: - 中断恢复

    func testResumeKeepsCompletedSets() throws {
        let context = try makeContext()
        let day = makePlanDay(in: context)

        let first = WorkoutSessionViewModel(planDay: day, context: context)
        first.completeCurrentSet()
        first.completeCurrentSet()
        first.moveTo(index: 0)

        // 模拟退出再进
        let second = WorkoutSessionViewModel(planDay: day, context: context)
        XCTAssertEqual(second.engine.completed.count, 2, "回来时勾选状态还在")
        XCTAssertEqual(second.currentSetIndex(for: second.engine.exercises[0]), 3)
    }

    func testDraftIsReusedNotDuplicated() throws {
        let context = try makeContext()
        let day = makePlanDay(in: context)

        _ = WorkoutSessionViewModel(planDay: day, context: context)
        _ = WorkoutSessionViewModel(planDay: day, context: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSessionDraft>()).count, 1)
    }

    func testPurgeStaleDrafts() throws {
        let context = try makeContext()
        let day = makePlanDay(in: context)

        let stale = WorkoutSessionDraft(
            planDayUUID: day.uuid,
            title: "两天前没练完的",
            startedAt: Date().addingTimeInterval(-48 * 3_600)
        )
        context.insert(stale)
        try context.save()

        XCTAssertEqual(WorkoutSessionViewModel.purgeStaleDrafts(in: context), 1)
        XCTAssertTrue(try context.fetch(FetchDescriptor<WorkoutSessionDraft>()).isEmpty)
    }

    func testPurgeKeepsFreshDrafts() throws {
        let context = try makeContext()
        let day = makePlanDay(in: context)
        _ = WorkoutSessionViewModel(planDay: day, context: context)

        XCTAssertEqual(WorkoutSessionViewModel.purgeStaleDrafts(in: context), 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSessionDraft>()).count, 1)
    }

    // MARK: - 边界

    func testPlanDayWithoutExercisesIsUnavailable() throws {
        let context = try makeContext()
        let plan = Plan(title: "空计划")
        context.insert(plan)
        let day = PlanDay(date: .now, title: "空训练日")
        day.plan = plan
        context.insert(day)
        try context.save()

        let model = WorkoutSessionViewModel(planDay: day, context: context)
        XCTAssertNotNil(model.unavailableReason, "没有动作的日子要说清楚，而不是给一个空流程")
        XCTAssertNil(model.currentExercise)
    }

    /// 「4 组 × 10 次」这种写法也要能解析出组数，否则整轮都不会自动切片
    func testChineseSetsTextParses() throws {
        let context = try makeContext()
        let day = makePlanDay(in: context, setsText: "4 组 × 10 次")
        let model = WorkoutSessionViewModel(planDay: day, context: context)

        model.completeCurrentSet()
        XCTAssertEqual(model.currentSetIndex(for: model.engine.exercises[0]), 2)
    }
}
