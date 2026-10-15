import XCTest
@testable import AgenticKeepKeep

@MainActor
private final class VoiceRecognitionStub: VoiceRecognizing {
    var onUpdate: ((String, Bool) -> Void)?
    var onFailure: ((String) -> Void)?
    var starts = 0
    var stops = 0
    func start() async { starts += 1 }
    func stop() { stops += 1 }
}

@MainActor
private final class VoiceSpeakerStub: VoiceSpeaking {
    var completion: (() -> Void)?
    var spoken = ""
    func speak(_ text: String, onFinish: @escaping () -> Void) throws {
        spoken = text
        completion = onFinish
    }
    // Retain completion intentionally to simulate a delayed callback after cancellation.
    func stop() {}
}

@MainActor
final class VoiceConversationTests: XCTestCase {
    func testConsentDoesNotStartRecording() async {
        let recognizer = VoiceRecognitionStub()
        let voice = VoiceConversation(recognition: recognizer, speaker: VoiceSpeakerStub())
        voice.open()
        XCTAssertEqual(voice.phase, .consent)
        XCTAssertEqual(recognizer.starts, 0)
        voice.end()
    }

    func testFinalSubmitsOnlyOnceAndPreservesText() async {
        let recognizer = VoiceRecognitionStub()
        let voice = VoiceConversation(recognition: recognizer, speaker: VoiceSpeakerStub())
        var submissions = [String]()
        voice.onSubmit = { text, _ in submissions.append(text) }
        voice.open(); voice.begin()
        recognizer.onUpdate?("  今天想休息  ", true)
        recognizer.onUpdate?("过期的结果", true)
        XCTAssertEqual(submissions, ["今天想休息"])
        XCTAssertEqual(voice.phase, .thinking)
        voice.end()
    }

    func testEmptyUtteranceDoesNotSend() async {
        let recognizer = VoiceRecognitionStub()
        let voice = VoiceConversation(recognition: recognizer, speaker: VoiceSpeakerStub())
        voice.onSubmit = { _, _ in XCTFail("Empty message submitted") }
        voice.open(); voice.begin()
        recognizer.onUpdate?(" \n", true)
        XCTAssertEqual(voice.phase, .failed)
        voice.end()
    }

    func testEndRejectsLateRecognitionAndReply() async throws {
        let recognizer = VoiceRecognitionStub()
        let voice = VoiceConversation(recognition: recognizer, speaker: VoiceSpeakerStub())
        voice.open(); voice.begin()
        recognizer.onUpdate?("安排训练", true)
        let id = try XCTUnwrap(voice.turn)
        voice.end()
        recognizer.onUpdate?("迟到结果", true)
        voice.complete(id: id, text: "迟到回复", needsReview: true, error: nil)
        XCTAssertEqual(voice.phase, .ended)
        XCTAssertEqual(voice.reply, "")
    }

    func testInterruptedReplyCannotResumeSpeechAndMuteIsPreserved() async throws {
        let recognizer = VoiceRecognitionStub()
        let voice = VoiceConversation(recognition: recognizer, speaker: VoiceSpeakerStub())
        voice.open(); voice.begin()
        recognizer.onUpdate?("安排训练", true)
        let id = try XCTUnwrap(voice.turn)
        voice.toggleMute()
        voice.interrupt()
        for _ in 0..<20 { await Task.yield() }
        voice.complete(id: id, text: "旧回复", needsReview: true, error: nil)
        XCTAssertEqual(voice.phase, .muted)
        XCTAssertTrue(voice.isMuted)
        voice.end()
    }

    func testReviewAndFailureCannotResumeViaMute() async throws {
        let recognizer = VoiceRecognitionStub()
        let voice = VoiceConversation(recognition: recognizer, speaker: VoiceSpeakerStub())
        voice.open(); voice.begin()
        recognizer.onUpdate?("安排训练", true)
        voice.complete(id: try XCTUnwrap(voice.turn), text: "课程建议", needsReview: true, error: nil)
        voice.toggleMute()
        XCTAssertEqual(voice.phase, .review)
        voice.begin()
        recognizer.onFailure?("无权限")
        voice.toggleMute()
        XCTAssertEqual(voice.phase, .failed)
        voice.end()
    }

    func testSystemPauseRequiresExplicitResume() async {
        let recognizer = VoiceRecognitionStub()
        let voice = VoiceConversation(recognition: recognizer, speaker: VoiceSpeakerStub())
        voice.open(); voice.begin(); voice.pause()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(voice.phase, .paused)
        XCTAssertEqual(recognizer.starts, 0)
        voice.end()
    }

