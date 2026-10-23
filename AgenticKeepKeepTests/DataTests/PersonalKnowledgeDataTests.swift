import XCTest
import SwiftData
@testable import AgenticKeepKeep

@MainActor final class PersonalKnowledgeDataTests: XCTestCase {
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
