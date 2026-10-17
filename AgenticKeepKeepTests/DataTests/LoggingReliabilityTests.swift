import XCTest
import SwiftData
@testable import AgenticKeepKeep

private enum LoggingWriteFailure: Error { case diskFull }

/// Deliberately completes after cancellation to exercise stale provider responses.
private actor DelayedLoggingClient: LLMClient {
    nonisolated let config = LLMClientConfig(baseURL: "https://mock.local/v1", apiKey: "test", model: "test")
    private var requests = 0
    private var pending: [Int: CheckedContinuation<LLMResponse, Error>] = [:]
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        try await withCheckedThrowingContinuation { continuation in
            pending[requests] = continuation
            requests += 1
            let ready = waiters.filter { $0.0 <= requests }
            waiters.removeAll { $0.0 <= requests }
            ready.forEach { $0.1.resume() }
        }
    }

    func waitForRequests(_ count: Int) async {
        if requests >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    func finish(_ index: Int, result: Result<LLMResponse, Error>) {
        pending.removeValue(forKey: index)?.resume(with: result)
    }
}

@MainActor
final class LoggingReliabilityTests: XCTestCase {
    private func context() throws -> ModelContext { ModelContext(try AppModelContainer.inMemory()) }

    private func meal(_ name: String, photo: Data) -> LogDraft {
        var draft = LogDraft(kind: .meal)
        draft.meal = MealDraft(from: ParsedMeal(items: [ParsedFood(name: name, calories: 100)]))
        draft.meal.photoData = photo
        return draft
    }

