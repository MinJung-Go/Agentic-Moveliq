import XCTest
import SwiftData
@testable import AgenticKeepKeep

@MainActor final class PersonalKnowledgeDataTests: XCTestCase {
    private final class ReviewClient: LLMClient {
        var config = LLMClientConfig(baseURL: "", apiKey: "", model: "test")
        var judgment: KnowledgeJudgment
        var onReview: (@MainActor () -> Void)?
        init(source: KnowledgeSource) {
            judgment = .init(accepted: true, reason: "用户明确自述", evidence: [.init(sourceID: source.id, kind: .preference, quote: source.text)])
        }
        func complete(_ request: LLMRequest) async throws -> LLMResponse {
            await onReview?()
            return .text(try KnowledgeRules.payload(judgment))
        }
    }
    private func withKnowledgeAccount(_ body: (ModelContext, String) async throws -> Void) async throws {
        let previousContainer = AppModelContainer.active, previousStorage = ServiceCredentials.storageForTesting
        let container = try AppModelContainer.inMemory()
        let token = UUID().uuidString
        var storedCredential: String?
        ServiceCredentials.storageForTesting = .init(read: { storedCredential }, write: { storedCredential = $0; return true }, remove: { storedCredential = nil })
        defer {
            AppModelContainer.active = previousContainer
            ServiceCredentials.storageForTesting = previousStorage
        }
        try ServiceCredentials.save(.init(user: .init(id: UUID().uuidString, username: "knowledge-test"), token: token, expiresAt: "2099-01-01T00:00:00.000Z"))
        AppModelContainer.active = container
        try await body(ModelContext(container), token)
    }
    private func toolCall(_ args: [String: Any]) throws -> LLMToolCall {
        .init(id: UUID().uuidString, name: "skill", argumentsJSON: String(decoding: try JSONSerialization.data(withJSONObject: args), as: UTF8.self))
    }
    func testPersonalToolReceiptFollowsPersistenceAndNewSessionCanRead() async throws {
        try await withKnowledgeAccount { context, token in
            for kind in ["profile", "memory"] {
                let conversation = UUID()
                let message = ChatMessage(role: .user, content: kind == "profile" ? "我叫张爱民" : "我决定先恢复训练规律")
                message.conversationID = conversation; context.insert(message); try context.save()
                let sources = try PersonalKnowledgeStore.sources(context, conversation: conversation)
                let client = ReviewClient(source: try XCTUnwrap(sources.first))
                let result = try await PersonalSkillSession().execute(toolCall([
                    "action": "save", "kind": kind, "name": kind == "profile" ? "姓名" : "长期训练决定", "description": "用户自述", "body": message.content
                ]), sources: sources, context: context, token: token, client: client)
                XCTAssertFalse(result.failed, result.content)
                let persisted = try PersonalKnowledgeStore.load(ModelContext(context.container))
                let item = try XCTUnwrap(persisted.items.first(where: { $0.kind.rawValue == kind }))
                XCTAssertTrue(result.content.contains(item.id.uuidString))
                XCTAssertTrue(result.content.contains("revision=1"))
                let reader = PersonalSkillSession()
                let loaded = try await reader.execute(toolCall(["action": "load", "kind": kind, "skill_id": item.id.uuidString]), sources: sources, context: context, token: token, client: client)
                XCTAssertFalse(loaded.failed, loaded.content); XCTAssertTrue(loaded.content.contains(message.content))
                let wrongKind = try await PersonalSkillSession().execute(toolCall(["action": "load", "kind": "skill", "skill_id": item.id.uuidString]), sources: sources, context: context, token: token, client: client)
                XCTAssertTrue(wrongKind.failed)
            }
        }
    }
    func testPersonalToolLateAccountChangeReturnsFailureWithoutWrite() async throws {
        try await withKnowledgeAccount { context, token in
            let conversation = UUID(), message = ChatMessage(role: .user, content: "我叫张爱民")
            message.conversationID = conversation; context.insert(message); try context.save()
            let sources = try PersonalKnowledgeStore.sources(context, conversation: conversation)
            let client = ReviewClient(source: try XCTUnwrap(sources.first))
            client.onReview = { AppModelContainer.active = nil }
            let result = try await PersonalSkillSession().execute(toolCall(["action": "save", "kind": "profile", "name": "姓名", "description": "用户自述", "body": "张爱民"]), sources: sources, context: context, token: token, client: client)
            XCTAssertTrue(result.failed)
            XCTAssertTrue(try PersonalKnowledgeStore.load(context).items.isEmpty)
        }
    }
    func testPersonalToolSourceChangedDuringReviewReturnsFailureWithoutWrite() async throws {
        try await withKnowledgeAccount { context, token in
            let conversation = UUID(), message = ChatMessage(role: .user, content: "我叫张爱民")
            message.conversationID = conversation; context.insert(message); try context.save()
            let sources = try PersonalKnowledgeStore.sources(context, conversation: conversation)
            let client = ReviewClient(source: try XCTUnwrap(sources.first))
            client.onReview = { message.content = "不要记住刚才的话" }
            let result = try await PersonalSkillSession().execute(toolCall(["action": "save", "kind": "profile", "name": "姓名", "description": "用户自述", "body": "张爱民"]), sources: sources, context: context, token: token, client: client)
            XCTAssertTrue(result.failed)
            XCTAssertTrue(try PersonalKnowledgeStore.load(context).items.isEmpty)
        }
    }

