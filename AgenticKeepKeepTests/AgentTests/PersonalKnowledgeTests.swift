import XCTest
@testable import AgenticKeepKeep

final class PersonalKnowledgeTests: XCTestCase {
    private let body = "## 适用\n加班但仍想训练时。\n## 步骤\n先询问剩余时间。\n减少辅助动作。\n## 注意\n疼痛时暂停。"
    private func content(_ name: String = "加班训练") -> KnowledgeContent { .init(name: name, description: "时间有限时调整训练", body: body) }
    private func evidence(_ kind: KnowledgeEvidenceKind = .explicitRequest, id: UUID = UUID(), conversation: UUID = UUID()) -> KnowledgeEvidence {
        .init(id: id, conversationID: conversation, kind: kind, date: Date(timeIntervalSince1970: 100))
    }
    private func seed() throws -> (KnowledgeState, UUID) {
        var state = KnowledgeState(); let id = try state.save(kind: .skill, content: content(), evidence: [evidence()]); return (state, id)
    }
    private var patch: KnowledgePatch { .init(field: .body, oldString: "减少辅助动作。", newString: "减少辅助动作；太晚时讨论休息。") }

    func testAssistantOnlyIsCandidateAndInvisibleToSearch() throws {
        var state = KnowledgeState()
        let id = try state.save(kind: .skill, content: content(), evidence: [evidence(.suggestion)])
        XCTAssertTrue(state.items[0].candidate); XCTAssertTrue(state.notices.isEmpty)
        XCTAssertTrue(KnowledgeRules.search("加班", in: state).isEmpty)
        try state.addEvidence([evidence(.feedback)], to: id)
        XCTAssertFalse(state.items[0].candidate); XCTAssertEqual(KnowledgeRules.search("加班", in: state).count, 1)
        XCTAssertEqual(state.notices.count, 1)
    }
    func testExplicitSaveDoesNotClaimOutcomeValidation() throws {
        let (state, _) = try seed()
        XCTAssertFalse(state.items[0].candidate)
        XCTAssertEqual(state.items[0].evidence[0].kind, .explicitRequest)
        XCTAssertTrue(state.items[0].evidence[0].kind.title.contains("未验证"))
    }
    func testAssistantCannotBecomePersonalFact() {
        var state = KnowledgeState()
        XCTAssertThrowsError(try state.save(kind: .profile, content: content(), evidence: [evidence(.suggestion)]))
        XCTAssertTrue(state.items.isEmpty)
    }
    func testExactSaveDeduplicatesAndAssociatesEvidence() throws {
        var (state, id) = try seed()
        XCTAssertEqual(try state.save(kind: .skill, content: content(), evidence: [evidence(.feedback)]), id)
        XCTAssertEqual(state.items.count, 1); XCTAssertEqual(state.items[0].evidence.count, 2)
        var different = content(); different.body += "\n其他限制。"
        XCTAssertThrowsError(try state.save(kind: .skill, content: different, evidence: [evidence()]))
        XCTAssertEqual(state.items[0].revision, 1)
    }
    func testPatchChangesOnlyUniqueFragment() throws {
        var (state, id) = try seed()
        try state.patch(id: id, expected: 1, operationID: "one", patches: [patch], manual: true)
        XCTAssertEqual(state.items[0].revision, 2)
        XCTAssertTrue(state.items[0].content.body.contains("太晚"))
        XCTAssertTrue(state.items[0].content.body.contains("疼痛时暂停。"))
        XCTAssertEqual(state.items[0].history.first?.before.body, body)
    }
    func testPatchBatchIsAtomic() throws {
        var (state, id) = try seed(); let before = state
        let bad = KnowledgePatch(field: .body, oldString: "不存在", newString: "插入")
        XCTAssertThrowsError(try state.patch(id: id, expected: 1, operationID: "one", patches: [patch, bad], evidence: [evidence()]))
        XCTAssertEqual(state, before)
    }
    func testAmbiguousIncludingOverlappingMatchesRejected() throws {
        var value = content(); value.body += "\naaa"
        XCTAssertThrowsError(try KnowledgeRules.applying([.init(field: .body, oldString: "aa", newString: "b")], to: value, kind: .skill))
        XCTAssertThrowsError(try KnowledgeRules.applying([.init(field: .body, oldString: "", newString: "b")], to: value, kind: .skill))
    }
    func testWholeBodyReplacementForbidden() throws {
        XCTAssertThrowsError(try KnowledgeRules.applying([.init(field: .body, oldString: body, newString: body + "\n更多")], to: content(), kind: .skill))
    }
    func testVersionConflictPreservesEverything() throws {
        var (state, id) = try seed(); let before = state
        XCTAssertThrowsError(try state.patch(id: id, expected: 9, operationID: "wrong", patches: [patch], manual: true))
        XCTAssertEqual(state, before)
    }
    func testIdempotentRetryAndReusedOperationRejectsDifferentPayload() throws {
        var (state, id) = try seed()
        try state.patch(id: id, expected: 1, operationID: "one", patches: [patch], manual: true)
        let saved = state
        try state.patch(id: id, expected: 1, operationID: "one", patches: [patch], manual: true)
        XCTAssertEqual(state, saved)
        XCTAssertThrowsError(try state.patch(id: id, expected: 2, operationID: "one", patches: [patch], manual: true))
    }
    func testNoopDoesNotCreateRevisionOrNotice() throws {
        var (state, id) = try seed()
        let noop = KnowledgePatch(field: .body, oldString: "减少辅助动作。", newString: "减少辅助动作。")
        try state.patch(id: id, expected: 1, operationID: "noop", patches: [noop], manual: true)
        XCTAssertEqual(state.items[0].revision, 1); XCTAssertEqual(state.notices.count, 1); XCTAssertTrue(state.items[0].history.isEmpty)
    }
    func testInsertionAndDeletionKeepRequiredSections() throws {
        let insert = KnowledgePatch(field: .body, oldString: "## 步骤", newString: "## 步骤\n先检查日程。")
        let delete = KnowledgePatch(field: .body, oldString: "减少辅助动作。", newString: "")
        let result = try KnowledgeRules.applying([insert, delete], to: content(), kind: .skill)
        XCTAssertTrue(result.body.contains("检查日程")); XCTAssertFalse(result.body.contains("减少辅助"))
        XCTAssertThrowsError(try KnowledgeRules.applying([.init(field: .body, oldString: "## 注意", newString: "")], to: result, kind: .skill))
    }
    func testEditorCreatesPatchesNotWholeDocumentUpdate() throws {
        let old = content(); var new = old
        new.name = "晚间训练"; new.body = body.replacingOccurrences(of: "减少辅助动作。", with: "减少辅助动作；太晚就休息。")
        let patches = try KnowledgeRules.diff(from: old, to: new)
        XCTAssertFalse(patches.contains { $0.field == .body && $0.oldString == body })
        XCTAssertEqual(try KnowledgeRules.applying(patches, to: old, kind: .skill), new)
    }
    func testSingleParagraphDiffSupportsInsertions() throws {
        let old = KnowledgeContent(name: "表达", description: "交流偏好", body: "喜欢简短而具体的说明。")
        for text in ["喜欢简短且清晰而具体的说明。", "喜欢简短而具体的说明。避免长篇。", "通常喜欢简短而具体的说明。"] {
            var new = old; new.body = text
            XCTAssertEqual(try KnowledgeRules.applying(KnowledgeRules.diff(from: old, to: new), to: old, kind: .profile), new)
        }
    }
    func testDisabledAndArchivedExcludedAndNotAutomaticallyReactivated() throws {
        var (state, id) = try seed()
        try state.setStatus(.archived, id: id, expected: 1)
        XCTAssertTrue(KnowledgeRules.search("加班", in: state).isEmpty)
        XCTAssertEqual(KnowledgeRules.search("加班", in: state, includeInactive: true).count, 1)
        XCTAssertThrowsError(try state.patch(id: id, expected: 2, operationID: "auto", patches: [patch], evidence: [evidence()]))
        try state.addEvidence([evidence(.feedback)], to: id)
        XCTAssertEqual(state.items[0].status, .archived)
        try state.setStatus(.active, id: id, expected: 2)
        XCTAssertEqual(KnowledgeRules.search("加班", in: state).count, 1)
    }
    func testUndoRefusesToClobberLaterEdit() throws {
        var (state, id) = try seed(); let notice = state.notices[0]
        try state.patch(id: id, expected: 1, operationID: "edit", patches: [patch], manual: true)
        XCTAssertThrowsError(try state.undo(noticeID: notice.id))
        try state.undo(noticeID: state.notices.last!.id)
        XCTAssertEqual(state.items[0].content.body, body); XCTAssertEqual(state.items[0].revision, 3)
    }
    func testUndoCreationSuppressesSameSourceButAllowsNewExplicitRequest() throws {
        var (state, _) = try seed(); let oldEvidence = state.items[0].evidence
        try state.undo(noticeID: state.notices[0].id)
        XCTAssertTrue(state.items.isEmpty)
        XCTAssertThrowsError(try state.save(kind: .skill, content: content(), evidence: oldEvidence))
        _ = try state.save(kind: .skill, content: content(), evidence: [evidence()])
        XCTAssertEqual(state.items.count, 1)
    }
    func testDeletePurgesBodyHistoryOperationsAndNotices() throws {
        var (state, id) = try seed()
        try state.patch(id: id, expected: 1, operationID: "edit", patches: [patch], manual: true)
        try state.delete(id: id, expected: 2)
        let json = try KnowledgeRules.payload(state)
        XCTAssertFalse(json.contains("减少辅助")); XCTAssertTrue(state.notices.isEmpty); XCTAssertTrue(state.operations.isEmpty)
        XCTAssertFalse(state.suppressedSources.isEmpty)
    }
    func testDeleteConversationRetainsSavedKnowledgeRemovesOrphanCandidateAndJobs() throws {
        var (state, _) = try seed(); let conversation = state.items[0].evidence[0].conversationID
        _ = try state.save(kind: .skill, content: content("出差酒店运动"), evidence: [evidence(.suggestion, conversation: conversation)])
        state.jobs.append(.init(conversationID: conversation, sourceIDs: [UUID()]))
        state.removeConversation(conversation)
        XCTAssertEqual(state.items.count, 1); XCTAssertTrue(state.items[0].evidence[0].sourceDeleted); XCTAssertTrue(state.jobs.isEmpty)
    }
    func testArchiveRoundTripNoCandidatesJobsOrAuthorizations() throws {
        var (state, _) = try seed()
        _ = try state.save(kind: .skill, content: content("睡前放松"), evidence: [evidence(.suggestion)])
        state.jobs.append(.init(conversationID: UUID(), sourceIDs: [UUID()]))
        let archive = KnowledgeArchive(state: state, account: "account-hash")
        let data = try JSONEncoder().encode(archive)
        let decoded = try KnowledgeArchive.read(data)
        let restored = try decoded.applying(to: KnowledgeState(), replaceIDs: [])
        XCTAssertEqual(restored.items.count, 1); XCTAssertTrue(restored.jobs.isEmpty)
        let json = String(decoding: data, as: UTF8.self)
        for forbidden in ["sessionToken", "apiKey", "password", "jobs", "automation"] { XCTAssertFalse(json.contains(forbidden)) }
        XCTAssertTrue(restored.items[0].evidence[0].sourceDeleted)
    }
    func testArchiveRejectsCorruptionUnknownVersionAndDuplicateIDs() throws {
        let (state, _) = try seed(); var archive = KnowledgeArchive(state: state, account: "same")
        XCTAssertThrowsError(try KnowledgeArchive.read(Data("garbage".utf8)))
        archive.version = 99; XCTAssertThrowsError(try KnowledgeArchive.read(JSONEncoder().encode(archive)))
        archive.version = 1; archive.items.append(archive.items[0])
        XCTAssertThrowsError(try KnowledgeArchive.read(JSONEncoder().encode(archive)))
    }
    func testImportConflictDefaultsToLocalAndExplicitRestoreInvalidatesOldUndo() throws {
        var (state, id) = try seed(); let archive = KnowledgeArchive(state: state, account: "same")
        try state.patch(id: id, expected: 1, operationID: "edit", patches: [patch], manual: true)
        XCTAssertEqual(archive.conflicts(in: state).count, 1)
        XCTAssertEqual(try archive.applying(to: state, replaceIDs: []).items, state.items)
        let restored = try archive.applying(to: state, replaceIDs: [id])
        XCTAssertEqual(restored.items[0].content.body, body); XCTAssertEqual(restored.items[0].revision, 3)
        XCTAssertTrue(restored.notices.isEmpty); XCTAssertTrue(restored.operations.isEmpty)
    }
    func testSearchUsesChineseBigramsAndRespectsBudget() throws {
        var state = KnowledgeState()
        for index in 0..<8 {
            var item = KnowledgeItem(kind: .skill, content: content("加班训练方式\(index)")); item.evidence = [evidence()]; state.items.append(item)
        }
        XCTAssertEqual(KnowledgeRules.search("加班训练", in: state).count, 5)
        XCTAssertTrue(KnowledgeRules.search("海洋捕鱼", in: state).isEmpty)
    }
    func testEvidenceCannotForgeUserRoleQuoteOrExecutionReceipt() throws {
        let source = KnowledgeSource(id: UUID(), conversationID: UUID(), role: "assistant", text: "建议先问剩余时间", date: Date())
        for kind: KnowledgeEvidenceKind in [.explicitRequest, .feedback, .execution] {
            let judgment = KnowledgeJudgment(accepted: true, reason: "", evidence: [.init(sourceID: source.id, kind: kind, quote: "先问剩余时间")])
            XCTAssertThrowsError(try judgment.validated(sources: [source], allowed: [source.id]))
        }
        let wrongQuote = KnowledgeJudgment(accepted: true, reason: "", evidence: [.init(sourceID: source.id, kind: .suggestion, quote: "我已经完成")])
        XCTAssertThrowsError(try wrongQuote.validated(sources: [source], allowed: [source.id]))
        let correct = KnowledgeJudgment(accepted: true, reason: "", evidence: [.init(sourceID: source.id, kind: .suggestion, quote: "先问剩余时间")])
        XCTAssertEqual(try correct.validated(sources: [source], allowed: [source.id]).first?.kind, .suggestion)
        XCTAssertThrowsError(try correct.validated(sources: [source], allowed: []))
    }
    func testExpiredFactsAreNotAvailable() throws {
        var state = KnowledgeState()
        _ = try state.save(kind: .memory, content: content(), evidence: [evidence(.preference)], expiresAt: Date(timeIntervalSince1970: 1))
        XCTAssertFalse(state.items[0].available)
    }
    func testDuplicateImportIsNoopDespiteSourceLinksBeingUnavailable() throws {
        let (state, _) = try seed()
        let archive = KnowledgeArchive(state: state, account: "same")
        XCTAssertTrue(archive.conflicts(in: state).isEmpty)
        XCTAssertEqual(try archive.applying(to: state, replaceIDs: []).items, state.items)
    }
    func testIndependentVerifierCannotAcceptDuplicateCitations() {
        let source = KnowledgeSource(id: UUID(), conversationID: UUID(), role: "user", text: "记住这个方法", date: Date())
        let citation = KnowledgeJudgment.Citation(sourceID: source.id, kind: .explicitRequest, quote: "记住这个方法")
        let judgment = KnowledgeJudgment(accepted: true, reason: "", evidence: [citation, citation])
        XCTAssertThrowsError(try judgment.validated(sources: [source], allowed: [source.id]))
    }

