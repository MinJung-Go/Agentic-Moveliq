import XCTest
import SwiftData
@testable import AgenticKeepKeep

@MainActor
final class CoachLifeDataTests: XCTestCase {
    private func context() throws -> ModelContext { ModelContext(try AppModelContainer.inMemory()) }
    private func tomorrow() -> Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!
    }
    private func configured(_ context: ModelContext) throws {
        var profile = CoachLifeProfile(); profile.confirmed = true; profile.goal = "保持习惯"; profile.bufferMinutes = 15
        profile.windows = (1...7).map { .init(weekday: $0, startMinute: 18 * 60, endMinute: 22 * 60) }
        try CoachLifeStore.save(profile: profile, in: context)
    }
    func testLifePreferencesAndPluginSelectionStayInAccountContainer() throws {
        let first = try context(), second = try context(); try configured(first)
        var plugins = CoachPluginConfiguration(); plugins.enabled.insert(.calendar); plugins.calendarIDs = ["first-account-calendar"]
        try CoachLifeStore.save(plugins: plugins, in: first)
        XCTAssertTrue(try CoachLifeStore.profile(first).confirmed)
        XCTAssertFalse(try CoachLifeStore.profile(second).confirmed)
        XCTAssertFalse(try CoachLifeStore.plugins(second).enabled.contains(.calendar))
        XCTAssertTrue(try CoachLifeStore.plugins(second).calendarIDs.isEmpty)
    }
    func testBatchProposalsReusePendingOperationButNotCompletedOperation() throws {
        let context = try context(), payload = CoachActionPayload(title: "训练", reason: "明确要求")
        let a = try CoachLifeStore.action(kind: "calendar", payload: payload, in: context)
        var repeated = payload; repeated.reason = "同一操作的另一种解释"
        let b = try CoachLifeStore.action(kind: "calendar", payload: repeated, in: context)
        XCTAssertEqual(a.operationID, b.operationID)
        a.state = "succeeded"; try context.save()
        let c = try CoachLifeStore.action(kind: "calendar", payload: payload, in: context)
        XCTAssertNotEqual(a.operationID, c.operationID)
    }
    func testScheduleOutsideConfirmedWindowIsRejected() throws {
        let context = try context(); try configured(context)
        let tooEarly = CoachLifeTime.at(minute: 17 * 60, on: tomorrow())!
        XCTAssertThrowsError(try CoachScheduleGuard.validate(start: tooEarly, minutes: 30, context: context))
        let valid = CoachLifeTime.at(minute: 19 * 60, on: tomorrow())!
        XCTAssertNoThrow(try CoachScheduleGuard.validate(start: valid, minutes: 30, context: context))
    }
    func testProtectedWindowAndActiveTemporaryLimitAreEnforced() throws {
        let context = try context(); try configured(context)
        var profile = try CoachLifeStore.profile(context)
        let weekday = Calendar.current.component(.weekday, from: tomorrow())
        profile.protectedTimes = [.init(weekday: weekday, startMinute: 19 * 60, endMinute: 20 * 60, label: "晚饭")]
        try CoachLifeStore.save(profile: profile, in: context)
        XCTAssertThrowsError(try CoachScheduleGuard.validate(start: CoachLifeTime.at(minute: 19 * 60, on: tomorrow())!, minutes: 30, context: context))
        let temporary = CoachCheckIn(kind: "temporary", note: "只有20分钟", expiresAt: tomorrow().addingTimeInterval(86400))
        temporary.availableMinutes = 20; context.insert(temporary); try context.save()
        let start = CoachLifeTime.at(minute: 20 * 60 + 30, on: tomorrow())!
        XCTAssertThrowsError(try CoachScheduleGuard.validate(start: start, minutes: 30, context: context))
        XCTAssertNoThrow(try CoachScheduleGuard.validate(start: start, minutes: 20, context: context))
    }
    func testLocalTrainingOverlapIsRejectedEvenWithoutCalendarPlugin() throws {
        let context = try context(); try configured(context)
        let plan = Plan(title: "已有训练"); context.insert(plan)
        let day = PlanDay(date: tomorrow(), title: "训练", order: 0); day.plan = plan
        let start = CoachLifeTime.at(minute: 19 * 60, on: tomorrow())!
        day.scheduledStart = start; day.durationMinutes = 30; context.insert(day); try context.save()
        XCTAssertThrowsError(try CoachScheduleGuard.validate(start: start, minutes: 20, context: context))
        XCTAssertNoThrow(try CoachScheduleGuard.validate(start: start, minutes: 20, excluding: day.uuid, context: context))
        XCTAssertNoThrow(try CoachScheduleGuard.validate(start: start, minutes: 20, excludingDayIDs: [day.uuid], context: context))
    }

    func testExpiredTemporaryLimitNoLongerConstrainsFutureTraining() throws {
        let context = try context(); try configured(context)
        let temporary = CoachCheckIn(kind: "temporary", note: "旧限制", expiresAt: .now); temporary.availableMinutes = 10
        context.insert(temporary); try context.save()
        XCTAssertNoThrow(try CoachScheduleGuard.validate(start: CoachLifeTime.at(minute: 19 * 60, on: tomorrow())!, minutes: 45, context: context))
    }
    func testConcreteTimesSurviveImportAndJSONExport() throws {
        let context = try context()
        var day = PlanDayDraft(dayOffset: 1, title: "训练", exercises: [.init(name: "深蹲", setsText: "3×8")])
        day.startTime = "19:30"; day.durationMinutes = 30
        let draft = PlanDraft(title: "本周", goal: "general", weeks: 1, days: [day])
        let message = ChatMessage(role: .assistant, content: "", pendingPlanJSON: "{}")
        context.insert(message)
        let plan = try XCTUnwrap(CoachPlanImporter.accept(draft, message: message, context: context))
        XCTAssertEqual(Calendar.current.component(.hour, from: try XCTUnwrap(plan.days.first?.scheduledStart)), 19)
        XCTAssertEqual(try DataExporter.makePayload(context: context).plans.first?.days.first?.durationMinutes, 30)
    }
    func testSyncOutboxIsIdempotentAndNewScheduleResetsOnlyRequiredSteps() throws {
        let context = try context()
        var config = CoachPluginConfiguration(); config.syncTrainingCalendar = true; config.syncTrainingAlarms = true; config.writeCalendarID = "example"
        try CoachLifeStore.save(plugins: config, in: context)
        let plan = Plan(title: "安排", goal: .general, startDate: .now, weeks: 1); context.insert(plan)
        let day = PlanDay(date: tomorrow(), title: "训练", order: 0); day.plan = plan
        day.scheduledStart = CoachLifeTime.at(minute: 19 * 60, on: tomorrow()); day.durationMinutes = 30
        context.insert(day); try context.save()
        try TrainingScheduleSync.enqueue(planID: plan.uuid, context: context)
        let first = try XCTUnwrap(context.fetch(FetchDescriptor<CoachTrainingLink>()).first)
        let id = first.alarmID
        try TrainingScheduleSync.enqueue(planID: plan.uuid, context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CoachTrainingLink>()), 1); XCTAssertEqual(first.alarmID, id)
        first.calendarReceipt = "已同步"; day.scheduledStart = CoachLifeTime.at(minute: 20 * 60, on: tomorrow())
        try context.save(); try TrainingScheduleSync.enqueue(planID: plan.uuid, context: context)
        XCTAssertTrue(first.calendarReceipt.isEmpty); XCTAssertNotEqual(first.alarmID, id); XCTAssertTrue(first.retiredAlarmIDs.contains(try XCTUnwrap(id)))
        let secondID = try XCTUnwrap(first.alarmID)
        day.scheduledStart = CoachLifeTime.at(minute: 21 * 60, on: tomorrow())
        try context.save(); try TrainingScheduleSync.enqueue(planID: plan.uuid, context: context)
        XCTAssertTrue(first.retiredAlarmIDs.contains(secondID)); XCTAssertTrue(first.retiredAlarmIDs.contains(try XCTUnwrap(id)))
        config.syncTrainingAlarms = false; config.syncTrainingCalendar = false
        try CoachLifeStore.save(plugins: config, in: context); try TrainingScheduleSync.enqueue(planID: plan.uuid, context: context)
        XCTAssertNil(first.alarmID); XCTAssertTrue(first.pending); XCTAssertEqual(first.retiredAlarmIDs.count, 3)
    }
    func testPluginExecutorRejectsAStaleAccountBeforeSystemAccess() async throws {
        let context = try context()
        do {
            _ = try await CoachPluginExecutor.execute(LLMToolCall(id: "test", name: CoachPluginTools.calendar.name, argumentsJSON: "{}"), context: context, token: "not-a-session")
            XCTFail("Stale account must be rejected")
        } catch { XCTAssertTrue(error is CoachPluginError) }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CoachActionRecord>()), 0)
    }
    func testLifeRevisionIsStableButNewWorkoutInvalidatesOldProposal() throws {
        let context = try context(); try configured(context)
        let original = try CoachLifeContextBuilder.revision(context: context)
        XCTAssertEqual(original, try CoachLifeContextBuilder.revision(context: context))
        context.insert(WorkoutSession(date: .now, title: "额外训练")); try context.save()
        XCTAssertNotEqual(original, try CoachLifeContextBuilder.revision(context: context))
    }
    func testAutomationRulesAreAccountScopedRevocableAndInvalidateOldProposals() throws {
        let first = try context(), second = try context()
        XCTAssertFalse(try CoachLifeStore.automationRules(first).enabled)
        let before = try CoachLifeContextBuilder.revision(context: first)
        var rules = CoachAutomationRules(); rules.enabled = true; rules.planIDs = [UUID()]; rules.actions = [.skip]
        rules.horizonDays = 7; rules.dailyChangeLimit = 1; rules.minimumLeadMinutes = 30
        try CoachLifeStore.save(automationRules: rules, in: first)
        XCTAssertTrue(try CoachLifeStore.automationRules(first).enabled)
        XCTAssertFalse(try CoachLifeStore.automationRules(second).enabled)
        XCTAssertNotEqual(before, try CoachLifeContextBuilder.revision(context: first))
        XCTAssertFalse(try XCTUnwrap(DataExporter.makePayload(context: first).coachState).automationJSON.isEmpty)
        let activeRevision = try CoachLifeStore.automationRules(first).revision
        try CoachLifeStore.save(automationRules: CoachAutomationRules(), in: first)
        XCTAssertFalse(try CoachLifeStore.automationRules(first).enabled)
        XCTAssertNotEqual(activeRevision, try CoachLifeStore.automationRules(first).revision)
    }

    func testFeedbackAndProfileAreIncludedInLocalExport() throws {
        let context = try context(); try configured(context)
        let check = CoachCheckIn(note: "只在本机的备注"); check.difficulty = "偏难"; context.insert(check); try context.save()
        let state = try XCTUnwrap(DataExporter.makePayload(context: context).coachState)
        XCTAssertTrue(state.profileJSON.contains("goal")); XCTAssertEqual(state.checkIns.first?.note, "只在本机的备注")
    }
}