    func testKnowledgeSnapshotPersistsInOnlyItsAccountContainer() throws {
        let first = try AppModelContainer.inMemory(), second = try AppModelContainer.inMemory()
        let context = ModelContext(first), workspace = PersonalKnowledgeWorkspace()
        var state = KnowledgeState()
        _ = try state.save(kind: .profile, content: .init(name: "交流方式", description: "喜欢简短说明", body: "先说结论，再说理由。"), evidence: [.init(id: UUID(), conversationID: UUID(), kind: .preference, date: Date())])
        workspace.payloadJSON = try KnowledgeRules.payload(state); context.insert(workspace); try context.save()
        XCTAssertEqual(try PersonalKnowledgeStore.load(ModelContext(first)).items, state.items)
        XCTAssertTrue(try PersonalKnowledgeStore.load(ModelContext(second)).items.isEmpty)
    }
    func testUnauthenticatedOrLateWriterCannotChangeWorkspace() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let before = try PersonalKnowledgeStore.load(context)
        XCTAssertThrowsError(try PersonalKnowledgeStore.mutate(context, token: nil) { $0.items.removeAll(); $0.enabledAt = .distantPast })
        XCTAssertEqual(try PersonalKnowledgeStore.load(context), before)
    }
    func testRealTimeTranscriptsAndOtherConversationsExcludedFromExtraction() throws {
        let context = ModelContext(try AppModelContainer.inMemory()), id = UUID()
        let text = ChatMessage(role: .user, content: "喜欢先说结论"); text.conversationID = id
        let realtime = ChatMessage(role: .user, content: "实时通话"); realtime.conversationID = id; realtime.isRealtime = true
        let other = ChatMessage(role: .user, content: "别的会话"); other.conversationID = UUID()
        for message in [text, realtime, other] { context.insert(message) }; try context.save()
        let sources = try PersonalKnowledgeStore.sources(context, conversation: id)
        XCTAssertEqual(sources.map(\.id), [text.uuid])
        XCTAssertFalse(sources[0].operationCompleted)
    }
    func testExecutionEvidenceComesFromPersistedDecisionNotAssistantClaim() throws {
        let context = ModelContext(try AppModelContainer.inMemory()), id = UUID()
        let message = ChatMessage(role: .assistant, content: "已经为你安排好了！", pendingPlanJSON: "{}")
        message.conversationID = id; context.insert(message); try context.save()
        XCTAssertFalse(try PersonalKnowledgeStore.sources(context, conversation: id)[0].operationCompleted)
        message.planAcceptedAt = Date(); try context.save()
        XCTAssertTrue(try PersonalKnowledgeStore.sources(context, conversation: id)[0].operationCompleted)
    }
    func testCompressionMemoryDoesNotCrossConversations() throws {
        let context = ModelContext(try AppModelContainer.inMemory()), id = UUID()
        let other = ChatMessage(role: .user, content: "别的会话"); other.date = .distantPast; other.conversationID = UUID()
        let user = ChatMessage(role: .user, content: "膝盖不舒服，避免跳跃"); user.conversationID = id
        let assistant = ChatMessage(role: .assistant, content: "先暂停跳跃"); assistant.conversationID = id; assistant.date = user.date.addingTimeInterval(1)
        for message in [other, user, assistant] { context.insert(message) }; try context.save()
        let turns = CoachHistoryBuilder.turns([user, assistant])
        let memory = CoachMemory(sessionID: user.uuid, coveredCount: 2, coveredDigest: CoachMemory.digest(turns[...]), facts: [.init(sourceID: user.uuid, quote: user.content)])
        let store = CoachMemoryStore(); try store.save(memory, generation: store.begin(), context: context)
        XCTAssertEqual(store.load([user, assistant]), memory); XCTAssertNil(store.load([other]))
    }
    func testPendingSystemActionsAreDeduplicatedOnlyWithinConversation() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let a = UUID(), b = UUID(), payload = CoachActionPayload(title: "提醒训练", reason: "用户要求")
        let first = try CoachLifeStore.action(kind: "calendar", payload: payload, in: context, conversationID: a)
        let repeated = try CoachLifeStore.action(kind: "calendar", payload: payload, in: context, conversationID: a)
        let separate = try CoachLifeStore.action(kind: "calendar", payload: payload, in: context, conversationID: b)
        XCTAssertEqual(first.uuid, repeated.uuid); XCTAssertNotEqual(first.uuid, separate.uuid)
        XCTAssertEqual(separate.conversationID, b)
    }

    func testLongSourceIsNotSilentlyTruncatedBeforeEvidenceReview() throws {
        let context = ModelContext(try AppModelContainer.inMemory()), id = UUID()
        let original = String(repeating: "背景说明。", count: 400) + "但只限今天，不要作为长期偏好。"
        let message = ChatMessage(role: .user, content: original); message.conversationID = id
        context.insert(message); try context.save()
        XCTAssertEqual(try PersonalKnowledgeStore.sources(context, conversation: id)[0].text, original)
    }

}