    func testSpokenReplyRemovesCodeAndLinkTargets() async {
        XCTAssertEqual(VoiceReplyText.spoken("## 建议\n**休息**，看[说明](https://example.com)。\n```json\n{\"tool\":true}\n```"), "建议\n休息，看说明。")
    }
    func testReplyFinishingAutomaticallyResumesListening() async throws {
        let recognizer = VoiceRecognitionStub()
        let speaker = VoiceSpeakerStub()
        let voice = VoiceConversation(recognition: recognizer, speaker: speaker)
        voice.open(); voice.begin()
        recognizer.onUpdate?("想休息", true)
        voice.complete(id: try XCTUnwrap(voice.turn), text: "**可以休息**", needsReview: false, error: nil)
        XCTAssertEqual(voice.phase, .speaking)
        XCTAssertEqual(speaker.spoken, "可以休息")
        speaker.completion?()
        XCTAssertEqual(voice.phase, .listening)
        voice.end()
    }

    func testMutedReplyFinishingDoesNotStartMicrophone() async throws {
        let recognizer = VoiceRecognitionStub()
        let speaker = VoiceSpeakerStub()
        let voice = VoiceConversation(recognition: recognizer, speaker: speaker)
        voice.open(); voice.begin()
        recognizer.onUpdate?("想休息", true)
        voice.complete(id: try XCTUnwrap(voice.turn), text: "可以休息", needsReview: false, error: nil)
        voice.toggleMute()
        speaker.completion?()
        XCTAssertEqual(voice.phase, .muted)
        voice.end()
    }

    func testLateSpeechCompletionDoesNotReopenCall() async throws {
        let recognizer = VoiceRecognitionStub()
        let speaker = VoiceSpeakerStub()
        let voice = VoiceConversation(recognition: recognizer, speaker: speaker)
        voice.open(); voice.begin()
        recognizer.onUpdate?("想休息", true)
        voice.complete(id: try XCTUnwrap(voice.turn), text: "可以休息", needsReview: false, error: nil)
        voice.end()
        speaker.completion?()
        XCTAssertEqual(voice.phase, .ended)
    }

    func testFailureOnlyResendsAfterExplicitRetry() async throws {
        let recognizer = VoiceRecognitionStub()
        let voice = VoiceConversation(recognition: recognizer, speaker: VoiceSpeakerStub())
        var texts = [String]()
        voice.onSubmit = { text, _ in texts.append(text) }
        voice.open(); voice.begin()
        recognizer.onUpdate?("想休息", true)
        voice.complete(id: try XCTUnwrap(voice.turn), text: "", needsReview: false, error: "断网")
        XCTAssertEqual(texts, ["想休息"])
        XCTAssertEqual(voice.phase, .failed)
        voice.retry()
        XCTAssertEqual(texts, ["想休息", "想休息"])
        XCTAssertEqual(voice.phase, .thinking)
        voice.end()
    }

    func testPauseWaitsForCancelledRequestBeforeRecordingAgain() async {
        let recognizer = VoiceRecognitionStub()
        let voice = VoiceConversation(recognition: recognizer, speaker: VoiceSpeakerStub())
        var release: CheckedContinuation<Void, Never>?
        let pending = Task { await withCheckedContinuation { release = $0 } }
        while release == nil { await Task.yield() }
        voice.onCancel = { pending.cancel(); return pending }
        voice.open(); voice.begin(); voice.pause(); voice.begin()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(recognizer.starts, 0)
        release?.resume()
        await pending.value
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(recognizer.starts, 1)
        voice.end()
    }

    func testSilenceSubmitsPartialTranscriptAutomatically() async throws {
        let recognizer = VoiceRecognitionStub()
        let voice = VoiceConversation(recognition: recognizer, speaker: VoiceSpeakerStub())
        let submitted = expectation(description: "Automatic end of utterance")
        voice.onSubmit = { text, _ in
            XCTAssertEqual(text, "轻松训练")
            submitted.fulfill()
        }
        voice.open(); voice.begin()
        while recognizer.starts == 0 { await Task.yield() }
        recognizer.onUpdate?("轻松训练", false)
        await fulfillment(of: [submitted], timeout: 3)
        XCTAssertEqual(voice.phase, .thinking)
        voice.end()
    }

}
