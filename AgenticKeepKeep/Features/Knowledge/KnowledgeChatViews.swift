import SwiftUI
import SwiftData

struct ConversationKnowledgeNotices: View {
    var conversationID: UUID
    var after: Date?
    @Environment(\.modelContext) private var context
    @StateObject private var model = KnowledgeViewModel()
    @State private var showsHistory = false
    private var notices: [KnowledgeNotice] {
        Array(model.state.notices.filter {
            $0.conversationID == conversationID && !$0.undone && $0.dismissed != true
                && (after == nil || $0.date >= after!)
        }.suffix(3))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(notices) { notice in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle").font(.subheadline).foregroundStyle(.secondary).padding(.top, 3)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(notice.message).font(.subheadline).foregroundStyle(.secondary)
                        HStack(spacing: 20) {
                            NavigationLink("查看") { KnowledgeDetailView(id: notice.itemID, model: model) }
                            Button("撤销") { model.perform(context) { try $0.undo(noticeID: notice.id) } }
                        }.font(.footnote).tint(Theme.accent)
                    }
                    Spacer(minLength: 0)
                    Button {
                        model.perform(context) { $0.dismissNotice(notice.id) }
                    } label: {
                        Image(systemName: "xmark").font(.caption).foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel("收起保存提示，不删除记忆")
                }.padding(.vertical, 8)
            }
            if model.state.jobs.contains(where: { $0.conversationID == conversationID && $0.state == "failed" }) {
                Button("记忆整理有未完成的任务，查看并重试") { showsHistory = true }.font(.footnote)
            }
            if let error = model.error { Text(error).font(.footnote).foregroundStyle(.red) }
        }
        .sheet(isPresented: $showsHistory) { NavigationStack { KnowledgeHistoryView(model: model) } }
        .task { model.refresh(context) }
        .onReceive(NotificationCenter.default.publisher(for: .personalKnowledgeChanged)) { _ in model.refresh(context) }
    }
}

struct ChatConversationsView: View {
    var activeID: UUID?
    var onSelect: (UUID) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\ChatConversation.updatedAt, order: .reverse)]) private var conversations: [ChatConversation]
    @Query(sort: [SortDescriptor(\ChatMessage.date, order: .reverse)]) private var messages: [ChatMessage]
    @State private var query = ""
    @State private var deletion: UUID?
    @State private var error: String?
    private let groups = ["今天", "昨天", "过去 7 天", "更早"]
    private func group(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return groups[0] }
        if calendar.isDateInYesterday(date) { return groups[1] }
        if date >= calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: Date()))! { return groups[2] }
        return groups[3]
    }
    private func preview(_ conversation: ChatConversation) -> String {
        if !conversation.draft.isEmpty { return "草稿 · " + conversation.draft }
        return messages.first(where: { $0.conversationID == conversation.uuid && !$0.content.isEmpty })?.content ?? "还没有发送消息"
    }
    private var matching: [ChatConversation] {
        conversations.filter { query.isEmpty || ($0.title + preview($0)).localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        List {
            Group {
            if matching.isEmpty {
                ContentUnavailableView(query.isEmpty ? "从一句话开始" : "没有找到这段对话", systemImage: "bubble.left",
                    description: Text(query.isEmpty ? "点右上角，和 Milo 聊点新话题。" : "试试其他关键词。"))
                    .listRowSeparator(.hidden).listRowBackground(Theme.canvas)
            }
            ForEach(groups, id: \.self) { label in
                let rows = matching.filter { group($0.updatedAt) == label }
                if !rows.isEmpty {
                    Section(label) {
                        ForEach(rows) { conversation in
                            Button { action { try PersonalKnowledgeStore.selectConversation(conversation.uuid, context: context); onSelect(conversation.uuid); dismiss() } } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack(alignment: .firstTextBaseline) {
                                        if conversation.uuid == activeID { Image(systemName: "checkmark").font(.caption).accessibilityLabel("当前会话") }
                                        Text(conversation.title.isEmpty ? "新的对话" : conversation.title).font(.body.weight(.medium)).lineLimit(1)
                                        Spacer(minLength: 12)
                                        Text(conversation.updatedAt.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(Theme.secondaryLabel)
                                    }
                                    Text(preview(conversation)).font(.subheadline).foregroundStyle(Theme.secondaryLabel).lineLimit(1)
                                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(conversation.uuid == activeID ? Theme.cardNested : Theme.canvas, in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain).foregroundStyle(Theme.Journal.label)
                                .listRowInsets(EdgeInsets(top: 2, leading: 20, bottom: 2, trailing: 20))
                                .listRowBackground(Theme.canvas).listRowSeparator(.hidden)
                                .swipeActions { Button("删除", role: .destructive) { deletion = conversation.uuid } }
                        }
                    }.textCase(nil)
                }
            }
            if let error { Text(error).foregroundStyle(Theme.danger).listRowBackground(Theme.canvas) }

            }.listRowBackground(Theme.canvas)
        }.themedListSurface()
        .listStyle(.plain).scrollContentBackground(.hidden).background(Theme.canvas)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索对话")
        .navigationTitle("对话").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.canvas, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            NavigationLink { PersonalKnowledgeView() } label: {
                HStack { Text("Milo 的记忆"); Spacer(); Image(systemName: "chevron.right") }
                    .font(.subheadline).foregroundStyle(Theme.secondaryLabel).padding(.horizontal, 24).frame(minHeight: 52)
            }.background(Theme.canvas)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) {
                Button { action { onSelect(try PersonalKnowledgeStore.newConversation(context)); dismiss() } } label: {
                    Image(systemName: "square.and.pencil").frame(width: 44, height: 44)
                }.accessibilityLabel("新建对话")
            }
        }
        .confirmationDialog("删除这个会话？", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }), titleVisibility: .visible) {
            Button("删除会话", role: .destructive) {
                guard let id = deletion else { return }
                action {
                    try PersonalKnowledgeStore.deleteConversation(id, context: context)
                    if id == activeID { onSelect(try PersonalKnowledgeStore.prepareConversation(context)) }
                }
                deletion = nil
            }
        } message: { Text("只删除对话。已保存的资料、记忆、技能以及课程表和记录会保留。") }
    }
    private func action(_ work: () throws -> Void) { do { try work() } catch { self.error = error.localizedDescription } }
}
