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

    func testDismissingNoticePreservesSavedKnowledgeAndUndo() throws {
        var (state, _) = try seed()
        let before = state
        let notice = state.notices[0]
        state.dismissNotice(notice.id)
        XCTAssertEqual(state.items, before.items)
        XCTAssertEqual(state.operations, before.operations)
        XCTAssertEqual(state.notices[0].dismissed, true)
        XCTAssertFalse(state.notices[0].undone)
        let restored = try JSONDecoder().decode(KnowledgeState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(restored, state)
        try state.undo(noticeID: notice.id)
        XCTAssertTrue(state.items.isEmpty)
        XCTAssertTrue(state.notices.isEmpty)
        XCTAssertFalse(state.suppressedSources.isEmpty)
    }
    func testLegacyNoticeWithoutDismissedFlagStillDecodes() throws {
        let (state, _) = try seed()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state.notices[0])) as? [String: Any])
        json.removeValue(forKey: "dismissed")
        let restored = try JSONDecoder().decode(KnowledgeNotice.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored.id, state.notices[0].id)
        XCTAssertNil(restored.dismissed)
        XCTAssertFalse(restored.undone)
    }

    private func arguments(_ value: [String: Any]) throws -> PersonalSkillTool.Arguments {
        try JSONDecoder().decode(PersonalSkillTool.Arguments.self, from: JSONSerialization.data(withJSONObject: value))
    }

    func testToolSavesPersonalFactsAfterVerifiedUserSourceWithoutSaveKeyword() async throws {
        for kind: KnowledgeKind in [.profile, .memory] {
            let text = kind == .profile ? "我叫张爱民" : "我决定先恢复规律，再提升训练量"
            let source = KnowledgeSource(id: UUID(), conversationID: UUID(), role: "user", text: text, date: Date())
            let args = try arguments(["action": "save", "kind": kind.rawValue, "name": kind == .profile ? "姓名" : "长期训练决定", "description": "用户明确表达", "body": text])
            var state = KnowledgeState()
            let proposal = try PersonalSkillTool.writeProposal(args, state: state, loaded: [:], sources: [source])
            let judgment = KnowledgeJudgment(accepted: true, reason: "用户自述", evidence: [.init(sourceID: source.id, kind: .preference, quote: text)])
            let client = StubClient(.text(try KnowledgeRules.payload(judgment)))
            let evidence = try await PersonalLearningAgent(client: client).verify(proposal: proposal, sources: [source])
            try PersonalSkillTool.validatePersonalWrite(proposal, evidence: evidence, sources: [source])
            let id = try state.applyVerified(proposal, evidence: evidence, operationID: "foreground")
            XCTAssertEqual(state.items.first?.id, id)
            XCTAssertEqual(state.items.first?.kind, kind)
            XCTAssertEqual(state.items.first?.content.body, text)
            XCTAssertEqual(state.items.first?.revision, 1)
            XCTAssertEqual(state.items.first?.candidate, false)
            XCTAssertEqual(state.notices.count, 1)
            XCTAssertEqual(KnowledgeRules.search(args.name!, in: state, kind: kind).first?.id, id)
            // Background uses the same mutation; duplicate input must not create a second notice/item.
            XCTAssertEqual(try state.applyVerified(proposal, evidence: evidence, operationID: "background"), id)
            XCTAssertEqual(state.items.count, 1); XCTAssertEqual(state.notices.count, 1)
        }
    }

    func testPersonalPatchRequiresLoadCorrectKindAndCurrentVersionThenCanUndo() throws {
        for kind: KnowledgeKind in [.profile, .memory] {
            var state = KnowledgeState()
            let id = try state.save(kind: kind, content: .init(name: "称呼", description: "用户称呼", body: "叫我小张"), evidence: [evidence(.preference)])
            let source = KnowledgeSource(id: UUID(), conversationID: UUID(), role: "user", text: "以后叫我爱民", date: Date())
            let payload: [String: Any] = ["action": "patch", "kind": kind.rawValue, "skill_id": id.uuidString, "expected_revision": 1,
                "patches": [["field": "body", "old_string": "叫我小张", "new_string": "叫我爱民"]]]
            let args = try arguments(payload)
            XCTAssertThrowsError(try PersonalSkillTool.writeProposal(args, state: state, loaded: [:], sources: [source]))
            var wrong = payload; wrong["kind"] = "skill"
            XCTAssertThrowsError(try PersonalSkillTool.writeProposal(arguments(wrong), state: state, loaded: [id: 1], sources: [source]))
            let proposal = try PersonalSkillTool.writeProposal(args, state: state, loaded: [id: 1], sources: [source])
            let proof = [KnowledgeEvidence(id: source.id, conversationID: source.conversationID, kind: .preference, date: source.date)]
            try PersonalSkillTool.validatePersonalWrite(proposal, evidence: proof, sources: [source])
            XCTAssertEqual(try state.applyVerified(proposal, evidence: proof, operationID: "correction"), id)
            XCTAssertEqual(state.items[0].content.body, "叫我爱民"); XCTAssertEqual(state.items[0].revision, 2)
            XCTAssertEqual(state.items[0].history.count, 1)
            let after = state
            XCTAssertThrowsError(try PersonalSkillTool.writeProposal(args, state: state, loaded: [id: 1], sources: [source]))
            XCTAssertThrowsError(try state.applyVerified(proposal, evidence: proof, operationID: "stale-background"))
            XCTAssertEqual(state, after)
            try state.undo(noticeID: state.notices.last!.id)
            XCTAssertEqual(state.items[0].content.body, "叫我小张")
        }
    }

    func testPersonalWriteRejectsAssistantClaimsAndUnrelatedOldUserEvidence() throws {
        let old = KnowledgeSource(id: UUID(), conversationID: UUID(), role: "user", text: "之前的信息", date: Date())
        let latest = KnowledgeSource(id: UUID(), conversationID: old.conversationID, role: "user", text: "今天聊聊其他事情", date: Date())
        for kind: KnowledgeKind in [.profile, .memory] {
            let proposal = KnowledgeProposal(action: "save", kind: kind, content: .init(name: "姓名", description: "猜测", body: "叫小张"), sourceIDs: [old.id, latest.id])
            let oldProof = KnowledgeEvidence(id: old.id, conversationID: old.conversationID, kind: .preference, date: old.date)
            XCTAssertThrowsError(try PersonalSkillTool.validatePersonalWrite(proposal, evidence: [oldProof], sources: [old, latest]))
            for proofKind: KnowledgeEvidenceKind in [.suggestion, .execution] {
                let proof = KnowledgeEvidence(id: latest.id, conversationID: latest.conversationID, kind: proofKind, date: latest.date)
                var state = KnowledgeState()
                XCTAssertThrowsError(try PersonalSkillTool.validatePersonalWrite(proposal, evidence: [proof], sources: [old, latest]))
                XCTAssertThrowsError(try state.applyVerified(proposal, evidence: [proof], operationID: "bad"))
                XCTAssertTrue(state.items.isEmpty); XCTAssertTrue(state.notices.isEmpty)
            }
        }
    }

    func testPersonalWriteVerifierFailureLeavesStateUntouched() async throws {
        let source = KnowledgeSource(id: UUID(), conversationID: UUID(), role: "user", text: "也许这样更好？", date: Date())
        let args = try arguments(["action": "save", "kind": "memory", "name": "决定", "description": "不明确", "body": "以后都这样做"])
        let state = KnowledgeState()
        let proposal = try PersonalSkillTool.writeProposal(args, state: state, loaded: [:], sources: [source])
        for judgment in [KnowledgeJudgment(accepted: false, reason: "含糊", evidence: []),
                         KnowledgeJudgment(accepted: true, reason: "", evidence: [.init(sourceID: source.id, kind: .preference, quote: "不存在的用户原文")])] {
            let client = StubClient(.text(try KnowledgeRules.payload(judgment)))
            do { _ = try await PersonalLearningAgent(client: client).verify(proposal: proposal, sources: [source]); XCTFail("Unverified input must not reach persistence") }
            catch { XCTAssertTrue(error is KnowledgeError) }
        }
        XCTAssertTrue(state.items.isEmpty)
    }

    func testSharedWriterRejectsMismatchedCategoryAndSuppressedPersonalSource() throws {
        var state = KnowledgeState(); let proof = evidence(.preference)
        let proposal = KnowledgeProposal(action: "save", kind: .profile, content: .init(name: "姓名", description: "用户姓名", body: "张爱民"), sourceIDs: [proof.id])
        let id = try state.applyVerified(proposal, evidence: [proof], operationID: "first")
        let bad = KnowledgeProposal(action: "patch", kind: .memory, skillID: id, expectedRevision: 1,
            patches: [.init(field: .body, oldString: "张爱民", newString: "爱民")], sourceIDs: [proof.id])
        let before = state
        XCTAssertThrowsError(try state.applyVerified(bad, evidence: [proof], operationID: "wrong-kind"))
        XCTAssertEqual(state, before)
        try state.undo(noticeID: state.notices[0].id)
        XCTAssertThrowsError(try state.applyVerified(proposal, evidence: [proof], operationID: "background-recreate"))
        XCTAssertTrue(state.items.isEmpty)
    }

    func testSaveCannotOverwriteExistingPersonalItemOrReviveArchivedItem() throws {
        var state = KnowledgeState(); let proof = evidence(.preference)
        var proposal = KnowledgeProposal(action: "save", kind: .profile, content: .init(name: "姓名", description: "用户姓名", body: "张爱民"), sourceIDs: [proof.id])
        let id = try state.applyVerified(proposal, evidence: [proof], operationID: "first")
        try state.setStatus(.archived, id: id, expected: 1)
        let noticeCount = state.notices.count
        XCTAssertEqual(try state.applyVerified(proposal, evidence: [proof], operationID: "duplicate"), id)
        XCTAssertEqual(state.items[0].status, .archived); XCTAssertEqual(state.notices.count, noticeCount)
        proposal.content?.body = "爱民"
        let before = state
        XCTAssertThrowsError(try state.applyVerified(proposal, evidence: [proof], operationID: "overwrite"))
        XCTAssertEqual(state, before)
    }

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

    func testProfileFieldSaveIsIdempotentButStillRequiresEvidence() throws {
        var state = KnowledgeState()
        let value = KnowledgeContent(name: "姓名", description: "用户自述", body: "小林", profileField: .name)
        let proof = evidence(.preference)
        let id = try state.save(kind: .profile, content: value, evidence: [proof])
        XCTAssertEqual(try state.save(kind: .profile, content: value, evidence: [proof]), id)
        XCTAssertEqual(state.items.count, 1); XCTAssertEqual(state.notices.count, 1)
        XCTAssertEqual(state.items[0].revision, 1)
        XCTAssertThrowsError(try state.save(kind: .profile, content: value, evidence: []))
        state.suppressedSources.append(proof.id)
        XCTAssertThrowsError(try state.save(kind: .profile, content: value, evidence: [proof]))
    }
    func testProfileChangeUsesPatchAndPreservesOtherFields() throws {
        var state = KnowledgeState()
        let name = try state.save(kind: .profile, content: .init(name: "姓名", description: "用户自述", body: "小林", profileField: .name), evidence: [evidence()])
        let pref = try state.save(kind: .profile, content: .init(name: "我的偏好", description: "沟通偏好", body: "先讲结论", profileField: .preferences), evidence: [evidence()])
        XCTAssertThrowsError(try state.save(kind: .profile, content: .init(name: "另一个姓名", description: "用户自述", body: "小张", profileField: .name), evidence: [evidence()]))
        try state.patch(id: pref, expected: 1, operationID: "profile-patch", patches: [.init(field: .body, oldString: "先讲结论", newString: "先讲结论，再解释理由")], evidence: [evidence()])
        XCTAssertEqual(state.items.first { $0.id == name }?.content.body, "小林")
        XCTAssertEqual(state.items.first { $0.id == pref }?.content.profileField, .preferences)
        try state.undo(noticeID: state.notices.last!.id)
        XCTAssertEqual(state.items.first { $0.id == pref }?.content.body, "先讲结论")
    }
    func testLegacyProfileMigrationPreservesUnknownAmbiguousAndInvalidTimezone() throws {
        var state = KnowledgeState()
        let name = KnowledgeItem(kind: .profile, content: .init(name: "姓名", description: "姓名", body: "小林"))
        let first = KnowledgeItem(kind: .profile, content: .init(name: "偏好", description: "旧偏好", body: "简洁"))
        let second = KnowledgeItem(kind: .profile, content: .init(name: "回答偏好", description: "旧偏好", body: "详细"))
        let unknown = KnowledgeItem(kind: .profile, content: .init(name: "其他背景条目", description: "旧条目", body: "保留原文"))
        let timezone = KnowledgeItem(kind: .profile, content: .init(name: "时区", description: "旧时区", body: "可能在中国"))
        state.items = [name, first, second, unknown, timezone]
        let migrated = PersonalProfileField.migrating(state)
        XCTAssertEqual(migrated.items.map(\.id), state.items.map(\.id))
        XCTAssertEqual(migrated.items.map { $0.content.body }, state.items.map { $0.content.body })
        XCTAssertEqual(migrated.items[0].content.profileField, .name)
        XCTAssertTrue(migrated.items.dropFirst().allSatisfy { $0.content.profileField == nil })
        XCTAssertEqual(PersonalProfileField.migrating(migrated), migrated)
        _ = try KnowledgeArchive.read(JSONEncoder().encode(KnowledgeArchive(state: migrated, account: "local")))
    }
    func testProfileArchiveCarriesStableFieldsAndReadableProjection() throws {
        var state = KnowledgeState()
        _ = try state.save(kind: .profile, content: .init(name: "称呼", description: "用户选择", body: "小林", profileField: .nickname), evidence: [evidence()])
        let archive = try KnowledgeArchive.read(JSONEncoder().encode(KnowledgeArchive(state: state, account: "local")))
        XCTAssertTrue(archive.userMarkdown.contains("## 称呼\n小林"))
        let imported = try archive.applying(to: KnowledgeState(), replaceIDs: [])
        XCTAssertEqual(imported.items.first?.content.profileField, .nickname)
        XCTAssertEqual(imported.items.first?.content.body, "小林")
    }
    func testProfileTimezoneAndCategoryAreValidated() throws {
        try KnowledgeRules.validate(.init(name: "时区", description: "本人提供", body: "Asia/Shanghai", profileField: .timezone), kind: .profile)
        XCTAssertThrowsError(try KnowledgeRules.validate(.init(name: "时区", description: "本人提供", body: "somewhere", profileField: .timezone), kind: .profile))
        XCTAssertThrowsError(try KnowledgeRules.validate(.init(name: "姓名", description: "本人提供", body: "小林", profileField: .name), kind: .memory))
    }

}
