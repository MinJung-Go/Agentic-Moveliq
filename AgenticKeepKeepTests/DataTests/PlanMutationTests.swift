import XCTest
import SwiftData
@testable import AgenticKeepKeep

@MainActor
final class PlanMutationTests: XCTestCase {
    private func fixture() throws -> (ModelContext, Plan, PlanDay) {
        let context = ModelContext(try AppModelContainer.inMemory())
        let plan = Plan(title: "旧计划")
        let day = PlanDay(date: .now, title: "胸部", order: 0)
        context.insert(plan)
        day.plan = plan
        context.insert(day)
        let exercise = PlanExercise(name: "卧推", setsText: "4×8", targetWeightKg: 60)
        exercise.day = day
        context.insert(exercise)
        try context.save()
        return (context, plan, day)
    }

    private func proposal(_ changes: [[String: Any]], plan: Plan, context: ModelContext) throws -> ChatMessage {
        let data = try JSONSerialization.data(withJSONObject: [
            "planID": plan.uuid.uuidString, "revision": PlanMutationStore.revision(plan),
            "summary": "调整", "changes": changes
        ])
        let message = ChatMessage(role: .assistant, content: "", pendingAdjustmentJSON: String(decoding: data, as: UTF8.self))
        context.insert(message)
        try context.save()
        return message
    }

