import XCTest
@testable import AgenticKeepKeep

final class CoachAutomationPolicyTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-19T08:00:00Z")!
    private let planID = UUID()
    private var utc: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value }
    private func rules() -> CoachAutomationRules {
        var value = CoachAutomationRules(); value.enabled = true; value.planIDs = [planID]
        value.actions = [.move, .shorten, .reduceWeight, .skip]; value.horizonDays = 7
        value.dailyChangeLimit = 2; value.minimumLeadMinutes = 30
        value.maximumStartShiftMinutes = 90; value.maximumDateShiftDays = 0
        value.minimumSessionMinutes = 20; value.maximumShorteningPercent = 50
        value.maximumWeightReductionPercent = 20
        return value
    }
    private func evidence() -> CoachAutomationEvidence {
        var value = CoachAutomationEvidence(verifiedAt: now)
        value.accountMatches = true; value.versionsMatch = true; value.constraintsVerified = true; value.needsUserClarification = false
        return value
    }
    private func change() -> CoachAutomationChange {
        let day = CoachAutomationDay(id: UUID(), planID: planID, title: "力量", start: now.addingTimeInterval(3600), minutes: 40,
            exercises: [.init(id: UUID(), name: "深蹲", setsText: "3×8", weight: 100)])
        var next = day; next.start = day.start!.addingTimeInterval(30 * 60)
        return .init(anchor: day, current: day, proposed: next)
    }
    private func decide(_ changes: [CoachAutomationChange], _ rules: CoachAutomationRules? = nil,
                        _ evidence: CoachAutomationEvidence? = nil) -> CoachAutomationDecision {
        CoachAutomationPolicy.evaluate(changes, rules: rules ?? self.rules(), evidence: evidence ?? self.evidence(), now: now, calendar: utc)
    }
    func testMissingUserConfigurationStaysManual() {
        XCTAssertEqual(decide([change()], CoachAutomationRules()), .needsConfirmation(.disabled))
    }
    func testEnabledButIncompleteRulesDoNotInheritExampleValues() {
        var value = CoachAutomationRules(); value.enabled = true
        XCTAssertEqual(decide([change()], value), .needsConfirmation(.incompleteRules))
    }
    func testExactAuthorizedMoveBoundaryIsAllowedAndOneMoreMinuteIsNot() {
        var item = change(); item.proposed.start = item.anchor.start!.addingTimeInterval(90 * 60)
        XCTAssertEqual(decide([item]), .automatic)
        item.proposed.start = item.anchor.start!.addingTimeInterval(91 * 60)
        XCTAssertEqual(decide([item]), .needsConfirmation(.magnitude))
    }
    func testCrossingMidnightRequiresSeparateDayRange() {
        var item = change(), settings = rules()
        item.anchor.start = utc.startOfDay(for: now).addingTimeInterval(23 * 3600 + 30 * 60)
        item.current = item.anchor; item.proposed = item.anchor; item.proposed.start = item.anchor.start!.addingTimeInterval(60 * 60)
        XCTAssertEqual(decide([item], settings), .needsConfirmation(.magnitude))
        settings.maximumDateShiftDays = 1
        XCTAssertEqual(decide([item], settings), .automatic)
    }
    func testRepeatedSmallMovesCannotBypassOriginalAnchor() {
        var item = change(); item.current.start = item.anchor.start!.addingTimeInterval(60 * 60)
        item.proposed.start = item.current.start!.addingTimeInterval(60 * 60)
        XCTAssertEqual(decide([item]), .needsConfirmation(.magnitude))
    }
    func testShorteningMustRespectBothDurationFloorAndCumulativePercent() {
        var item = change(); item.proposed = item.current; item.proposed.minutes = 20
        XCTAssertEqual(decide([item]), .automatic)
        item.proposed.minutes = 19
        XCTAssertEqual(decide([item]), .needsConfirmation(.magnitude))
        item.current.minutes = 25; item.proposed.minutes = 20
        var settings = rules(); settings.maximumShorteningPercent = 40
        XCTAssertEqual(decide([item], settings), .needsConfirmation(.magnitude))
    }
    func testLongerTrainingHigherWeightsAndExerciseReplacementNeedConfirmation() {
        var item = change(); item.proposed.minutes = 45
        XCTAssertEqual(decide([item]), .needsConfirmation(.magnitude))
        item = change(); item.proposed.exercises[0].weight = 105
        XCTAssertEqual(decide([item]), .needsConfirmation(.magnitude))
        item = change(); item.proposed.exercises[0].name = "卧推"
        XCTAssertEqual(decide([item]), .needsConfirmation(.unsupported))
    }
    func testRepeatedWeightReductionsRespectOriginalWeight() {
        var item = change(); item.proposed.exercises[0].weight = 85
        XCTAssertEqual(decide([item]), .automatic)
        item.current.exercises[0].weight = 85; item.proposed.exercises[0].weight = 72.5
        XCTAssertEqual(decide([item]), .needsConfirmation(.magnitude))
    }
    func testOneOutOfScopeDayMakesWholeBatchManual() {
        let first = change(); var second = change(); second.current.planID = UUID()
        second.anchor.planID = second.current.planID; second.proposed.planID = second.current.planID
        XCTAssertEqual(decide([first, second]), .needsConfirmation(.planScope))
    }
    func testDailyBudgetCountsActualDaysNotJustOneBatch() {
        var checked = evidence(); checked.changesToday = 1
        XCTAssertEqual(decide([change(), change()], nil, checked), .needsConfirmation(.dailyLimit))
        XCTAssertEqual(decide([change()], nil, checked), .automatic)
    }
    func testSystemSyncIsSeparatelyAuthorized() {
        var checked = evidence(), settings = rules(); checked.writesCalendar = true
        XCTAssertEqual(decide([change()], settings, checked), .needsConfirmation(.systemScope))
        settings.syncCalendar = true; checked.writesAlarms = true
        XCTAssertEqual(decide([change()], settings, checked), .needsConfirmation(.systemScope))
        settings.syncAlarms = true
        XCTAssertEqual(decide([change()], settings, checked), .automatic)
    }
    func testStaleAccountVersionConstraintsAndEvidenceCannotAuthorize() {
        for index in 0...3 {
            var checked = evidence()
            if index == 0 { checked.accountMatches = false }
            if index == 1 { checked.versionsMatch = false }
            if index == 2 { checked.constraintsVerified = false }
            if index == 3 { checked.verifiedAt = now.addingTimeInterval(-61) }
            XCTAssertEqual(decide([change()], nil, checked), .needsConfirmation(.unverified))
        }
    }
    func testPainClarificationOrOngoingWorkoutRequiresUser() {
        let item = change(); var checked = evidence(); checked.needsUserClarification = true
        XCTAssertEqual(decide([item], nil, checked), .needsConfirmation(.clarification))
        checked.needsUserClarification = false; checked.runningDayIDs = [item.current.id]
        XCTAssertEqual(decide([item], nil, checked), .needsConfirmation(.running))
    }
    func testExpiredRulesAndNearStartingWorkoutDoNotAutoExecute() {
        var settings = rules(); settings.validUntil = now
        XCTAssertEqual(decide([change()], settings), .needsConfirmation(.expired))
        settings = rules(); settings.validUntil = now.addingTimeInterval(70 * 60)
        XCTAssertEqual(decide([change()], settings), .needsConfirmation(.expired))
        var item = change(); item.current.start = now.addingTimeInterval(10 * 60)
        XCTAssertEqual(decide([item]), .needsConfirmation(.timing))
    }
    func testCompletedAndUntimedDaysCannotBeAutomatic() {
        var item = change(); item.current.status = "done"
        XCTAssertEqual(decide([item]), .needsConfirmation(.unsupported))
        item = change(); item.current.start = nil
        XCTAssertEqual(decide([item]), .needsConfirmation(.unknownTime))
    }
    func testDuplicateDaysAndNoopAreRejectedButAuthorizedRestIsAllowed() {
        var item = change()
        XCTAssertEqual(decide([item, item]), .needsConfirmation(.identity))
        item.proposed = item.current
        XCTAssertEqual(decide([item]), .needsConfirmation(.unsupported))
        item.proposed.note = "只有说明变化，未改变安排"
        XCTAssertEqual(decide([item]), .needsConfirmation(.unsupported))
        item.proposed.status = "skipped"
        XCTAssertEqual(decide([item]), .automatic)
    }
}