    func testFallbackWriteFailureThrowsAndLeavesNoAutosaveInsert() throws {
        let context = try context()
        XCTAssertThrowsError(try RecordImporter.storeRawNote("午饭", failureReason: "网络失败", to: context,
                                                            photoData: Data([1]), persist: { _ in throw LoggingWriteFailure.diskFull }))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RawNote>()), 0)
        XCTAssertFalse(context.hasChanges)
    }

    func testBatchFailureRollsBackRecordsAndPreservesUnrelatedEdits() throws {
        let context = try context()
        context.insert(RawNote(text: "已有的未保存修改"))
        let inputs = [RecordImporter.Input(record: .init(kind: .meal, meal: .init(items: [ParsedFood(name: "米饭")]))),
                      RecordImporter.Input(record: .init(kind: .metric, metric: .init(kind: "weight", value: 70)))]
        XCTAssertThrowsError(try RecordImporter.applyBatch(inputs, to: context, persist: { _ in throw LoggingWriteFailure.diskFull }))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MealEntry>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FoodItem>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BodyMetric>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RawNote>()), 1)
        XCTAssertEqual(try RecordImporter.applyBatch(inputs, to: context).total, 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MealEntry>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BodyMetric>()), 1)
    }

    func testTurnRetryIsAtomicAndPhotosStayWithTheirOwnMeals() throws {
        let context = try context()
        // A later date on another meal must not affect attachment identity.
        let existing = MealEntry(date: .now, note: "原餐食")
        existing.createdAt = Date.distantFuture
        context.insert(existing)
        try context.save()
        var fail = true
        let model = LoggingViewModel(persist: { context in
            if fail { throw LoggingWriteFailure.diskFull }
            try context.save()
        })
        let turn = LoggingViewModel.LogTurn(kind: .assistant, drafts: [meal("米饭", photo: Data([1])), meal("鸡肉", photo: Data([2]))])
        model.turns = [turn]
        XCTAssertEqual(model.save(turnID: turn.id, context: context), 0)
        XCTAssertNil(model.turns.first?.savedCount)
        XCTAssertEqual(model.turns.first?.drafts.count, 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MealEntry>()), 1)
        fail = false
        XCTAssertEqual(model.save(turnID: turn.id, context: context), 2)
        XCTAssertEqual(model.save(turnID: turn.id, context: context), 0)
        let meals = try context.fetch(FetchDescriptor<MealEntry>())
        XCTAssertEqual(meals.count, 3)
        XCTAssertNil(existing.photoData)
        for (name, photo) in [("米饭", Data([1])), ("鸡肉", Data([2]))] {
            let entry = try XCTUnwrap(meals.first { $0.items.first?.name == name })
            XCTAssertEqual(entry.photoData, photo)
            XCTAssertTrue(entry.hasPhoto)
            XCTAssertEqual(entry.source, .photo)
        }
    }

    func testFailedFallbackKeepsPhotoAndTextAsRetryableNoteDraft() async throws {
        let context = try context()
        var fail = true
        let model = LoggingViewModel(client: MockLLMClient(error: LLMError.network("离线")), persist: { context in
            if fail { throw LoggingWriteFailure.diskFull }
            try context.save()
        })
        let photo = Data([1, 2, 3]) // Invalid image also uses the same fallback path.
        model.inputText = "午饭的原文"
        await model.submit(context: context, photo: photo)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RawNote>()), 0)
        XCTAssertTrue(model.turns.contains { $0.kind == .failure && $0.text.contains("尚未保存") })
        XCTAssertFalse(model.turns.contains { $0.kind == .failure && $0.text.contains("已保存在待归类") })
        let turn = try XCTUnwrap(model.turns.last)
        XCTAssertEqual(turn.drafts.first?.note.text, "午饭的原文")
        XCTAssertEqual(turn.drafts.first?.note.photoData, photo)
        fail = false
        XCTAssertEqual(model.save(turnID: turn.id, context: context), 1)
        let note = try XCTUnwrap(context.fetch(FetchDescriptor<RawNote>()).first)
        XCTAssertEqual(note.text, "午饭的原文")
        XCTAssertEqual(note.photoData, photo)
        XCTAssertEqual(model.save(turnID: turn.id, context: context), 0)
    }

    func testResetRejectsLateSuccessAndDoesNotClearNewBusyState() async throws {
        let context = try context()
        let client = DelayedLoggingClient()
        let model = LoggingViewModel(client: client)
        model.inputText = "旧输入"
        let old = Task { await model.submit(context: context) }
        await client.waitForRequests(1)
        model.reset()
        model.inputText = "新输入"
        let current = Task { await model.submit(context: context) }
        await client.waitForRequests(2)
        await client.finish(0, result: .success(LLMResponse(content: #"{"records":[{"type":"note","note":"旧结果"}]}"#)))
        await old.value
        XCTAssertTrue(model.isParsing)
        XCTAssertEqual(model.turns.count, 1)
        XCTAssertEqual(model.turns.first?.text, "新输入")
        await client.finish(1, result: .success(LLMResponse(content: #"{"records":[{"type":"note","note":"新结果"}]}"#)))
        await current.value
        XCTAssertFalse(model.isParsing)
        XCTAssertEqual(model.turns.last?.drafts.first?.note.text, "新结果")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RawNote>()), 0)
    }

    func testResetRejectsLateFailureWithoutPersistingClearedInput() async throws {
        let context = try context()
        let client = DelayedLoggingClient()
        let model = LoggingViewModel(client: client)
        model.inputText = "主动清空的输入"
        let task = Task { await model.submit(context: context) }
        await client.waitForRequests(1)
        model.reset()
        await client.finish(0, result: .failure(LLMError.network("晚到的错误")))
        await task.value
        XCTAssertTrue(model.turns.isEmpty)
        XCTAssertFalse(model.isParsing)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RawNote>()), 0)
    }

    func testBusyHomeSubmissionDoesNotConsumeTheNextInput() async throws {
        let context = try context()
        let client = DelayedLoggingClient()
        let model = LoggingViewModel(client: client)
        model.inputText = "正在解析"
        let task = Task { await model.submit(context: context) }
        await client.waitForRequests(1)
        let state = AppState()
        state.pendingLogText = "下一条"
        state.pendingLogPhoto = Data([3])
        await model.submitHomeInput(from: state, context: context)
        XCTAssertEqual(state.pendingLogText, "下一条")
        XCTAssertEqual(state.pendingLogPhoto, Data([3]))
        model.reset()
        await client.finish(0, result: .failure(CancellationError()))
        await task.value
    }
}
