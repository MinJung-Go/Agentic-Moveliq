import XCTest
@testable import AgenticKeepKeep

final class RealtimeIdleTimerTests: XCTestCase {
    func testCallHoldsScreenAndRestoresAutoLockOnDisconnect() async {
        await MainActor.run {
            var disabled = false
            let timer = RealtimeIdleTimer(read: { disabled }, write: { disabled = $0 })
            let call = UUID()
            timer.acquire(call)
            XCTAssertTrue(disabled)
            timer.release(call)
            XCTAssertFalse(disabled)
        }
    }
    func testPreservesPreviouslyDisabledAutoLock() async {
        await MainActor.run {
            var disabled = true
            let timer = RealtimeIdleTimer(read: { disabled }, write: { disabled = $0 })
            let call = UUID()
            timer.acquire(call); timer.release(call)
            XCTAssertTrue(disabled)
        }
    }
    func testRepeatedAcquireAndReleaseDoNotLeakOrOverwriteBaseline() async {
        await MainActor.run {
            var disabled = false
            var writes = 0
            let timer = RealtimeIdleTimer(read: { disabled }, write: { disabled = $0; writes += 1 })
            let call = UUID()
            timer.acquire(call); timer.acquire(call)
            timer.release(call); timer.release(call)
            XCTAssertFalse(disabled)
            XCTAssertEqual(writes, 2)
            disabled = true
            timer.acquire(call); timer.release(call)
            XCTAssertTrue(disabled)
        }
    }
    func testOtherCallCannotReleaseActiveCallLease() async {
        await MainActor.run {
            var disabled = false
            let timer = RealtimeIdleTimer(read: { disabled }, write: { disabled = $0 })
            let first = UUID(), second = UUID()
            timer.acquire(first)
            timer.release(second)
            XCTAssertTrue(disabled)
            timer.acquire(second)
            timer.release(first)
            XCTAssertTrue(disabled)
            timer.release(second)
            XCTAssertFalse(disabled)
        }
    }
}
