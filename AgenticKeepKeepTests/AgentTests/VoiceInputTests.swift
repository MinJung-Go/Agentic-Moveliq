import XCTest
@testable import AgenticKeepKeep

@MainActor
private final class DictationStub: VoiceRecognizing {
    var onUpdate: ((String, Bool) -> Void)?
    var onFailure: ((String) -> Void)?
    var stops = 0
    var starts = 0
    func start() async { starts += 1 }
    func stop() { stops += 1 }
}

@MainActor
final class VoiceInputTests: XCTestCase {
    func testPartialResultsReplaceOnlyDictatedSuffix() async {
        let driver = DictationStub()
        let value = VoiceInput(recognizer: driver)
        value.begin(draft: "原草稿"); driver.onUpdate?("今天", false); driver.onUpdate?("今天想休息", false)
        XCTAssertEqual(value.text, "原草稿\n今天想休息")
        XCTAssertTrue(value.active)
        value.finish(); XCTAssertEqual(value.text, "原草稿\n今天想休息")
    }
    func testCancelRestoresDraftAndRejectsLateCallbacks() async {
        let driver = DictationStub(), value: VoiceInput
        value = VoiceInput(recognizer: driver); value.begin(draft: "原草稿")
        let late = driver.onUpdate
        driver.onUpdate?("新增", false); value.finish(cancel: true); late?("过期结果", true)
        XCTAssertEqual(value.text, "原草稿"); XCTAssertFalse(value.active)
        value.begin(draft: "新草稿"); late?("上一轮结果", true)
        XCTAssertEqual(value.text, "新草稿"); XCTAssertTrue(value.active); value.finish()
    }
    func testFinalStopsWithoutSendingOrRestarting() async {
        let driver = DictationStub()
        let input = VoiceInput(recognizer: driver); input.begin(draft: "")
        driver.onUpdate?("待确认文字", true)
        XCTAssertEqual(input.text, "待确认文字"); XCTAssertFalse(input.active)
        await Task.yield(); XCTAssertFalse(input.active); XCTAssertEqual(driver.stops, 1)
    }
    func testCancelBeforeStartDoesNotRequestRecording() async {
        let driver = DictationStub(), value: VoiceInput
        value = VoiceInput(recognizer: driver); value.begin(draft: "草稿"); value.finish(cancel: true)
        await Task.yield()
        XCTAssertEqual(driver.starts, 0); XCTAssertFalse(value.active)
    }
    /// 录音中直接发送：取走已识别的文字并结束收音，不需要先点一次「停」
    func testSendTakesDictatedTextAndStopsWithoutNotice() async {
        let driver = DictationStub()
        let value = VoiceInput(recognizer: driver)
        value.begin(draft: "原草稿"); driver.onUpdate?("今天想休息", false)
        XCTAssertEqual(value.finishForSend(), "原草稿\n今天想休息")
        XCTAssertFalse(value.active)
        XCTAssertEqual(driver.stops, 1)
        XCTAssertEqual(value.notice, "")
    }
    func testSendRejectsCallbacksFromTheStoppedRecording() async {
        let driver = DictationStub(), value: VoiceInput
        value = VoiceInput(recognizer: driver)
        value.begin(draft: "草稿")
        let late = driver.onUpdate
        XCTAssertEqual(value.finishForSend(), "草稿")
        late?("过期结果", false)
        XCTAssertEqual(value.text, "草稿")
        XCTAssertFalse(value.active)
    }
    func testFailureRetainsPartialTextAndStops() async {
        let driver = DictationStub(), value: VoiceInput
        value = VoiceInput(recognizer: driver); value.begin(draft: "草稿")
        driver.onUpdate?("已识别", false); driver.onFailure?("识别中断")
        XCTAssertEqual(value.text, "草稿\n已识别"); XCTAssertFalse(value.active)
        XCTAssertEqual(value.notice, "识别中断")
    }
}
