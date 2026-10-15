import AVFoundation
import SwiftUI
import UIKit
import SwiftData

/// 与 AI 教练对话：澄清需求 → function call 生成计划 → 确认后写入课程表
struct CoachChatView: View {
    var initialMessage: String = ""
    var onMessageSubmitted: (() -> Void)? = nil
    @State private var consumedInitialMessage = false

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var dictation = VoiceInput()
    @StateObject private var realtime = RealtimeCall()
    @State private var showsRealtime = false

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @Query(sort: [SortDescriptor(\ChatMessage.date)])
    private var messages: [ChatMessage]

    @State private var inputText = ""
    @State private var confirmsClearHistory = false
    @State private var showsDataUsage = false
    @FocusState private var isInputFocused: Bool
    @State private var isSending = false
    @State private var isPreparingContext = false
    @StateObject private var browser = LocalBrowserSession()
    @StateObject private var memoryStore = CoachMemoryStore()
    @State private var errorText: String?
    /// 本次对话注入教练的个人概况（展示给用户，保持透明）
    @State private var profileText = ""

    // 流式渲染
    @State private var toolActivities: [CoachToolActivity] = []
    @State private var streamingText = ""
    @State private var streamingReasoning = ""
    @State private var streamTask: Task<Void, Never>?

    private static let streamingAnchor = "keepkeep.coach.streaming"
    private static let bottomAnchor = "keepkeep.coach.bottom"

    @ObservedObject private var settings = LLMSettings.shared
    @AppStorage(MiloPersona.nameKey) private var miloName = "Milo"
    private var displayName: String { MiloPersona(name: miloName).name }