    func testReplacementActuallyChangesExercisesAndCannotApplyTwice() throws {
        let (context, plan, day) = try fixture()
        let message = try proposal([["action": "replace", "dayID": day.uuid.uuidString, "detail": "换动作",
                                    "exercises": [["name": "俯卧撑", "setsText": "3×12"]]]], plan: plan, context: context)
        XCTAssertNotNil(try PlanMutationStore.apply(message: message, context: context))
        XCTAssertEqual(day.exercises.map(\.name), ["俯卧撑"])
        XCTAssertEqual(day.exercises.first?.setsText, "3×12")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlanExercise>()), 1)
        XCTAssertNil(try PlanMutationStore.apply(message: message, context: context))
        XCTAssertEqual(message.adjustmentDecisionRaw, "applied")
        XCTAssertTrue(message.content.contains("已更新"))
    }

    func testTimedRescheduleKeepsExactStartAndChangesActualDuration() throws {
        let (context, plan, day) = try fixture()
        day.scheduledStart = CoachLifeTime.at(minute: 19 * 60, on: day.date); day.durationMinutes = 45
        let message = try proposal([["action": "reschedule", "dayID": day.uuid.uuidString, "date": "2027-01-04", "startTime": "20:30", "durationMinutes": 20, "detail": "加班后缩短训练"]], plan: plan, context: context)
        _ = try PlanMutationStore.apply(message: message, context: context)
        let start = try XCTUnwrap(day.scheduledStart)
        XCTAssertTrue(Calendar.current.isDate(start, inSameDayAs: try XCTUnwrap(PlanMutationStore.localDate("2027-01-04"))))
        XCTAssertEqual(Calendar.current.component(.hour, from: start), 20)
        XCTAssertEqual(Calendar.current.component(.minute, from: start), 30)
        XCTAssertEqual(day.durationMinutes, 20); XCTAssertNil(message.adjustmentUndoJSON)
        XCTAssertNil(try PlanMutationStore.apply(message: message, context: context))
    }

    func testRescheduleUsesAbsoluteDateEvenWhenConfirmedLater() throws {
        let (context, plan, day) = try fixture()
        let message = try proposal([["action": "reschedule", "dayID": day.uuid.uuidString, "date": "2026-10-02", "detail": "顺延"]], plan: plan, context: context)
        _ = try PlanMutationStore.apply(message: message, context: context, now: .now.addingTimeInterval(86400))
        XCTAssertEqual(day.date, PlanMutationStore.localDate("2026-10-02"))
    }

    func testRescheduleUndoRestoresDateAndNoteAndCannotReplay() throws {
        let (context, plan, day) = try fixture()
        let oldDate = day.date
        day.note = "原备注"
        let message = try proposal([["action": "reschedule", "dayID": day.uuid.uuidString, "date": "2026-10-02", "detail": "顺延"]], plan: plan, context: context)
        _ = try PlanMutationStore.apply(message: message, context: context)
        XCTAssertNotNil(message.adjustmentUndoJSON)
        XCTAssertTrue(try PlanMutationStore.undoReschedule(message: message, context: context))
        XCTAssertEqual(day.date, oldDate)
        XCTAssertEqual(day.note, "原备注")
        XCTAssertEqual(message.adjustmentDecisionRaw, "undone")
        XCTAssertFalse(try PlanMutationStore.undoReschedule(message: message, context: context))
    }

    func testRescheduleUndoRejectsLaterChanges() throws {
        let (context, plan, day) = try fixture()
        let message = try proposal([["action": "reschedule", "dayID": day.uuid.uuidString, "date": "2026-10-02", "detail": "顺延"]], plan: plan, context: context)
        _ = try PlanMutationStore.apply(message: message, context: context)
        day.title = "用户后续修改"
        try context.save()
        XCTAssertThrowsError(try PlanMutationStore.undoReschedule(message: message, context: context))
        XCTAssertEqual(day.title, "用户后续修改")
        XCTAssertEqual(day.date, PlanMutationStore.localDate("2026-10-02"))
        XCTAssertEqual(message.adjustmentDecisionRaw, "applied")
    }

    func testDestructiveChangeHasNoRescheduleUndo() throws {
        let (context, plan, _) = try fixture()
        let message = try proposal([["action": "delete_plan", "detail": "删除"]], plan: plan, context: context)
        _ = try PlanMutationStore.apply(message: message, context: context)
        XCTAssertNil(message.adjustmentUndoJSON)
        XCTAssertFalse(try PlanMutationStore.undoReschedule(message: message, context: context))
    }

    func testDeletePlanPreservesDailyRecordsAndWorkoutDrafts() throws {
        let (context, plan, day) = try fixture()
        let workout = WorkoutSession(title: "已练完")
        let ongoing = WorkoutSessionDraft(planDayUUID: day.uuid, title: "进行中")
        let snapshot = HealthSnapshot(day: .now, steps: 1000)
        context.insert(workout); context.insert(ongoing); context.insert(snapshot)
        try context.save()
        let message = try proposal([["action": "delete_plan", "detail": "用户要求删除"]], plan: plan, context: context)
        _ = try PlanMutationStore.apply(message: message, context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Plan>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlanDay>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlanExercise>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSessionDraft>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<HealthSnapshot>()), 1)
        XCTAssertTrue(message.content.contains("已删除课程表《旧计划》"))
        XCTAssertNil(try PlanMutationStore.apply(message: message, context: context))
    }

    func testStaleProposalCannotDeleteChangedPlan() throws {
        let (context, plan, _) = try fixture()
        let message = try proposal([["action": "delete_plan", "detail": "删除"]], plan: plan, context: context)
        plan.title = "后来修改的计划"
        try context.save()
        XCTAssertThrowsError(try PlanMutationStore.apply(message: message, context: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Plan>()), 1)
        XCTAssertTrue(message.hasPendingAdjustment)
    }

    func testWrongDayAndInvalidBatchDoNotPartiallyApply() throws {
        let (context, plan, day) = try fixture()
        let message = try proposal([
            ["action": "skip", "dayID": day.uuid.uuidString, "detail": "跳过"],
            ["action": "delete_day", "dayID": UUID().uuidString, "detail": "不存在"]
        ], plan: plan, context: context)
        XCTAssertThrowsError(try PlanMutationStore.apply(message: message, context: context))
        XCTAssertEqual(day.status, .pending)
        XCTAssertTrue(message.hasPendingAdjustment)
    }

    func testAddingDayAndRenamingPlan() throws {
        let (context, plan, _) = try fixture()
        let message = try proposal([
            ["action": "rename_plan", "title": "新计划", "detail": "改名"],
            ["action": "add_day", "title": "腿部", "date": "2026-10-03", "detail": "补一天",
             "exercises": [["name": "深蹲", "setsText": "3×8", "targetWeightKg": 40]]]
        ], plan: plan, context: context)
        _ = try PlanMutationStore.apply(message: message, context: context)
        XCTAssertEqual(plan.title, "新计划")
        XCTAssertEqual(plan.days.count, 2)
        XCTAssertEqual(plan.days.first { $0.title == "腿部" }?.exercises.first?.name, "深蹲")
    }

    func testManualDeleteOnlyRemovesSelectedPlan() throws {
        let (context, plan, _) = try fixture()
        let other = Plan(title: "另一份")
        context.insert(other)
        try context.save()
        try PlanMutationStore.delete(id: plan.uuid, context: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Plan>()).map(\.title), ["另一份"])
    }

    func testLegacyDraftCannotAccidentallyTargetCurrentPlan() throws {
        let (context, _, _) = try fixture()
        let message = ChatMessage(role: .assistant, content: "", pendingAdjustmentJSON: #"{"summary":"旧建议","changes":[{"action":"delete_plan","detail":"删除"}]}"#)
        context.insert(message)
        try context.save()
        XCTAssertThrowsError(try PlanMutationStore.apply(message: message, context: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Plan>()), 1)
    }
    func testDeleteDayKeepsPlanAndCompletedWorkout() throws {
        let (context, plan, day) = try fixture()
        context.insert(WorkoutSession(title: "已练完"))
        try context.save()
        let message = try proposal([["action": "delete_day", "dayID": day.uuid.uuidString, "detail": "删除这一天"]], plan: plan, context: context)
        _ = try PlanMutationStore.apply(message: message, context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Plan>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlanDay>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
    }

}
