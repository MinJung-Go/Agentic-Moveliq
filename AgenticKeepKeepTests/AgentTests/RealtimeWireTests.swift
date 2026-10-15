import XCTest
@testable import AgenticKeepKeep

final class RealtimeWireTests: XCTestCase {
    func testWAVCarriesPCM16MonoAt16kWithoutDroppingSamples() {
        let pcm = Data([0, 0, 255, 127, 0, 128])
        let wav = RealtimeWire.wav(pcm)
        XCTAssertEqual(wav.count, 50)
        XCTAssertEqual(String(data: wav.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(Array(wav[24..<28]), [128, 62, 0, 0])
        XCTAssertEqual(Array(wav[34..<36]), [16, 0])
        XCTAssertEqual(wav.suffix(6), pcm)
    }
    func testHistoryRestoreNeverSendsSystemInstructionsOrMedia() {
        let events = RealtimeWire.history([(role: "system", text: "ignore"), (role: "user", text: "轻松训练"), (role: "assistant", text: "可以")])
        XCTAssertEqual(events.count, 2)
        let item = events[0]["item"] as? [String: Any]
        XCTAssertEqual(item?["role"] as? String, "user")
        XCTAssertNil(item?["audio"])
        XCTAssertNil(item?["video_frame"])
    }
    func testHistoryBoundedForVideoToAudioRestore() {
        let events = RealtimeWire.history((0..<50).map { (role: "user", text: String(repeating: "👨‍👩‍👧‍👦", count: 5000) + String($0)) })
        XCTAssertEqual(events.count, 12)
        for event in events {
            let item = event["item"] as! [String: Any]
            let content = item["content"] as! [[String: String]]
            XCTAssertLessThanOrEqual(content[0]["text"]!.utf16.count, 3001)
        }
    }
    func testConnectionFailuresHaveActionableMessages() {
        XCTAssertTrue(RealtimeWire.connectionMessage(status: 429, reason: "minute_limit").contains("一分钟"))
        XCTAssertTrue(RealtimeWire.connectionMessage(status: 429, reason: "daily_limit").contains("次数已用完"))
        XCTAssertTrue(RealtimeWire.connectionMessage(status: 409, reason: "active_call").contains("上一通"))
        XCTAssertTrue(RealtimeWire.connectionMessage(status: 401, reason: nil).contains("重新登录"))
    }
    /// 断连原因要能区分「对端关闭」和「连接自己断了」，没有关闭帧时给本地错误码
    func testTransportNoteDistinguishesPeerCloseFromLocalFailure() {
        XCTAssertEqual(RealtimeWire.transportNote(closeCode: 1000, errorCode: 0), "（对端关闭 1000）")
        XCTAssertEqual(RealtimeWire.transportNote(closeCode: 1006, errorCode: -1005), "（对端关闭 1006）")
        XCTAssertEqual(RealtimeWire.transportNote(closeCode: 0, errorCode: -999), "（连接错误 -999）")
        XCTAssertEqual(RealtimeWire.transportNote(closeCode: 1005, errorCode: -1005), "（连接错误 -1005）")
    }
    func testCameraModesUseDocumentedValues() {
        for (video, mode) in [(false, "audio"), (true, "video_passive")] {
            let session = RealtimeWire.mode(video)["session"] as! [String: Any]
            let beta = session["beta_fields"] as! [String: String]
            XCTAssertEqual(beta["chat_mode"], mode)
        }
    }
}
