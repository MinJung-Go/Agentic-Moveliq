import XCTest
import SwiftData
@testable import AgenticKeepKeep

@MainActor
final class CoachSpeedTests: XCTestCase {
    private func wire(model: String, thinking: Bool?) async throws -> [String: Any] {
        MockURLProtocol.responder = { _ in (200, Data(#"{"choices":[{"message":{"content":"ok"}}]}"#.utf8)) }
        let client = OpenAICompatibleClient(config: LLMClientConfig(baseURL: "https://fixture.invalid", apiKey: "fixture", model: model), session: MockURLProtocol.makeSession())
        _ = try await client.complete(LLMRequest(messages: [.user("hi")], thinkingEnabled: thinking))
        return try JSONSerialization.jsonObject(with: XCTUnwrap(MockURLProtocol.lastRequestBody)) as! [String: Any]
    }

    func testGLMUsesMediumEvenWhenThinkingIsImplicit() async throws {
        defer { MockURLProtocol.reset() }
        for model in ["glm-5.2"] {
            for thinking: Bool? in [true, nil] {
                let body = try await wire(model: model, thinking: thinking)
                XCTAssertEqual(body["reasoning_effort"] as? String, "medium")
            }
        }
    }

    func testGLMOffIsExplicitAndOmitsEffort() async throws {
        defer { MockURLProtocol.reset() }
        let body = try await wire(model: "glm-5.2", thinking: false)
        XCTAssertEqual((body["thinking"] as? [String: String])?["type"], "disabled")
        XCTAssertNil(body["reasoning_effort"])
    }

    func testOtherModelsDoNotReceiveGLMEffort() async throws {
        defer { MockURLProtocol.reset() }
        for model in ["glm-4.7", "glm-5", "gpt-4o", "custom-model"] {
            let body = try await wire(model: model, thinking: true)
            XCTAssertNil(body["reasoning_effort"])
        }
    }

    func testStreamingUsesSupportedGLM53Effort() async throws {
        defer { MockURLProtocol.reset() }
        MockURLProtocol.responder = { _ in
            (200, Data("data: {\"choices\":[{\"delta\":{\"content\":\"ok\"}}]}\n\ndata: [DONE]\n\n".utf8))
        }
        let client = OpenAICompatibleClient(config: LLMClientConfig(baseURL: "https://fixture.invalid", apiKey: "fixture", model: "glm-5.3-flash"), session: MockURLProtocol.makeSession())
        _ = try await LLMStreamCollector.collect(client.stream(LLMRequest(messages: [.user("hi")], thinkingEnabled: true)))
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(MockURLProtocol.lastRequestBody)) as! [String: Any]
        XCTAssertEqual(body["reasoning_effort"] as? String, "high")
    }

    private var query: LLMToolCall {
        LLMToolCall(id: "query", name: CoachTools.records.name, argumentsJSON: #"{"kind":"health"}"#)
    }

    func testActivityTracksActualSuccessAndFailure() async throws {
        for failed in [false, true] {
            var events: [CoachToolActivity] = []
            let client = MockLLMClient(responses: [.calls([query]), .text("回复")])
            let tools = CoachTools(onActivity: { events.append($0) }) { _ in
                CoachToolResult(content: "结果", failed: failed)
            }
            _ = try await CoachAgent(client: client, tools: tools).reply(history: [], userMessage: "查询")
            XCTAssertEqual(events.count, 2)
            XCTAssertEqual(events.first?.status, .running)
            XCTAssertEqual(events.last?.status, failed ? .failed : .completed)
            XCTAssertEqual(events.first?.id, events.last?.id)
            XCTAssertNotNil(events.last?.duration)
            XCTAssertEqual(events.last?.title, "查询健康数据")
            XCTAssertFalse(client.requests.last!.messages.map(\.content).joined().contains(events[0].id.uuidString))
        }
    }

    func testCancellationDoesNotReportSuccess() async throws {
        var events: [CoachToolActivity] = []
        let client = MockLLMClient(responses: [.calls([query])])
        let tools = CoachTools(onActivity: { events.append($0) }) { _ in throw CancellationError() }
        do {
            _ = try await CoachAgent(client: client, tools: tools).reply(history: [], userMessage: "查询")
            XCTFail("Cancellation should propagate")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(events.map(\.status), [.running, .cancelled])
    }

    func testThrownErrorReportsFailure() async throws {
        var events: [CoachToolActivity] = []
        let client = MockLLMClient(responses: [.calls([query]), .text("查询失败")])
        let tools = CoachTools(onActivity: { events.append($0) }) { _ in throw LLMError.invalidEndpoint("fixture") }
        _ = try await CoachAgent(client: client, tools: tools).reply(history: [], userMessage: "查询")
        XCTAssertEqual(events.map(\.status), [.running, .failed])
    }

    func testPublicWebFailureRetainsSafeReason() async throws {
        var events: [CoachToolActivity] = []
        let search = LLMToolCall(id: "search", name: CoachTools.search.name, argumentsJSON: #"{"query":"Swift"}"#)
        let client = MockLLMClient(responses: [.calls([search]), .text("需要验证，尚未核实来源")])
        let tools = CoachTools(webSearchEnabled: true, onActivity: { events.append($0) }) { _ in
            throw PublicWebError.verification
        }
        _ = try await CoachAgent(client: client, tools: tools).reply(history: [], userMessage: "查询 Swift")
        XCTAssertEqual(events.last?.status, .failed)
        XCTAssertEqual(events.last?.failureReason, PublicWebError.verification.localizedDescription)
        let json = String(decoding: try JSONEncoder().encode(events), as: UTF8.self)
        XCTAssertEqual(CoachToolActivity.decode(json), events)
    }

    func testOldActivityWithoutFailureReasonStillDecodes() throws {
        let json = #"[{"id":"00000000-0000-0000-0000-000000000001","title":"查询","status":"failed"}]"#
        let activity = try XCTUnwrap(CoachToolActivity.decode(json).first)
        XCTAssertNil(activity.failureReason)
        XCTAssertEqual(activity.status, .failed)
    }

    func testActivityPersistsAndIsExcludedFromChatHistory() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let message = ChatMessage(role: .assistant, content: "已有回复")
        let activity = CoachToolActivity(title: "查询过程专用标记", status: .completed, duration: 0.3)
        message.toolActivityJSON = String(data: try JSONEncoder().encode([activity]), encoding: .utf8)
        context.insert(message)
        try context.save()
        let reader = ModelContext(context.container)
        let saved = try XCTUnwrap(reader.fetch(FetchDescriptor<ChatMessage>()).first)
        XCTAssertEqual(CoachToolActivity.decode(saved.toolActivityJSON), [activity])
        XCTAssertFalse(CoachHistoryBuilder.turns([saved]).map(\.content).joined().contains(activity.title))
        XCTAssertTrue(CoachToolActivity.decode(nil).isEmpty)
    }
}
