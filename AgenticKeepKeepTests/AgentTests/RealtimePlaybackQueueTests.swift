import XCTest
@testable import AgenticKeepKeep

final class RealtimePlaybackQueueTests: XCTestCase {
    func testShortAudioIsAdmittedWhole() {
        var queue = RealtimePlaybackQueue()
        XCTAssertTrue(queue.admit(frames: 0).isEmpty)
        XCTAssertEqual(queue.admit(frames: 960), [960])
        XCTAssertEqual(queue.queuedFrames, 960)
        XCTAssertEqual(queue.droppedFrames, 0)
    }
    func testLongAudioIsSplitIntoOneSecondChunks() {
        var queue = RealtimePlaybackQueue()
        XCTAssertEqual(queue.admit(frames: 60_000), [24_000, 24_000, 12_000])
        XCTAssertEqual(queue.queuedFrames, 60_000)
        XCTAssertEqual(queue.droppedFrames, 0)
    }
    /// 长回复排不过来时丢后面的块，而不是让整通电话失败
    func testBacklogBeyondCapDropsNewAudioInsteadOfFailing() {
        var queue = RealtimePlaybackQueue()
        let cap = RealtimePlaybackQueue.maxQueuedFrames
        XCTAssertEqual(queue.admit(frames: cap).reduce(0, +), cap)
        XCTAssertTrue(queue.admit(frames: 24_000).isEmpty)
        XCTAssertEqual(queue.queuedFrames, cap)
        XCTAssertEqual(queue.droppedFrames, 24_000)
    }
    /// 积压没满时前面的块照常返回，只有放不下的尾部被丢
    func testPartialOverflowKeepsTheBlocksThatFit() {
        var queue = RealtimePlaybackQueue()
        let admitted = queue.admit(frames: RealtimePlaybackQueue.maxQueuedFrames - 1_000)
        XCTAssertEqual(admitted.count, 20)
        XCTAssertEqual(admitted.reduce(0, +), 479_000)
        XCTAssertEqual(admitted.last, 23_000)
        XCTAssertEqual(queue.droppedFrames, 0)
        // 只剩 1000 帧空位，后面按整秒切出来的块都放不下
        XCTAssertTrue(queue.admit(frames: 48_000).isEmpty)
        XCTAssertEqual(queue.droppedFrames, 48_000)
    }
    func testPlayedFramesFreeUpRoomAgain() {
        var queue = RealtimePlaybackQueue()
        _ = queue.admit(frames: RealtimePlaybackQueue.maxQueuedFrames)
        queue.played(frames: 24_000)
        XCTAssertEqual(queue.admit(frames: 24_000), [24_000])
        XCTAssertEqual(queue.droppedFrames, 0)
    }
    /// 播放回调在打断后晚到也不能把积压算成负数
    func testLatePlaybackCallbackCannotGoNegative() {
        var queue = RealtimePlaybackQueue()
        _ = queue.admit(frames: 960)
        queue.played(frames: 960)
        queue.played(frames: 960)
        XCTAssertEqual(queue.queuedFrames, 0)
    }
    func testResetClearsBacklogAndDropCount() {
        var queue = RealtimePlaybackQueue()
        _ = queue.admit(frames: RealtimePlaybackQueue.maxQueuedFrames + 24_000)
        queue.reset()
        XCTAssertEqual(queue.queuedFrames, 0)
        XCTAssertEqual(queue.droppedFrames, 0)
    }
}
