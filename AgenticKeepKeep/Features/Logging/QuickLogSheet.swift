import SwiftUI
import SwiftData
import UIKit

/// 对话式记录：说一句话 → 解析结果以可编辑卡片内联出现 → 确认入库。
/// 输入条常驻在底部，可以连续补充（「再加一组」「换成 90kg」），不必反复重开弹窗。
struct QuickLogSheet: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: LoggingViewModel

    @StateObject private var dictation = VoiceInput()
    @State private var pickedPhoto: Data?
    @State private var isSubmittingInput = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                conversation
                if let turn = pendingConfirmation {
                    Button("保存这 \(turn.drafts.count) 条") { save(turn.id) }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(viewModel.isParsing)
                        .padding(Theme.Spacing.l)
                        .background(Theme.canvas)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { inputBar }
            .background(Theme.canvas)
            .navigationTitle("记录")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.submitHomeInput(from: appState, context: context)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { close() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.hasTurns {
                        Button("清空") {
                            dictation.finish()
                            withAnimation { viewModel.reset() }
                        }
                        .foregroundStyle(Theme.danger)
                    }
                }
            }
        }
    }

    private var pendingConfirmation: LoggingViewModel.LogTurn? {
        viewModel.turns.last { $0.kind == .assistant && !$0.isSaved && !$0.drafts.isEmpty }
    }

    // MARK: - 对话流

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !viewModel.hasTurns {
                        intro
                    }

                    ForEach($viewModel.turns) { $turn in
                        turnView($turn)
                            .id(turn.id)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }

                    if viewModel.isParsing {
                        parsingRow.id(Self.parsingAnchor)
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.turns.count) { scrollToBottom(proxy) }
            .onChange(of: viewModel.isParsing) { scrollToBottom(proxy) }
            .animation(.listChange, value: viewModel.turns.count)
        }
    }

    private static let parsingAnchor = "keepkeep.parsing"

    @ViewBuilder
    private func turnView(_ turn: Binding<LoggingViewModel.LogTurn>) -> some View {
        let value = turn.wrappedValue

        switch value.kind {
        case .user:
            // 照片是**附件**不是触发器：贴在气泡里一起显示，文字是它的补充说明
            ChatBubble(
                speaker: .user,
                thumbnail: value.photoData.flatMap(UIImage.init(data:)),
                showsContent: !value.text.isEmpty
            ) {
                Text(value.text).font(Theme.Font.body)
            }

        case .failure:
            failureCard(value.text)

        case .assistant:
            assistantTurn(turn)
        }
    }

    @ViewBuilder
    private func assistantTurn(_ turn: Binding<LoggingViewModel.LogTurn>) -> some View {
        let value = turn.wrappedValue

        VStack(alignment: .leading, spacing: 10) {
            if let savedCount = value.savedCount {
                ForEach(turn.drafts) { $draft in
                    DraftCardView(draft: $draft, onDelete: {})
                        .disabled(true)
                }
                savedCard(count: savedCount)
            } else if value.drafts.isEmpty {
                Text("这一轮已清空")
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.tertiaryLabel)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Theme.accent)
                    Text("识别完成 · 每个字段都能改")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.tertiaryLabel)
                }

                ForEach(turn.drafts) { $draft in
                    DraftCardView(draft: $draft) {
                        withAnimation {
                            turn.wrappedValue.drafts.removeAll { $0.id == draft.id }
                        }
                    }
                }

                if value.id != pendingConfirmation?.id {
                    Button("保存这 \(value.drafts.count) 条") {
                        save(turn.wrappedValue.id)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
    }

    /// 保存后**折叠成一行回执**，而不是整块消失 —— 用户得看得见「刚才那条进去了」
    private func savedCard(count: Int) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.positive)
            Text("已保存 \(count) 条记录")
                .font(Theme.Font.subheadline)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, 11)
        .background(Theme.chip, in: Capsule())
    }

    private func failureCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .foregroundStyle(Theme.warning)
                Text(text)
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                ForEach(LogDraft.Kind.allCases, id: \.self) { kind in
                    Button {
                        withAnimation { viewModel.addManualDraft(kind) }
                    } label: {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: kind.recordKind.symbol)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(kind.recordKind.color)
                            Text(kind.headerTitle)
                        }
                        .font(Theme.Font.footnote)
                        .padding(.horizontal, Theme.Spacing.m)
                        .padding(.vertical, 6)
                        .background(Theme.chip, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(Theme.cardNested.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous))
    }

    private var parsingRow: some View {
        HStack(spacing: Theme.Spacing.s) {
            PulsingDots()
            Text("正在理解…")
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.secondaryLabel)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    // MARK: - 空态引导

    private var intro: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !viewModel.isConfigured {
                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Theme.warning)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("尚未配置 AI").font(Theme.Font.subheadline.weight(.semibold))
                        Text("请确认已登录且云端服务可用；也可以直接手动记录。")
                            .font(Theme.Font.footnote)
                            .foregroundStyle(Theme.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .card()
            }

            Text("说一句话就能记录")
                .font(Theme.Font.headline)

            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                exampleRow(quote: "深蹲100kg 5×5，有点累", tag: "训练")
                exampleRow(quote: "中午吃了牛肉面", tag: "饮食")
                exampleRow(quote: "体重74.5", tag: "指标")
            }

            RowDivider(inset: 0)
                .padding(.vertical, Theme.Spacing.xs)

            Text("或手动记录")
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.secondaryLabel)

            HStack(spacing: 10) {
                ForEach(LogDraft.Kind.allCases, id: \.self) { kind in
                    Button {
                        withAnimation { viewModel.addManualDraft(kind) }
                    } label: {
                        VStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: kind.recordKind.filledSymbol)
                                .font(Theme.Font.title)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(kind.recordKind.color)
                            Text(kind.headerTitle).font(Theme.Font.badge)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.cardNested, in: RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// 示例可以**直接点** —— 空态给的是能照抄的东西，不是一段说明文字（FR15.6）
    private func exampleRow(quote: String, tag: String) -> some View {
        Button {
            viewModel.inputText = quote
            Haptics.tap()
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                Text("「\(quote)」")
                    .font(Theme.Font.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
                Spacer(minLength: 6)
                Badge(tag, tone: .bright(Theme.accent))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("填入输入框")
    }

    // MARK: - 输入条

    private var inputBar: some View {
        MessageComposer(
            text: $viewModel.inputText,
            photo: $pickedPhoto,
            dictation: dictation,
            focus: $isInputFocused,
            placeholder: "记下饮食、训练或感受…",
            isBusy: viewModel.isParsing || isSubmittingInput,
            identifier: "logging",
            background: Theme.canvas,
            onSend: send
        )
    }

    private func send() {
        guard !isSubmittingInput, !viewModel.isParsing,
              pickedPhoto != nil || !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let photo = pickedPhoto
        pickedPhoto = nil
        isSubmittingInput = true
        Task {
            defer { isSubmittingInput = false }
            await viewModel.submit(context: context, photo: photo)
        }
    }

    // MARK: - 动作

    private func save(_ turnID: UUID) {
        let count = viewModel.save(turnID: turnID, context: context)
        guard count > 0 else {
            Haptics.warning()
            return
        }

        Haptics.success()
        appState.showToast("已保存 \(count) 条记录")
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation {
            if viewModel.isParsing {
                proxy.scrollTo(Self.parsingAnchor, anchor: .bottom)
            } else if let last = viewModel.turns.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func close() {
        dictation.finish()
        viewModel.reset()
        pickedPhoto = nil
        dismiss()
    }
}
