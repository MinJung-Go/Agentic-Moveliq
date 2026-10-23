import SwiftUI
import SwiftData

struct ConversationKnowledgeNotices: View {
    var conversationID: UUID
    @Environment(\.modelContext) private var context
    @StateObject private var model = KnowledgeViewModel()
    @State private var showsHistory = false
    private var notices: [KnowledgeNotice] {
        Array(model.state.notices.filter { $0.conversationID == conversationID && !$0.undone }.suffix(3))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(notices) { notice in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "bookmark").foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(notice.message).font(.subheadline)
                        HStack(spacing: 20) {
                            NavigationLink("查看") { KnowledgeDetailView(id: notice.itemID, model: model) }
                            Button("撤销") { model.perform(context) { try $0.undo(noticeID: notice.id) } }
                        }.font(.footnote).tint(Theme.accent)
                    }
                    Spacer(minLength: 0)
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
    @State private var deletion: UUID?
    @State private var error: String?
    var body: some View {
        List {
            Section {
                Button { action { onSelect(try PersonalKnowledgeStore.newConversation(context)); dismiss() } } label: { Label("新的对话", systemImage: "square.and.pencil") }
            } footer: { Text("换个话题，仍是了解你的 Milo。个人资料、记忆和技能在会话间共享。") }
            ForEach(conversations) { conversation in
                Button {
                    action { try PersonalKnowledgeStore.selectConversation(conversation.uuid, context: context); onSelect(conversation.uuid); dismiss() }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(conversation.title).foregroundStyle(.primary)
                            Text(conversation.updatedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if conversation.uuid == activeID { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                    }.padding(.vertical, 6)
                }.swipeActions { Button("删除", role: .destructive) { deletion = conversation.uuid } }
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle("对话").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
        .confirmationDialog("删除这个会话？", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }), titleVisibility: .visible) {
            Button("删除会话", role: .destructive) {
                guard let id = deletion else { return }
                action {
                    try PersonalKnowledgeStore.deleteConversation(id, context: context)
                    if id == activeID { onSelect(try PersonalKnowledgeStore.prepareConversation(context)) }
                }
                deletion = nil
            }
        } message: { Text("只删除对话。已保存的资料、记忆、技能以及课程表和记录会保留；可以到「Milo 的记忆」单独管理。") }
    }
    private func action(_ work: () throws -> Void) { do { try work() } catch { self.error = error.localizedDescription } }
}
