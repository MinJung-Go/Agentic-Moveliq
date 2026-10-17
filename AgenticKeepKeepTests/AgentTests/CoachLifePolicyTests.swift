import XCTest
@testable import AgenticKeepKeep

final class CoachLifePolicyTests: XCTestCase {
    private var utc: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value }
    private func date(_ time: String) -> Date { ISO8601DateFormatter().date(from: "2026-10-19T\(time):00Z")! }
    private func profile() -> CoachLifeProfile {
        var value = CoachLifeProfile(); value.confirmed = true; value.bufferMinutes = 15
        value.windows = [CoachDailyWindow(weekday: 2, startMinute: 18 * 60, endMinute: 22 * 60)]
        return value
    }
    func testUnknownPreferencesNeverProduceAvailableTrainingSlots() {
        XCTAssertTrue(CoachLifeTime.freeSlots(on: date("00:00"), profile: CoachLifeProfile(), busy: [], now: date("00:00"), calendar: utc).isEmpty)
    }
    func testBusyTimeAndPreparationBuffersAreSubtracted() {
        let slots = CoachLifeTime.freeSlots(on: date("00:00"), profile: profile(), busy: [.init(start: date("19:00"), end: date("20:00"))], now: date("00:00"), calendar: utc)
        XCTAssertEqual(slots, [.init(start: date("18:15"), end: date("18:45")), .init(start: date("20:15"), end: date("21:45"))])
    }
    func testOverlappingAndDuplicateEventsDoNotCreateFalseGaps() {
        let busy = [CoachTimeSlot(start: date("18:30"), end: date("20:00")), .init(start: date("19:00"), end: date("20:30")), .init(start: date("19:00"), end: date("20:30"))]
        let slots = CoachLifeTime.freeSlots(on: date("00:00"), profile: profile(), busy: busy, now: date("00:00"), calendar: utc)
        XCTAssertEqual(slots, [.init(start: date("20:45"), end: date("21:45"))])
    }
    func testProtectedMealTimeCannotBecomeTrainingTime() {
        var profile = profile(); profile.bufferMinutes = 0
        profile.protectedTimes = [.init(weekday: 2, startMinute: 19 * 60, endMinute: 20 * 60, label: "晚饭与休息")]
        let slots = CoachLifeTime.freeSlots(on: date("00:00"), profile: profile, busy: [], now: date("00:00"), calendar: utc)
        XCTAssertEqual(slots, [.init(start: date("18:00"), end: date("19:00")), .init(start: date("20:00"), end: date("22:00"))])
    }
    func testAllDayEventLeavesNoTrainingAvailability() {
        let slots = CoachLifeTime.freeSlots(on: date("00:00"), profile: profile(), busy: [.init(start: date("00:00"), end: date("23:59"))], now: date("00:00"), calendar: utc)
        XCTAssertTrue(slots.isEmpty)
    }
    func testPastWindowsAreNotOfferedAndNowClampsCurrentWindow() {
        XCTAssertTrue(CoachLifeTime.freeSlots(on: date("00:00"), profile: profile(), busy: [], now: date("23:00"), calendar: utc).isEmpty)
        XCTAssertEqual(CoachLifeTime.freeSlots(on: date("00:00"), profile: profile(), busy: [], now: date("20:30"), calendar: utc).first?.start, date("20:30"))
    }
    func testMalformedAndDuplicateWeekdayWindowsAreRejected() {
        var profile = profile(); profile.windows[0].endMinute = 0; XCTAssertFalse(profile.isValid)
        profile = self.profile(); profile.windows.append(profile.windows[0]); XCTAssertFalse(profile.isValid)
        XCTAssertNil(CoachLifeTime.minute("24:00")); XCTAssertNil(CoachLifeTime.minute("9:30")); XCTAssertNil(CoachLifeTime.minute("19:99"))
    }
    func testSystemWriteTimesRequireAnExplicitTimezone() {
        XCTAssertNil(CoachLifeTime.date("2026-10-19T19:00:00"))
        XCTAssertEqual(CoachLifeTime.date("2026-10-19T19:00:00+08:00"), CoachLifeTime.date("2026-10-19T11:00:00Z"))
    }
    func testNonexistentDSTClockTimeIsRejected() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let day = ISO8601DateFormatter().date(from: "2026-03-08T12:00:00Z")!
        XCTAssertNil(CoachLifeTime.at(minute: 2 * 60 + 30, on: day, calendar: calendar))
    }
    func testOnlyAnExplicitTemporaryTimeLimitIsExtracted() {
        XCTAssertEqual(CoachLifeTime.statedMinutes("今天只有20分钟，想练一下"), 20)
        XCTAssertEqual(CoachLifeTime.statedMinutes("这周最多 45 分钟"), 45)
        XCTAssertNil(CoachLifeTime.statedMinutes("通勤20分钟")); XCTAssertNil(CoachLifeTime.statedMinutes("最多999分钟"))
    }
}
