import Foundation
import SwiftData

/// 记录闭环：对话式记录流的宿主。
/// 用户每说一句 → 追加一条消息 → 解析结果以可编辑卡片内联出现 → 确认后入库。
/// 解析失败尝试留存 RawNote；写入失败保留可重试草稿，不误报持久化成功。
@MainActor
final class LoggingViewModel: ObservableObject {

    /// 对话流里的一条消息
    struct LogTurn: Identifiable {

        enum Kind {
            case user       // 用户输入
            case assistant  // 解析结果（可编辑卡片）
            case failure    // 失败与降级说明
        }

        let id = UUID()
        var kind: Kind
        var text: String = ""
        var drafts: [LogDraft] = []
        /// 已保存条数（nil 表示尚未保存）
        var savedCount: Int?
        /// 用户这条消息附带的照片 —— 气泡里要显示缩略图，所以留着原始数据
        var photoData: Data?

        var isSaved: Bool { savedCount != nil }
        var hasPhoto: Bool { photoData != nil }
    }

    @Published var turns: [LogTurn] = []
    @Published var inputText: String = ""
    @Published var isParsing = false

    private let settings: LLMSettings
    private let injectedClient: LLMClient?
    private let persist: (ModelContext) throws -> Void
    private var parsingGeneration = UUID()
    private var parsingTask: Task<[LogDraft], Error>?

    init(settings: LLMSettings = .shared, client: LLMClient? = nil,
         persist: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.settings = settings
        self.injectedClient = client
        self.persist = persist
    }

    var isConfigured: Bool { injectedClient != nil || settings.isConfigured }

