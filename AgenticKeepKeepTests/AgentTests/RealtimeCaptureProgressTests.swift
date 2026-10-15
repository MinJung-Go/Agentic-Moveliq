import XCTest
@testable import AgenticKeepKeep

final class RealtimeCaptureProgressTests: XCTestCase {
    func testEngineStoppedTakesPrecedenceOverRecentAudio() {
        let progress = RealtimeCaptureProgress()
        progress.received(frames: 1600, at: 10)
        progress.produced(at: 10)
        XCTAssertEqual(progress.stage(engineRunning: false, at: 11), .engineStopped)
    }
    func testDistinguishesCallbackSamplesConversionAndDelivery() {
        let progress = RealtimeCaptureProgress()
        XCTAssertEqual(progress.stage(engineRunning: true, at: 10), .noCallback)
        progress.received(frames: 0, at: 10)
        XCTAssertEqual(progress.stage(engineRunning: true, at: 11), .emptyBuffer)
        progress.received(frames: 1600, at: 11)
        XCTAssertEqual(progress.stage(engineRunning: true, at: 12), .noConversion)
        progress.produced(at: 12)
        XCTAssertEqual(progress.stage(engineRunning: true, at: 13), .deliveryStopped)
    }
    func testOldActivityDoesNotHideLaterStall() {
        let progress = RealtimeCaptureProgress()
        progress.received(frames: 1600, at: 10)
        progress.produced(at: 10)
        XCTAssertEqual(progress.stage(engineRunning: true, at: 15), .noCallback)
        progress.received(frames: 0, at: 15)
        XCTAssertEqual(progress.stage(engineRunning: true, at: 15), .emptyBuffer)
        progress.received(frames: 1600, at: 15)
        XCTAssertEqual(progress.stage(engineRunning: true, at: 15), .noConversion)
    }
    func testNewConnectionDoesNotInheritOldSamples() {
        let old = RealtimeCaptureProgress()
        old.received(frames: 1600, at: 10)
        old.produced(at: 10)
        XCTAssertEqual(RealtimeCaptureProgress().stage(engineRunning: true, at: 11), .noCallback)
    }
    func testConcurrentAudioAndSnapshotAccess() {
        let progress = RealtimeCaptureProgress()
        DispatchQueue.concurrentPerform(iterations: 1000) { _ in
            progress.received(frames: 1600, at: 10)
            progress.produced(at: 10)
            _ = progress.stage(engineRunning: true, at: 11)
        }
        XCTAssertEqual(progress.stage(engineRunning: true, at: 11), .deliveryStopped)
    }
    func testRecoveryOnlyWhileInputExpectedAndEngineStopped() {
        var recovery = RealtimeEngineRecovery()
        XCTAssertFalse(recovery.shouldRestart(engineRunning: false, expectingInput: false))
        XCTAssertFalse(recovery.shouldRestart(engineRunning: true, expectingInput: true))
        XCTAssertFalse(recovery.attempted)
        XCTAssertTrue(recovery.shouldRestart(engineRunning: false, expectingInput: true))
        XCTAssertFalse(recovery.shouldRestart(engineRunning: false, expectingInput: true))
    }
    func testNewConnectionCanRecoverIndependently() {
        var recovery = RealtimeEngineRecovery()
        XCTAssertTrue(recovery.shouldRestart(engineRunning: false, expectingInput: true))
        recovery = RealtimeEngineRecovery()
        XCTAssertTrue(recovery.shouldRestart(engineRunning: false, expectingInput: true))
    }
}
