import XCTest
@testable import AgenticKeepKeep

final class RealtimeInputHealthTests: XCTestCase {
    func testConnectionWithoutMicrophoneDataTimesOut() {
        var health = RealtimeInputHealth(); health.reset(at: 100)
        XCTAssertNil(health.failure(at: 104, shouldSend: true))
        XCTAssertEqual(health.failure(at: 105, shouldSend: true), .captureStopped)
    }
    func testMicrophoneWithoutSuccessfulUploadIsDistinguished() {
        var health = RealtimeInputHealth(); health.reset(at: 0)
        health.capture(at: 7)
        XCTAssertEqual(health.failure(at: 8, shouldSend: true), .uploadStopped)
    }
    func testContinuousSilenceFramesKeepCallHealthy() {
        var health = RealtimeInputHealth(); health.reset(at: 0)
        for tick in 1...60 {
            health.capture(at: Double(tick)); health.upload(at: Double(tick))
            XCTAssertNil(health.failure(at: Double(tick), shouldSend: true))
        }
        XCTAssertEqual(health.captured, 60); XCTAssertEqual(health.sent, 60)
    }
    func testMuteAndModeSwitchDoNotCauseTimeoutAndResumeHasGracePeriod() {
        var health = RealtimeInputHealth(); health.reset(at: 0)
        XCTAssertNil(health.failure(at: 30, shouldSend: false))
        XCTAssertNil(health.failure(at: 100, shouldSend: false))
        XCTAssertNil(health.failure(at: 101, shouldSend: true))
        XCTAssertNil(health.failure(at: 105, shouldSend: true))
        XCTAssertEqual(health.failure(at: 106, shouldSend: true), .captureStopped)
    }
    func testStalledCaptureAfterSuccessfulStartAndNewCallReset() {
        var health = RealtimeInputHealth(); health.reset(at: 0)
        health.capture(at: 2); health.upload(at: 2)
        XCTAssertEqual(health.failure(at: 7, shouldSend: true), .captureStopped)
        health.reset(at: 100)
        XCTAssertEqual(health.captured, 0); XCTAssertEqual(health.sent, 0)
        XCTAssertNil(health.failure(at: 101, shouldSend: true))
    }
}
