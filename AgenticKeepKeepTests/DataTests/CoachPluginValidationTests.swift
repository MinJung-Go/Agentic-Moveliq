import XCTest
@testable import AgenticKeepKeep

@MainActor
final class CoachPluginValidationTests: XCTestCase {
    private func snapshot() -> CalendarEventSnapshot {
        .init(token: "actual-token", identifier: "event", calendarID: "calendar", calendarTitle: "日历", title: "原日程", start: .now, end: Date().addingTimeInterval(3600), allDay: false, recurring: true, version: "version")
    }
    func testCalendarEditRequiresQueriedIdentityAndActualChange() {
        let service = CalendarPluginService.shared
        XCTAssertThrowsError(try service.validate(.init(action: "update", title: "新标题"), target: nil))
        XCTAssertThrowsError(try service.validate(.init(action: "update"), target: snapshot()))
        XCTAssertNoThrow(try service.validate(.init(action: "update", title: "新标题"), target: snapshot()))
    }
    func testCalendarRejectsAmbiguousTimesAndUnboundedRecurrence() {
        let service = CalendarPluginService.shared
        XCTAssertThrowsError(try service.validate(.init(action: "create", title: "训练", start: "2027-01-10T19:00:00", end: "2027-01-10T20:00:00"), target: nil))
        XCTAssertThrowsError(try service.validate(.init(action: "create", title: "训练", start: "2027-01-10T19:00:00+08:00", end: "2027-01-10T20:00:00+08:00", recurrence: "weekly"), target: nil))
        XCTAssertThrowsError(try service.validate(.init(action: "delete", allDay: true), target: snapshot()))
    }
    func testAlarmRejectsContradictorySchedulesAndInvalidWeekdays() {
        let future = CoachLifeTime.iso(Date().addingTimeInterval(3600))
        XCTAssertThrowsError(try AlarmPluginService.validate(.init(action: "create", title: "训练", date: future, countdownMinutes: 10)))
        XCTAssertThrowsError(try AlarmPluginService.validate(.init(action: "create", title: "训练", date: future, time: "19:00")))
        XCTAssertThrowsError(try AlarmPluginService.validate(.init(action: "create", title: "训练", time: "19:00", weekdays: [0, 8])))
        XCTAssertThrowsError(try AlarmPluginService.validate(.init(action: "create", title: "训练", time: "19:00", weekdays: [2, 2])))
    }
    func testAlarmUpdateNeedsIdentityAndValidCreateDoesNotNeedSystemPermission() {
        XCTAssertThrowsError(try AlarmPluginService.validate(.init(action: "update", title: "训练", countdownMinutes: 10)))
        XCTAssertNoThrow(try AlarmPluginService.validate(.init(action: "create", title: "训练", time: "19:00", weekdays: [2, 4])))
        XCTAssertNoThrow(try AlarmPluginService.validate(.init(action: "create", title: "训练", countdownMinutes: 10)))
    }
    func testUnavailablePluginsAreAbsentFromModelTools() {
        let none = CoachPluginTools.definitions(enabled: [], calendarReady: true, alarmReady: true, musicReady: true).map(\.name)
        XCTAssertEqual(none, [CoachPluginTools.life.name])
        let locked = CoachPluginTools.definitions(enabled: Set(CoachPlugin.allCases), calendarReady: false, alarmReady: false, musicReady: false).map(\.name)
        XCTAssertFalse(locked.contains(CoachPluginTools.calendarChange.name))
        XCTAssertFalse(locked.contains(CoachPluginTools.alarmChange.name))
        XCTAssertFalse(locked.contains(CoachPluginTools.musicPlay.name))
        XCTAssertTrue(locked.contains(CoachPluginTools.places.name))
    }
}