    var body: some View {
        NavigationStack {
            Group {
                if messages.isEmpty {
                    GeometryReader { geometry in
                        ScrollView {
                            intro
                                .frame(maxWidth: .infinity, minHeight: max(0, geometry.size.height - 32), alignment: .bottomLeading)
                                .padding(.vertical, Theme.Spacing.l)
                        }
                    }
                } else {
                    chatList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            // 手势只作用于聊天区域，不覆盖下方输入栏；保留消息内按钮与链接操作。
            .simultaneousGesture(TapGesture().onEnded { isInputFocused = false })
            .scrollDismissesKeyboard(.immediately)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if !isInputFocused, let pending = pendingPlan, let draft = decodedPlan(pending) {
                        VStack(spacing: Theme.Spacing.s) {
                            Button("加入课程表") { accept(plan: draft, message: pending) }
                                .buttonStyle(PrimaryButtonStyle())
                                .disabled(draft.days.isEmpty)
                        }
                        .padding(Theme.Spacing.l)
                        .background(Theme.conversationCanvas)
                    }
                    inputBar
                }
                .background(Theme.conversationCanvas)
            }
            .background(Theme.conversationCanvas)
            .navigationTitle(displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.conversationCanvas, for: .navigationBar)
            .confirmationDialog("清空对话？", isPresented: $confirmsClearHistory, titleVisibility: .visible) {
                Button("清空对话", role: .destructive) { clearHistory() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将删除聊天历史，已保存的课程表和训练记录会保留。")
            }
            .alert("数据使用说明", isPresented: $showsDataUsage) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(profileText.isEmpty ? "按需查询本机记录的聚合数据，未默认加载全部历史。" : profileText)
            }
            .task {
                loadProfile()
                if !consumedInitialMessage {
                    consumedInitialMessage = true
                    if !initialMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        inputText = initialMessage
                        startSend()
                    }
                }
            }
            .environment(\.openURL, OpenURLAction { url in
                guard settings.useLocalModel else { return .systemAction }
                guard LocalBrowserPolicy.allows(url) else {
                    appState.showToast("此验证版本暂不支持该来源的内置阅读")
                    return .handled
                }
                Task { try? await browser.preview(url) }
                return .handled
            })
            .sheet(isPresented: $browser.isPresented) { LocalBrowserView(browser: browser) }
            .onDisappear { dictation.finish(); realtime.end(); stopStreaming(); _ = memoryStore.begin(); browser.cancel() }
            .onChange(of: dictation.text) { _, text in inputText = text }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { dictation.finish(); realtime.pause() }
            }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { note in
                if let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                   type == AVAudioSession.InterruptionType.began.rawValue { dictation.finish(); realtime.pause() }
            }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { note in
                if let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                   reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { dictation.finish(); realtime.pause() }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        MiloAvatar(size: 36)
                        Text(displayName).font(.headline)
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.secondaryLabel)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("关闭 \(displayName)")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let pending = pendingPlan {
                            Button("不采用这份计划") { reject(message: pending) }
                        }
                        Button("数据使用说明", systemImage: "chart.bar.doc.horizontal") { showsDataUsage = true }
                        Button("清空对话", role: .destructive) { confirmsClearHistory = true }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(Theme.secondaryLabel)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("更多对话操作")
                }
            }
        }
        .accessibilityHidden(showsRealtime)
        .overlay {
            if showsRealtime {
                RealtimeCallView(call: realtime, name: displayName, onEnd: {
                    realtime.end(); showsRealtime = false
                }, onReview: { request in
                    realtime.end(); showsRealtime = false
                    guard !isSending else { return }
                    isSending = true
                    streamTask = Task { await send(suppliedText: request) }
                })

            }
        }
    }

    private func openRealtime() {
        dictation.finish()
        isInputFocused = false
        realtime.open(history: messages.suffix(12).map { (role: $0.role.rawValue, text: $0.content) })
        realtime.onText = { role, text in
            context.insert(ChatMessage(role: role == "user" ? .user : .assistant, content: text))
            do { try context.save() }
            catch { appState.showToast("通话文字保存失败，请检查存储空间") }
        }
        showsRealtime = true
    }

    private var pendingPlan: ChatMessage? {
        guard !isSending else { return nil }
        return messages.last { $0.hasPendingPlan && decodedPlan($0) != nil }
    }

    private func decodedPlan(_ message: ChatMessage) -> PlanDraft? {
        guard let json = message.pendingPlanJSON, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PlanDraft.self, from: data)
    }

    // MARK: - 空态

    /// 空态给的是**能直接点的示例**，不是一句「暂无对话」（FR15.6）
    private static let exampleQuestions = [
        "今天适合练什么？",
        "帮我调整本周课程表",
        "看看我最近的恢复情况",
    ]

    private var intro: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            MiloAvatar(size: 64)
            Text("今天，从哪里开始？")
                .font(Theme.Font.largeTitle)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                ForEach(Self.exampleQuestions, id: \.self) { question in
                    Button {
                        inputText = question
                        Haptics.tap()
                    } label: {
                        Text(question)
                            .font(Theme.Font.body)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, Theme.Spacing.l)
                            .padding(.vertical, Theme.Spacing.m)
                            .background(Theme.cardNested, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("填入输入框，确认后发送")
                }
            }
            if let errorText {
                Text(errorText)
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.danger)
            } else if !settings.isConfigured {
                Text(settings.useLocalModel ? "请先在「设置 → 离线模式」完成模型下载" : "请确认已登录；服务不可用时请联系管理员")
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.l)
    }

    // MARK: - 对话

    private var chatList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    ForEach(messages) { message in
                        messageView(message)
                            .id(message.id)
                    }

                    if isSending {
                        streamingBubble.id(Self.streamingAnchor)
                    }

                    if let errorText {
                        Text(errorText)
                            .font(Theme.Font.footnote)
                            .foregroundStyle(Theme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                            .id("error")
                    }
                    Color.clear.frame(height: 1).id(Self.bottomAnchor)
                }
                .padding(Theme.Spacing.l)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: messages.count, initial: true) {
                scrollToBottom(proxy)
            }
            .onChange(of: isSending) {
                scrollToBottom(proxy)
            }
            .onChange(of: streamingText) {
                scrollToBottom(proxy)
            }
            .onChange(of: toolActivities) {
                scrollToBottom(proxy)
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }

    @ViewBuilder
    private func messageView(_ message: ChatMessage) -> some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 40)
                Text(message.content)
                    .font(Theme.Font.body)
                    .textSelection(.enabled)
                    .padding(Theme.Spacing.m)
                    .background(Theme.cardNested, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                let activities = CoachToolActivity.decode(message.toolActivityJSON)
                if activities.contains(where: { settings.thinkingEnabled || $0.kind != "thinking" }) {
                    CoachToolActivityView(activities: activities, showThinking: settings.thinkingEnabled)
                }
                if settings.thinkingEnabled, !activities.contains(where: { $0.kind == "thinking" }), let reasoning = message.reasoningText, !reasoning.isEmpty {
                    ThinkingBlock(text: reasoning, isStreaming: false, defaultExpanded: false)
                }

                if !message.content.isEmpty {
                    MarkdownText(content: message.content, justifiedParagraphs: true)
                        .lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !message.content.isEmpty {
                    HStack(spacing: 2) {
                        Button {
                            UIPasteboard.general.string = message.content
                            appState.showToast("已复制")
                        } label: {
                            Image(systemName: "doc.on.doc").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("复制回复")
                        ShareLink(item: message.content) {
                            Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("分享回复")
                    }
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryLabel)
                    .buttonStyle(.plain)
                }

                if message.pendingPlanJSON != nil && message.planDecisionRaw != "rejected" {
                    PlanDraftCard(message: message, showsActions: message.id != pendingPlan?.id) { plan in
                        accept(plan: plan, message: message)
                    } onReject: {
                        reject(message: message)
                    }
                }

                if message.pendingAdjustmentJSON != nil && message.adjustmentDecisionRaw != "rejected" {
                    AdjustmentDraftCard(message: message) { draft in
                        apply(adjustment: draft, message: message)
                    } onReject: {
                        reject(message: message)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 输入

    private var inputBar: some View {
        VStack(spacing: 6) {
            if dictation.active {
                HStack {
                    Text(dictation.notice).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("取消") { dictation.finish(cancel: true) }
                }.padding(.horizontal, Theme.Spacing.l)
            } else if !dictation.notice.isEmpty {
                Text(dictation.notice).font(.caption).foregroundStyle(.secondary).padding(.horizontal, Theme.Spacing.l)
            }
        HStack(spacing: Theme.Spacing.s) {
            TextField("聊聊训练、饮食或恢复…", text: $inputText, axis: .vertical)
                .focused($isInputFocused)
                .disabled(dictation.active)
                .lineLimit(1...4)
                .font(Theme.Font.body)
                .padding(.leading, Theme.Spacing.m)
                .padding(.vertical, Theme.Spacing.m)

            // 输入栏内保留独立入口，不依赖系统键盘工具栏是否成功显示。
            if isInputFocused {
                Button {
                    isInputFocused = false
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 20))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondaryLabel)
                .accessibilityLabel("收起键盘")
                .accessibilityHint("保留已输入的文字")
                .accessibilityIdentifier("coach.dismissKeyboard")
            }

            Button {
                isInputFocused = false
                if dictation.active { dictation.finish() } else { dictation.begin(draft: inputText) }
            } label: {
                Image(systemName: dictation.active ? "stop.circle.fill" : "mic.fill").font(.title3).frame(width: 44, height: 44)
            }
            .disabled(isSending)
            .foregroundStyle(dictation.active ? Color.red : Theme.secondaryLabel)
            .accessibilityLabel(dictation.active ? "停止语音输入" : "开始语音输入")
            .accessibilityHint("只转成文字，确认后手动发送")
            .accessibilityIdentifier("coach.voiceInput")
            Button(action: openRealtime) {
                Image(systemName: "phone.fill").font(.title3).frame(width: 44, height: 44)
            }
            .disabled(isSending || dictation.active)
            .accessibilityLabel("实时通话")
            .accessibilityIdentifier("coach.realtimeCall")

            ChatSendButton(
                isBusy: isSending,
                canSend: canSend,
                onSend: startSend,
                onStop: stopStreaming
            )
        }
        .padding(Theme.Spacing.xs)
        .background(Theme.cardNested, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.s)
        .background(Theme.conversationCanvas)
        }
    }

    private var canSend: Bool {
        !isSending && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - 动作

    private func startSend() {
        guard !isSending else { return }
        // 录音中也能直接发：取走已识别的文字并结束这次收音，不用先点一次停下
        if dictation.active { inputText = dictation.finishForSend() }
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isInputFocused = false
        isSending = true
        streamTask = Task { await send() }
    }

    private func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
    }

    private func send(suppliedText: String? = nil) async {
        let text = (suppliedText ?? inputText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { isSending = false; return }

        guard settings.isConfigured else {
            errorText = settings.useLocalModel ? "请先在「设置 → 离线模式」完成模型下载" : "请先登录并确认云端服务已就绪"
            isSending = false
            return
        }

        if suppliedText == nil { onMessageSubmitted?() }
        let generation = memoryStore.begin()
        let history = CoachHistoryBuilder.turns(messages)
        let memory = memoryStore.load(messages)

        if suppliedText == nil { inputText = "" }
        errorText = nil
        isSending = true
        streamingText = ""
        streamingReasoning = ""
        toolActivities = []

        let userMessage = ChatMessage(role: .user, content: text)
        context.insert(userMessage)
        do { try context.save() }
        catch {
            context.delete(userMessage)
            if suppliedText == nil { inputText = text }
            isSending = false
            errorText = "保存消息失败，请重试"
            return
        }

        var accumulatedText = ""
        var accumulatedReasoning = ""
        var reply: CoachReply?
        // 每个 chunk 都重排气泡会把主线程打满，合并到 60ms 窗口（设计系统 §10）
        var throttle = StreamThrottle()

        do {
            let client = try settings.makeRecordingClient()
            var coachContext = CoachContext()
            coachContext.persona = MiloPersona(defaults: .standard)
            coachContext.planState = try CoachPlanContext.build(context: context, query: text)
            profileText = "按需查询本机记录的聚合数据，未默认加载全部历史。"

            var searchSources: [URL] = []
            let queryTools = CoachTools(webSearchEnabled: settings.webSearchEnabled && settings.supportsWebSearch, onActivity: { activity in
                guard memoryStore.generation == generation else { return }
                if let index = toolActivities.firstIndex(where: { $0.id == activity.id }) {
                    toolActivities[index] = activity
                } else {
                    toolActivities.append(activity)
                }
            }) { call in
                try Task.checkCancellation()
                guard memoryStore.generation == generation else { throw CancellationError() }
                if call.name == CoachTools.records.name {
                    guard let query = CoachAgent.decodeArguments(CoachRecordQuery.self, from: call) else {
                        return CoachToolResult(content: "查询参数无效，请提供类型和 yyyy-MM-dd 日期范围。", failed: true)
                    }
                    do {
                        return try CoachRecordStore.query(query, context: context)
                    } catch let error as CoachRecordQuery.QueryError {
                        return CoachToolResult(content: error.localizedDescription, failed: true)
                    }
                }
                if call.name == CoachTools.reader.name {
                    guard settings.webSearchEnabled && settings.supportsWebSearch,
                          let args = CoachAgent.decodeArguments(WebReaderArguments.self, from: call),
                          args.sourceIndex > 0, args.sourceIndex <= searchSources.count else {
                        return CoachToolResult(content: "请先搜索，再选择本轮返回的有效来源编号。未读取网页。", failed: true)
                    }
                    if settings.useLocalModel { return try await browser.read(searchSources[args.sourceIndex - 1]) }
                    return try await GLMWebReader(config: client.config).read(url: searchSources[args.sourceIndex - 1])
                }
                guard settings.webSearchEnabled && settings.supportsWebSearch,
                      let args = CoachAgent.decodeArguments(FitnessSearchArguments.self, from: call) else {
                    return CoachToolResult(content: "联网搜索未启用，或公共主题不受支持。没有执行搜索。", failed: true)
                }
                let count = args.count ?? GLMWebSearch.defaultResultCount
                let result: CoachToolResult
                if settings.useLocalModel { result = try await browser.search(topic: args.topic, count: count) }
                else { result = try await GLMWebSearch(config: client.config).search(topic: args.topic, count: count) }
                searchSources = result.sources
                return result
            }
            let stream = CoachAgent(client: client, policy: settings.coachPolicy, tools: queryTools).streamReply(
                history: history,
                userMessage: text,
                context: coachContext,
                thinkingEnabled: settings.thinkingEnabled,
                memory: memory,
                onMemory: { value in
                    try memoryStore.save(value, generation: generation, context: context)
                },
                onPreparing: { value in
                    if memoryStore.generation == generation { isPreparingContext = value }
                }
            )

            for try await event in stream {
                try Task.checkCancellation()
                guard memoryStore.generation == generation else { return }
                switch event {
                case .reasoning(let chunk):
                    accumulatedReasoning += chunk
                    if throttle.shouldEmit() { streamingReasoning = accumulatedReasoning }
                case .text(let chunk):
                    accumulatedText += chunk
                    if throttle.shouldEmit() { streamingText = accumulatedText }
                case .completed(let value):
                    reply = value
                }
            }

            try Task.checkCancellation()
            // 补上落在窗口中间、还没显示的最后一段 —— 否则最后一个字看不到
            if throttle.flush() {
                streamingText = accumulatedText
                streamingReasoning = accumulatedReasoning
            }
        } catch {
            guard memoryStore.generation == generation else { return }
            if suppliedText == nil && !Task.isCancelled && accumulatedText.isEmpty && accumulatedReasoning.isEmpty && inputText.isEmpty {
                inputText = text
            }
            // 中断或失败：已收到的内容照样保留
            let wasCancelled = error is CancellationError || Task.isCancelled
                || (error as? URLError)?.code == .cancelled
            if wasCancelled {
                errorText = accumulatedText.isEmpty && accumulatedReasoning.isEmpty
                    ? "本次回复已停止，可以重新发送。"
                    : "本次回复已停止，已保留收到的内容。"
            } else if accumulatedText.isEmpty && accumulatedReasoning.isEmpty {
                errorText = "调用失败：\(error.localizedDescription)"
            } else {
                errorText = "回复中断：\(error.localizedDescription)\n已保留收到的内容。"
            }
        }

        guard memoryStore.generation == generation else { return }
        isSending = false
        isPreparingContext = false
        streamingText = ""
        streamingReasoning = ""

        let finalText = reply?.text ?? (accumulatedText.isEmpty ? nil : accumulatedText)
        let hasContent = !(finalText ?? "").isEmpty
            || reply?.planArgumentsJSON != nil
            || reply?.adjustmentArgumentsJSON != nil
            || !toolActivities.isEmpty

        guard hasContent else { return }

        // 优先用流式过程中收到的思考内容；没收到时退回 reply 里带出来的
        let finalReasoning = accumulatedReasoning.isEmpty ? (reply?.reasoning ?? "") : accumulatedReasoning

        let assistant = ChatMessage(
            role: .assistant,
            content: finalText ?? "",
            pendingPlanJSON: reply?.planArgumentsJSON,
            pendingPlanTitle: reply?.planDraft?.title,
            pendingAdjustmentJSON: reply?.adjustmentArgumentsJSON,
            reasoningText: finalReasoning.isEmpty ? nil : finalReasoning
        )
        if !toolActivities.isEmpty, let data = try? JSONEncoder().encode(toolActivities) {
            assistant.toolActivityJSON = String(data: data, encoding: .utf8)
        }
        context.insert(assistant)
        do {
            try context.save()
        } catch { errorText = "回复未能保存，请重试。" }
    }

    private func loadProfile() {
        guard profileText.isEmpty else { return }
        profileText = "会按问题查询本机记录的聚合数据；不会默认加载全部历史。"
    }

    /// 把计划草稿写入课程表
    private func accept(plan draft: PlanDraft, message: ChatMessage) {
        do {
            guard try CoachPlanImporter.accept(draft, message: message, context: context) != nil else { return }
        } catch {
            context.rollback()
            appState.showToast("保存计划失败，请重试")
            return
        }

        Haptics.success()
        appState.showToast("已加入课程表：\(draft.title)")
    }

    /// 把教练的调整建议落到课程表（仅用户确认后生效）
    private func apply(adjustment: PlanAdjustmentDraft, message: ChatMessage) {
        do {
            if let receipt = try PlanMutationStore.apply(message: message, context: context) {
                Haptics.success()
                appState.showToast(receipt)
            }
        } catch { appState.showToast(error.localizedDescription) }
    }

    private func reject(message: ChatMessage) {
        if message.hasPendingPlan { message.planDecisionRaw = "rejected" }
        if message.hasPendingAdjustment { message.adjustmentDecisionRaw = "rejected" }
        try? context.save()
    }

    private func clearHistory() {
        dictation.finish()
        realtime.end(); showsRealtime = false
        stopStreaming()
        toolActivities = []
        isSending = false
        isPreparingContext = false
        streamingText = ""
        streamingReasoning = ""
        do { try memoryStore.clear(context: context); errorText = nil }
        catch { context.rollback(); errorText = "清空失败，请重试" }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
    }

    /// 流式中的气泡：思考区 + 正文，边收边渲染
    private var streamingBubble: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if toolActivities.contains(where: { settings.thinkingEnabled || $0.kind != "thinking" }) {
                CoachToolActivityView(activities: toolActivities, initiallyExpanded: true, showThinking: settings.thinkingEnabled)
            }
            if settings.thinkingEnabled, !toolActivities.contains(where: { $0.kind == "thinking" }), !streamingReasoning.isEmpty {
                ThinkingBlock(text: streamingReasoning, isStreaming: streamingText.isEmpty)
            } else if streamingText.isEmpty && !toolActivities.contains(where: { $0.status == .running }) {
                HStack(spacing: Theme.Spacing.s) {
                    PulsingDots()
                    Text(isPreparingContext ? "正在整理聊天记录…" : "正在准备回复…")
                        .font(Theme.Font.footnote)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }

            if !streamingText.isEmpty {
                MarkdownText(content: streamingText, justifiedParagraphs: true)
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }


        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// function call 结果的计划卡片：确认后才写入课程表
struct PlanDraftCard: View {

    let message: ChatMessage
    var showsActions = true
    var onAccept: (PlanDraft) -> Void
    var onReject: () -> Void

    private var draft: PlanDraft? {
        guard let json = message.pendingPlanJSON, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PlanDraft.self, from: data)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("为你整理的计划")
                .font(Theme.Font.badge)
                .foregroundStyle(Theme.accent)

            if let draft {
                Text(draft.title)
                    .font(Theme.Font.subheadline.weight(.semibold))
                TutorialProgressView(names: draft.days.flatMap { $0.exercises.map(\.name) })

                VStack(spacing: 0) {
                    ForEach(Array(draft.days.enumerated()), id: \.offset) { index, day in
                        HStack(alignment: .top, spacing: Theme.Spacing.m) {
                            Text(dayLabel(day.dayOffset))
                                .font(Theme.Font.footnote.weight(.semibold))
                                .foregroundStyle(day.dayOffset == 0 ? Theme.accent : Theme.secondaryLabel)
                                .frame(width: 48, alignment: .leading)

                            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                                Text(day.title)
                                    .font(Theme.Font.subheadline.weight(.semibold))

                                VStack(spacing: Theme.Spacing.s) {
                                    ForEach(Array(day.exercises.enumerated()), id: \.offset) { _, exercise in
                                        NavigationLink {
                                            ExerciseDetailView(name: exercise.name, setsText: exercise.setsText, weightKg: exercise.targetWeightKg)
                                        } label: {
                                        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
                                            Text(exercise.name)
                                                .font(Theme.Font.subheadline)
                                            Spacer(minLength: 0)
                                            Text(exerciseDetail(exercise))
                                                .font(Theme.Font.footnote)
                                                .foregroundStyle(Theme.secondaryLabel)
                                                .multilineTextAlignment(.trailing)
                                        }
                                        }
                                    }
                                }
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, Theme.Spacing.s)

                        if index < draft.days.count - 1 {
                            RowDivider(inset: 60)
                        }
                    }
                }

                if draft.days.isEmpty {
                    Text("这份计划没有排到任何训练日")
                        .font(Theme.Font.footnote)
                        .foregroundStyle(Theme.secondaryLabel)
                }

                if message.planAcceptedAt != nil {
                    Label("已加入课程表", systemImage: "checkmark.circle.fill")
                        .font(Theme.Font.footnote)
                        .foregroundStyle(Theme.accent)
                        .padding(.top, Theme.Spacing.xs)
                } else if showsActions {
                    VStack(spacing: Theme.Spacing.s) {
                        Button("不采用") { onReject() }
                            .buttonStyle(SecondaryButtonStyle())

                        Button("加入课程表") { onAccept(draft) }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    .padding(.top, Theme.Spacing.xs)
                }
            } else {
                Text("计划解析失败，请在对话中重新生成")
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.danger)
            }
        }
        .padding(Theme.Spacing.l)
        .background(Theme.cardNested, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    /// 「卧推 4×8 · 60kg」—— 有组次就带上，没有就只写名字
    private func exerciseDetail(_ exercise: PlanExerciseDraft) -> String {
        var text = exercise.setsText
        if let weight = exercise.targetWeightKg, weight > 0 {
            text += " · \(Format.number(weight, decimals: weight.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1))kg"
        }
        return text
    }

    /// 「今天 / 明天 / 后天 / 9月16日」—— 用真实日期，比「+3 天」好对
    private func dayLabel(_ offset: Int) -> String {
        if let acceptedAt = message.planAcceptedAt {
            let date = Calendar.current.date(byAdding: .day, value: offset, to: acceptedAt) ?? acceptedAt
            return Format.shortDay(date)
        }
        switch offset {
        case 0: return "今天"
        case 1: return "明天"
        case 2: return "后天"
        default:
            let date = Calendar.current.date(byAdding: .day, value: offset, to: .now) ?? .now
            return Format.shortDay(date)
        }
    }
}

/// function call 返回的调整建议卡片：用户确认后才改动课程表
struct AdjustmentDraftCard: View {
    @Environment(\.modelContext) private var context
    @State private var undoError: String?

    @Query private var plans: [Plan]

    let message: ChatMessage
    var onAccept: (PlanAdjustmentDraft) -> Void
    var onReject: () -> Void

    private var draft: PlanAdjustmentDraft? {
        guard let json = message.pendingAdjustmentJSON, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PlanAdjustmentDraft.self, from: data)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("建议这样调整")
                .font(Theme.Font.badge)
                .foregroundStyle(Theme.accent)

            if let draft {
                Text(draft.summary)
                    .font(Theme.Font.subheadline.weight(.semibold))
                if let plan = plans.first(where: { $0.uuid.uuidString == draft.planID?.uppercased() }) {
                    Text("课程表：\(plan.title)").font(Theme.Font.footnote)
                }

                ForEach(Array(draft.changes.enumerated()), id: \.offset) { _, change in
                    HStack(alignment: .top, spacing: Theme.Spacing.m) {
                        Text(actionLabel(change.action))
                            .font(Theme.Font.footnote.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 52, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(targetLabel(change, draft: draft))
                                .font(Theme.Font.badge)
                                .fontWeight(.regular)
                                .foregroundStyle(Theme.secondaryLabel)
                            Text(change.detail)
                                .font(Theme.Font.footnote)
                            if let title = change.title { Text("新名称：\(title)") }
                            if let date = change.date { Text("日期：\(date)") }
                            if let exercises = change.exercises {
                                ForEach(Array(exercises.enumerated()), id: \.offset) { _, exercise in
                                    Text("\(exercise.name) · \(exercise.setsText)" + (exercise.targetWeightKg.map { " · \(Format.number($0, decimals: $0.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1))kg" } ?? " · 未设目标重量"))
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                }

                if message.adjustmentDecisionRaw == "undone" {
                    Label("已撤销改期", systemImage: "arrow.uturn.backward")
                        .font(Theme.Font.footnote).foregroundStyle(Theme.secondaryLabel)
                } else if message.adjustmentDecisionRaw == "applied" {
                    Label("已完成", systemImage: "checkmark.circle.fill")
                        .font(Theme.Font.footnote).foregroundStyle(Theme.positive)
                    if message.adjustmentUndoJSON != nil {
                        Button("撤销改期") {
                            do { _ = try PlanMutationStore.undoReschedule(message: message, context: context) }
                            catch { undoError = error.localizedDescription }
                        }
                        if let undoError { Text(undoError).font(.footnote).foregroundStyle(Theme.danger) }
                    }
                } else if draft.planID == nil || draft.revision == nil || !plans.contains(where: { $0.uuid.uuidString == draft.planID?.uppercased() }) {
                    Text("目标已不存在或建议缺少有效版本，请在对话中重新查询后生成。")
                        .font(Theme.Font.footnote).foregroundStyle(Theme.secondaryLabel)
                    Button("不采用", action: onReject)
                } else {
                    let destructive = draft.changes.contains { ["delete_plan", "delete_day"].contains($0.action) }
                    if destructive {
                        Text("删除后无法恢复，已有训练记录会保留。")
                            .font(Theme.Font.footnote).foregroundStyle(Theme.secondaryLabel)
                    }
                    Button(role: destructive ? .destructive : nil) { onAccept(draft) } label: {
                        Text(destructive ? "确认删除所列内容" : "确认应用修改").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(destructive ? Theme.danger : Theme.accent)
                    .controlSize(.large)
                    Button("不采用", action: onReject).buttonStyle(SecondaryButtonStyle())
                }
            } else {
                Text("调整建议解析失败，请在对话中重新生成")
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.danger)
            }
        }
        .padding(Theme.Spacing.l)
        .background(Theme.cardNested, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private func targetLabel(_ change: PlanAdjustmentChange, draft: PlanAdjustmentDraft) -> String {
        if let plan = plans.first(where: { $0.uuid.uuidString == draft.planID?.uppercased() }),
           let day = plan.days.first(where: { $0.uuid.uuidString == change.dayID?.uppercased() }) {
            return "\(Format.shortDay(day.date)) · \(day.title)"
        }
        if change.action == "delete_plan" || change.action == "rename_plan" { return "整份课程表" }
        return change.date ?? "建议中的训练日"
    }

    private func actionLabel(_ action: String) -> String {
        switch action {
        case "delete_plan": return "删除课程表"
        case "delete_day": return "删除训练日"
        case "add_day": return "增加训练日"
        case "rename_plan": return "改名称"
        case "deload": return "减载15%"
        case "replace": return "换动作"
        case "reschedule": return "顺延"
        case "skip": return "跳过"
        default: return "调整"
        }
    }

}