    private final class StubClient: LLMClient {
        var config = LLMClientConfig(baseURL: "https://example.invalid", apiKey: "", model: "fixture")
        var response: LLMResponse
        var requests: [LLMRequest] = []
        init(_ response: LLMResponse) { self.response = response }
        func complete(_ request: LLMRequest) async throws -> LLMResponse { requests.append(request); return response }
    }
    func testExtractorAllowsEmptyResultAndExposesNoTools() async throws {
        let client = StubClient(.text(#"{"proposals":[]}"#))
        let result = try await PersonalLearningAgent(client: client).extract(sources: [], existing: [], profile: "未设置")
        XCTAssertTrue(result.isEmpty); XCTAssertTrue(client.requests[0].tools.isEmpty)
        XCTAssertEqual(client.requests[0].thinkingEnabled, false)
    }
    func testVerifierChecksOriginalUserQuoteIndependently() async throws {
        let source = KnowledgeSource(id: UUID(), conversationID: UUID(), role: "user", text: "记住这个方法", date: Date())
        let judgment = KnowledgeJudgment(accepted: true, reason: "明确保存", evidence: [.init(sourceID: source.id, kind: .explicitRequest, quote: "记住这个方法")])
        let client = StubClient(.text(try KnowledgeRules.payload(judgment)))
        let proposal = KnowledgeProposal(action: "save", kind: .skill, content: content(), sourceIDs: [source.id])
        let verified = try await PersonalLearningAgent(client: client).verify(proposal: proposal, sources: [source])
        XCTAssertEqual(verified[0].kind, .explicitRequest)
        XCTAssertEqual(client.requests.count, 1); XCTAssertTrue(client.requests[0].tools.isEmpty)
    }
    func testTruncatedModelOutputCannotBecomeAWrite() async throws {
        let client = StubClient(.init(content: #"{"proposals":[]}"#, finishReason: "length"))
        do { _ = try await PersonalLearningAgent(client: client).extract(sources: [], existing: [], profile: ""); XCTFail("Expected truncated rejection") }
        catch { XCTAssertTrue(error is KnowledgeError) }
    }
    func testRequestOverBudgetDoesNotCallModel() async throws {
        let client = StubClient(.text(#"{"proposals":[]}"#))
        do { _ = try await PersonalLearningAgent(client: client, inputByteLimit: 100).extract(sources: [], existing: [], profile: ""); XCTFail("Expected budget rejection") }
        catch { XCTAssertTrue(client.requests.isEmpty) }
    }
    func testKnownCredentialPatternsCannotEnterKnowledgeOrArchive() {
        let content = KnowledgeContent(name: "资料", description: "不应保存的凭据", body: "api_key: sk-example12345678901234567890")
        XCTAssertThrowsError(try KnowledgeRules.validate(content, kind: .profile))
    }
    func testProfileAndMemoryCanBeFoundWithoutLoadingAllBodies() throws {
        var state = KnowledgeState()
        _ = try state.save(kind: .profile, content: .init(name: "表达偏好", description: "简短说明", body: "先说结论再说理由。"), evidence: [evidence(.preference)])
        XCTAssertTrue(KnowledgeRules.search("表达", in: state).isEmpty)
        XCTAssertEqual(KnowledgeRules.search("表达", in: state, kind: .profile).count, 1)
    }

    func testPersonalFactCanBeCorrectedWithoutSkillBodyRestriction() throws {
        let old = KnowledgeContent(name: "交流", description: "说明方式", body: "喜欢简短回答")
        var new = old; new.body = "复杂问题给出具体步骤"
        XCTAssertEqual(try KnowledgeRules.applying(KnowledgeRules.diff(from: old, to: new), to: old, kind: .profile), new)
    }
    func testOrphanCandidateRemovesItsHiddenPatchHistory() throws {
        var state = KnowledgeState(); let source = evidence(.suggestion)
        let id = try state.save(kind: .skill, content: content(), evidence: [source])
        try state.patch(id: id, expected: 1, operationID: "draft-edit", patches: [patch], manual: true)
        state.removeConversation(source.conversationID)
        XCTAssertTrue(state.items.isEmpty); XCTAssertTrue(state.operations.isEmpty)
        XCTAssertFalse(try KnowledgeRules.payload(state).contains("辅助动作"))
    }

    func testUndoPromotionCannotBeReversedByAnotherAssistantSuggestion() throws {
        var state = KnowledgeState()
        let id = try state.save(kind: .skill, content: content(), evidence: [evidence(.suggestion)])
        try state.addEvidence([evidence(.endorsement)], to: id)
        try state.undo(noticeID: state.notices.last!.id)
        XCTAssertTrue(state.items[0].candidate)
        try state.addEvidence([evidence(.suggestion)], to: id)
        XCTAssertTrue(state.items[0].candidate)
        try state.addEvidence([evidence(.explicitRequest)], to: id)
        XCTAssertFalse(state.items[0].candidate)
    }

}