    var canSubmit: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isParsing
    }

    var hasTurns: Bool { !turns.isEmpty }

    /// 首页点发送后立即开始处理。先消费请求，弹窗重现时不会重复发送。
    func submitHomeInput(from state: AppState, context: ModelContext) async {
        guard !isParsing else { return }
        let text = state.pendingLogText
        let photo = state.pendingLogPhoto
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || photo != nil else { return }
        state.pendingLogText = ""
        state.pendingLogPhoto = nil
        inputText = text
        await submit(context: context, photo: photo)
    }

    // MARK: - 提交

    /// 发送一轮：只发文字、只发照片，或文字 + 照片（文字作为照片的补充说明）
    func submit(context: ModelContext, photo: Data? = nil) async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isParsing, !text.isEmpty || photo != nil else { return }

        turns.append(LogTurn(kind: .user, text: text, photoData: photo))
        inputText = ""

        guard isConfigured else {
            preserveInput(text, photo: photo, reason: "云端服务尚未就绪",
                          message: "云端服务暂不可用，重新登录或服务恢复后可以重新处理。", context: context)
            return
        }

        let generation = UUID()
        parsingGeneration = generation
        isParsing = true
        defer {
            if parsingGeneration == generation {
                isParsing = false
                parsingTask = nil
            }
        }

        do {
            let client = try injectedClient ?? settings.makeRecordingClient()
            let history = Self.historyTurns(from: Array(turns.dropLast()))
            let task = Task { @MainActor in
                try await self.parseDrafts(text: text, photo: photo, history: history, client: client)
            }
            parsingTask = task
            let drafts = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: { task.cancel() }
            guard parsingGeneration == generation else { return }
            try Task.checkCancellation()
            guard !drafts.isEmpty else { throw AgentError.emptyResult }
            turns.append(LogTurn(kind: .assistant, drafts: drafts))
        } catch {
            guard parsingGeneration == generation else { return }
            appendFailure(for: error, text: text, photo: photo, context: context)
        }
    }

    private func parseDrafts(text: String, photo: Data?, history: [CoachTurn], client: LLMClient) async throws -> [LogDraft] {
        try Task.checkCancellation()
        let drafts: [LogDraft]
        if let photo {
            guard let base64 = ImageDownscaler.jpegBase64(from: photo) else {
                throw LLMError.decoding("图片无法读取，请换一张或改用文字记录。")
            }
            if settings.useLocalModel {
                let records = try await ParserAgent(client: client).parse(text, imageBase64JPEG: base64)
                drafts = records.compactMap { record in
                    guard var draft = LogDraft.from(record) else { return nil }
                    if draft.kind == .meal { draft.meal.photoData = ImageDownscaler.jpegData(from: photo) }
                    return draft
                }
            } else {
                drafts = try await visionDrafts(photo: photo, base64: base64, note: text, client: client)
            }
        } else {
            // 不含本轮：本轮输入单独作为最后一条 user 消息
            let records = try await ParserAgent(client: client).parse(text, history: history)
            drafts = records.compactMap { LogDraft.from($0) }
        }

        try Task.checkCancellation()
        return drafts
    }

    /// 照片识别：把用户附带的文字作为补充说明一起发过去
    private func visionDrafts(photo: Data, base64: String, note: String, client: LLMClient) async throws -> [LogDraft] {
        let meal = try await VisionAgent(client: client).analyzeMeal(
            imageBase64JPEG: base64,
            note: note.isEmpty ? nil : note
        )

        var draft = LogDraft(kind: .meal)
        draft.meal = MealDraft(from: meal)
        draft.meal.photoData = ImageDownscaler.jpegData(from: photo)
        return [draft]
    }

    /// 失败处理：文字和附件均留存为 RawNote，保留重试入口。
    private func appendFailure(for error: Error, text: String, photo: Data?, context: ModelContext) {
        if let photo {
            let message = (error as? LLMError).map(Self.photoFailureMessage(for:))
                ?? "照片识别失败：\(error.localizedDescription)"
            preserveInput(text, photo: photo, reason: error.localizedDescription, message: message, context: context)
            return
        }

        preserveInput(text, photo: nil, reason: error.localizedDescription,
                      message: "没能解析这句：\(error.localizedDescription)", context: context)
    }

    private func preserveInput(_ text: String, photo: Data?, reason: String, message: String, context: ModelContext) {
        do {
            try RecordImporter.storeRawNote(text, failureReason: reason, to: context, photoData: photo, persist: persist)
            turns.append(LogTurn(kind: .failure, text: message + "\n原输入已保存在待归类记录。"))
        } catch {
            turns.append(LogTurn(kind: .failure, text: message + "\n本机保存失败，尚未保存。原文与照片保留在当前对话和下方草稿中，请保留此页并重试保存。"))
            var draft = LogDraft(kind: .note)
            draft.note = NoteDraft(text: text.isEmpty && photo != nil ? "待整理的照片" : text,
                                   photoData: photo, failureReason: reason)
            turns.append(LogTurn(kind: .assistant, drafts: [draft]))
        }
    }

    /// 把照片识别的常见失败翻译成可执行的提示
    static func photoFailureMessage(for error: LLMError) -> String {
        switch error {
        case .http(let status, let body):
            switch status {
            case 400, 404, 415, 422:
                return "当前模型似乎不支持图片输入（HTTP \(status)）。请在「设置 → 模型」换用支持视觉的模型，或改用文字记录。\n服务返回：\(body)"
            case 401, 403:
                return "登录或服务权限异常（HTTP \(status)）。请重新登录，或联系管理员。"
            case 429:
                return "请求过于频繁或额度不足（HTTP 429），稍后再试。"
            default:
                return "服务返回错误（HTTP \(status)）：\(body)"
            }
        case .network(let message):
            return "网络不可用，照片没有上传。稍后重试，或改用文字记录。\n\(message)"
        default:
            return "照片识别失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 手动记录

    func addManualDraft(_ kind: LogDraft.Kind) {
        turns.append(LogTurn(kind: .assistant, drafts: [LogDraft(kind: kind)]))
    }

    // MARK: - 保存

    /// 保存某一轮的全部草稿
    @discardableResult
    func save(turnID: UUID, context: ModelContext) -> Int {
        guard let index = turns.firstIndex(where: { $0.id == turnID }) else { return 0 }

        var turn = turns[index]
        guard !turn.isSaved else { return 0 }
        let inputs = turn.drafts.filter { !$0.isEmpty }.map { draft in
            RecordImporter.Input(record: draft.toParsedRecord(),
                                 photoData: draft.kind == .meal ? draft.meal.photoData : draft.note.photoData,
                                 failureReason: draft.kind == .note ? draft.note.failureReason : "")
        }
        guard !inputs.isEmpty else { return 0 }
        do {
            let summary = try RecordImporter.applyBatch(inputs, to: context, persist: persist)
            guard summary.total > 0 else { return 0 }
            turn.savedCount = summary.total
            turns[index] = turn
            return summary.total
        } catch {
            turns.append(LogTurn(kind: .failure, text: "保存失败，本轮记录尚未保存。全部草稿与照片已保留，请重试保存。"))
            return 0
        }
    }

    func removeTurn(_ id: UUID) {
        turns.removeAll { $0.id == id }
    }

    func reset() {
        parsingGeneration = UUID()
        parsingTask?.cancel()
        parsingTask = nil
        turns = []
        inputText = ""
        isParsing = false
    }

    // MARK: - 对话历史（供多轮解析）

    /// 把对话流压缩成 LLM 上下文：用户原话 + 已确认记录的摘要
    static func historyTurns(from turns: [LogTurn]) -> [CoachTurn] {
        turns.compactMap { turn in
            switch turn.kind {
            case .user:
                return CoachTurn(role: .user, content: turn.text)

            case .assistant:
                let summary = turn.drafts.map(summaryLine(for:)).filter { !$0.isEmpty }.joined(separator: "；")
                guard !summary.isEmpty else { return nil }
                return CoachTurn(role: .assistant, content: "上一轮已解析：" + summary)

            case .failure:
                return nil
            }
        }
    }

    /// 单条草稿的紧凑摘要（用于上下文）
    static func summaryLine(for draft: LogDraft) -> String {
        switch draft.kind {
        case .workout:
            let exercises = draft.workout.exercises.compactMap { exercise -> String? in
                let name = exercise.name.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return nil }

                var text = name
                if let weight = ParsedInput.double(exercise.weightText) {
                    text += " \(Format.number(weight, decimals: weight == weight.rounded() ? 0 : 1))kg"
                }
                if let reps = ParsedInput.int(exercise.repsText) { text += " ×\(reps)次" }
                if let sets = ParsedInput.int(exercise.setsText) { text += " \(sets)组" }
                return text
            }
            return exercises.isEmpty ? "" : "训练 " + exercises.joined(separator: "、")

        case .meal:
            let names = draft.meal.items.map(\.name).filter { !$0.isEmpty }
            return names.isEmpty ? "" : "饮食 " + names.joined(separator: "、")

        case .metric:
            return "\(draft.metric.kind.displayName) \(draft.metric.valueText)\(draft.metric.kind.unit)"

        case .note:
            return draft.note.text.isEmpty ? "" : "笔记：" + draft.note.text
        }
    }
}
