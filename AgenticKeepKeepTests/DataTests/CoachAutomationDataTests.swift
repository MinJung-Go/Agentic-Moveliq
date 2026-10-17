import XCTest
import SwiftData
@testable import AgenticKeepKeep

@MainActor
final class CoachAutomationDataTests: XCTestCase {
    private func fixture() throws -> (ModelContext, Plan, PlanDay, CoachAutomationRules) {
        let context = ModelContext(try AppModelContainer.inMemory())
        let plan = Plan(title: "训练安排"); context.insert(plan)
        let date = Calendar.current.date(byAdding: .day, value: 2, to: Calendar.current.startOfDay(for: .now))!
        let day = PlanDay(date: date, title: "力量", order: 0); day.plan = plan
        day.scheduledStart = CoachLifeTime.at(minute: 19 * 60, on: date); day.durationMinutes = 45
        context.insert(day)
        let exercise = PlanExercise(name: "深蹲", setsText: "3×8", targetWeightKg: 60); exercise.day = day; context.insert(exercise)
        var rules = CoachAutomationRules(); rules.enabled = true; rules.planIDs = [plan.uuid]; rules.actions = [.move, .shorten]
        rules.horizonDays = 7; rules.dailyChangeLimit = 3; rules.minimumLeadMinutes = 30
        rules.maximumStartShiftMinutes = 60; rules.maximumDateShiftDays = 0
        rules.minimumSessionMinutes = 20; rules.maximumShorteningPercent = 50; rules.syncCalendar = true
        try CoachLifeStore.save(automationRules: rules, in: context)
        rules = try CoachLifeStore.automationRules(context)
        try context.save(); return (context, plan, day, rules)
    }
    private func draft(_ day: PlanDay, plan: Plan, time: String = "19:30") -> PlanAdjustmentDraft {
        var change = PlanAdjustmentChange(dayOffset: 2, action: "reschedule", detail: "配合日常")
        change.dayID = day.uuid.uuidString; change.startTime = time
        return .init(summary: "调整训练时间", changes: [change], planID: plan.uuid.uuidString, revision: PlanMutationStore.revision(plan))
    }
    private func queued(_ context: ModelContext, plan: Plan, day: PlanDay, rules: CoachAutomationRules) throws -> (CoachAutomationRecord, CoachTrainingLink) {
        var config = CoachPluginConfiguration(); config.syncTrainingCalendar = true; config.writeCalendarID = "selected"
        try CoachLifeStore.save(plugins: config, in: context)
        let record = CoachAutomationRecord(ruleID: rules.revision, planID: plan.uuid, messageID: UUID())
        record.afterRevision = PlanMutationStore.revision(plan); context.insert(record); try context.save()
        try TrainingScheduleSync.enqueue(planID: plan.uuid, context: context, dayIDs: [day.uuid], automation: record)
        return (record, try XCTUnwrap(context.fetch(FetchDescriptor<CoachTrainingLink>()).first))
    }
    func testRepeatedMovesKeepOriginalAnchorAndCannotResetCumulativeLimit() throws {
        let (context, plan, day, rules) = try fixture()
        let original = CoachAutomationCoordinator.snapshot(day, planID: plan.uuid)
        let record = CoachAutomationRecord(ruleID: rules.revision, planID: plan.uuid, messageID: UUID())
        record.anchorJSON = try CoachLifeStore.encode([original]); context.insert(record)
        day.scheduledStart = day.scheduledStart!.addingTimeInterval(30 * 60); try context.save()
        let changes = try CoachAutomationCoordinator.changes(draft(day, plan: plan, time: "20:01"), plan: plan, rules: rules, history: [record])
        XCTAssertEqual(changes.first?.anchor, original)
        var evidence = CoachAutomationEvidence(verifiedAt: .now); evidence.accountMatches = true; evidence.versionsMatch = true
        evidence.constraintsVerified = true; evidence.needsUserClarification = false
        XCTAssertEqual(CoachAutomationPolicy.evaluate(changes, rules: rules, evidence: evidence), .needsConfirmation(.magnitude))
    }
    func testUnknownDayAndReplacementCannotEnterAutomaticSnapshot() throws {
        let (_, plan, day, rules) = try fixture()
        var value = draft(day, plan: plan); value.changes[0].dayID = UUID().uuidString
        XCTAssertThrowsError(try CoachAutomationCoordinator.changes(value, plan: plan, rules: rules, history: []))
        value = draft(day, plan: plan); value.changes[0].title = "模型偷偷改标题"
        XCTAssertThrowsError(try CoachAutomationCoordinator.changes(value, plan: plan, rules: rules, history: []))
    }
    func testPlanAndAuditCommitTogetherAndRepeatedApplyDoesNotCreateAnotherAudit() throws {
        let (context, plan, day, rules) = try fixture()
        let json = try JSONSerialization.data(withJSONObject: ["planID": plan.uuid.uuidString, "revision": PlanMutationStore.revision(plan),
            "summary": "调整", "changes": [["action": "reschedule", "dayID": day.uuid.uuidString, "startTime": "19:30", "detail": "配合日常"]]])
        let message = ChatMessage(role: .assistant, content: "", pendingAdjustmentJSON: String(decoding: json, as: UTF8.self))
        context.insert(message); try context.save()
        let audit = CoachAutomationRecord(ruleID: rules.revision, planID: plan.uuid, messageID: message.uuid)
        XCTAssertNotNil(try PlanMutationStore.apply(message: message, context: context, audit: audit))
        XCTAssertEqual(audit.afterRevision, PlanMutationStore.revision(plan))
        XCTAssertEqual(Calendar.current.component(.minute, from: try XCTUnwrap(day.scheduledStart)), 30)
        XCTAssertNil(try PlanMutationStore.apply(message: message, context: context, audit: audit))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CoachAutomationRecord>()), 1)
    }
    func testRevokingOrRevisingRulesStopsPreviouslyQueuedSystemWrites() throws {
        let (context, plan, day, rules) = try fixture()
        let (_, link) = try queued(context, plan: plan, day: day, rules: rules)
        XCTAssertNoThrow(try TrainingScheduleSync.validateAutomationAuthority(link, context: context))
        var updated = rules; updated.dailyChangeLimit = 4
        try CoachLifeStore.save(automationRules: updated, in: context)
        XCTAssertThrowsError(try TrainingScheduleSync.validateAutomationAuthority(link, context: context))
        updated.enabled = false; try CoachLifeStore.save(automationRules: updated, in: context)
        XCTAssertThrowsError(try TrainingScheduleSync.validateAutomationAuthority(link, context: context))
        XCTAssertTrue(link.pending); XCTAssertTrue(link.calendarReceipt.isEmpty)
    }
    func testLaterPlanEditInvalidatesQueuedAuthorityWithoutChangingSavedPlan() throws {
        let (context, plan, day, rules) = try fixture()
        let (_, link) = try queued(context, plan: plan, day: day, rules: rules)
        day.title = "用户后改的训练"; try context.save()
        XCTAssertThrowsError(try TrainingScheduleSync.validateAutomationAuthority(link, context: context))
        XCTAssertEqual(day.title, "用户后改的训练")
    }
    func testAutomaticQueueIsLimitedToAffectedDaysAndHistoryExports() throws {
        let (context, plan, day, rules) = try fixture()
        let other = PlanDay(date: day.date.addingTimeInterval(86400), title: "另一天", order: 1); other.plan = plan
        other.scheduledStart = day.scheduledStart?.addingTimeInterval(86400); other.durationMinutes = 30
        context.insert(other); try context.save()
        let (record, _) = try queued(context, plan: plan, day: day, rules: rules)
        record.beforeJSON = try CoachLifeStore.encode([CoachAutomationCoordinator.snapshot(day, planID: plan.uuid)])
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<CoachTrainingLink>()).map(\.dayID), [day.uuid])
        XCTAssertEqual(try DataExporter.makePayload(context: context).coachState?.automationHistory.first?.id, record.uuid)
    }
}
