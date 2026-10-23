import SwiftUI
import SwiftData
import UniformTypeIdentifiers

@MainActor final class KnowledgeViewModel: ObservableObject {
    @Published var state = KnowledgeState()
    @Published var error: String?
    func refresh(_ context: ModelContext) { do { state = try PersonalKnowledgeStore.load(context) } catch { self.error = error.localizedDescription } }
    func perform(_ context: ModelContext, _ action: (inout KnowledgeState) throws -> Void) {
        error = nil
        do { try PersonalKnowledgeStore.mutate(context, token: ServiceCredentials.session?.token, action); refresh(context) }
        catch { self.error = error.localizedDescription }
    }
}
struct KnowledgeFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct PersonalKnowledgeView: View {
    @Environment(\.modelContext) private var context
    @StateObject private var model = KnowledgeViewModel()
    @State private var kind: KnowledgeKind = .skill
    @State private var query = ""
    @State private var archived = false
    @State private var showHistory = false
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var confirmExport = false
    @State private var exportFile: KnowledgeFile?
    @State private var pendingImport: KnowledgeImportPreview?
    private var entries: [KnowledgeItem] {
        model.state.items.filter { !$0.candidate && $0.kind == kind && ($0.status == .archived) == archived }
            .filter { query.isEmpty || ($0.content.name + $0.content.description + $0.content.body).localizedCaseInsensitiveContains(query) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
    var body: some View {
        List {
            Section {
                Text("熟悉你的方式，慢慢积累。")
                    .font(.subheadline).foregroundStyle(.secondary).listRowSeparator(.hidden)
                Picker("知识类型", selection: $kind) {
                    ForEach(KnowledgeKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).listRowSeparator(.hidden)
            }.listRowBackground(Color.clear)
            if kind == .profile {
                Section {
                    NavigationLink { CoachLifeProfileView() } label: {
                        Label("训练与日常设置", systemImage: "person.text.rectangle")
                    }
                } footer: { Text("目标、器械、频次和时段沿用已有设置；这里整理其他稳定偏好。") }
            }
            Section {
                if entries.isEmpty {
                    ContentUnavailableView(query.isEmpty ? "慢慢了解你" : "没有找到", systemImage: "book.closed",
                        description: Text(query.isEmpty ? "对话中的方法和偏好会逐渐出现在这里。只有助手提出的方法，先留作内部候选。" : "换一个关键词，或查看已归档的内容。"))
                        .listRowSeparator(.hidden)
                }
                ForEach(entries) { item in
                    NavigationLink {
                        KnowledgeDetailView(id: item.id, model: model)
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(item.content.name).font(.body.weight(.medium))
                                Spacer(minLength: 12)
                                if item.status != .active { Text(item.status == .archived ? "已归档" : "已停用").font(.caption).foregroundStyle(.secondary) }
                            }
                            Text(item.content.description).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        }.padding(.vertical, 10)
                    }
                }
            } header: { if archived { Text("已归档") } }
            Section {
                Button { showHistory = true } label: { Label("整理历史对话", systemImage: "clock.arrow.circlepath") }
            } footer: {
                Text("保存在本机，不会自动同步。整理时会把必要的对话片段发送给已配置的云端模型；不包含思考过程或原始健康记录。")
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden).background(Theme.conversationCanvas)
        .navigationTitle("Milo 的记忆").navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, prompt: "搜索名称、内容或适用场景")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(archived ? "查看未归档" : "查看已归档", systemImage: "archivebox") { archived.toggle() }
                    Button("整理历史对话", systemImage: "clock.arrow.circlepath") { showHistory = true }
                    Button("导出记忆", systemImage: "square.and.arrow.up") { confirmExport = true }
                    Button("导入记忆", systemImage: "square.and.arrow.down") { showImporter = true }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("记忆管理")
            }
        }
        .task { model.refresh(context) }
        .onReceive(NotificationCenter.default.publisher(for: .personalKnowledgeChanged)) { _ in model.refresh(context) }
        .alert("未能完成", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("知道了", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
        .confirmationDialog("导出本机记忆？", isPresented: $confirmExport, titleVisibility: .visible) {
            Button("导出文件") { export() }
        } message: {
            Text("文件含个人资料、长期记忆和正式技能及其版本，不含完整聊天、候选、登录凭据或自动执行授权。请妥善保管。")
        }
        .fileExporter(isPresented: $showExporter, document: exportFile, contentType: .json, defaultFilename: "Moveliq-记忆") { result in
            if case .failure(let error) = result { model.error = error.localizedDescription }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get(), granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 12_000_000 else { throw KnowledgeError.invalid("文件不能超过 12 MB。") }
                let archive = try KnowledgeArchive.read(Data(contentsOf: url))
                pendingImport = .init(archive: archive)
            } catch { model.error = error.localizedDescription }
        }
        .sheet(item: $pendingImport) { preview in
            NavigationStack { KnowledgeImportView(archive: preview.archive, model: model) }
        }
        .sheet(isPresented: $showHistory) { NavigationStack { KnowledgeHistoryView(model: model) } }
    }
    private func export() {
        do {
            try CoachLifeStore.checkAccount(context: context, token: ServiceCredentials.session?.token)
            let archive = KnowledgeArchive(state: try PersonalKnowledgeStore.load(context), account: PersonalKnowledgeStore.account)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            exportFile = KnowledgeFile(data: try encoder.encode(archive)); showExporter = true
        } catch { model.error = error.localizedDescription }
    }
}
private struct KnowledgeImportPreview: Identifiable { let id = UUID(); var archive: KnowledgeArchive }

struct KnowledgeDetailView: View {
    var id: UUID
    @ObservedObject var model: KnowledgeViewModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editing: KnowledgeItem?
    @State private var confirmsDelete = false
    private var item: KnowledgeItem? { model.state.items.first { $0.id == id } }
    var body: some View {
        Group {
            if let item {
                List {
                    if let error = model.error { Section { Text(error).foregroundStyle(.red) } }
                    Section {
                        Text(item.content.name).font(.title2.weight(.semibold)).listRowSeparator(.hidden)
                        Text(item.content.description).foregroundStyle(.secondary).listRowSeparator(.hidden)
                        if item.kind == .skill {
                            Toggle("在相关对话中自动使用", isOn: Binding(get: { item.status == .active }, set: { enabled in
                                model.perform(context) { try $0.setStatus(enabled ? .active : .disabled, id: id, expected: item.revision) }
                            }))
                        }
                    }
                    Section {
                        MarkdownText(content: item.content.body).padding(.vertical, 8)
                    }
                    Section("来源") {
                        if item.evidence.isEmpty { Text("手动导入，尚无本机来源").foregroundStyle(.secondary) }
                        ForEach(item.evidence) { source in
                            if source.sourceDeleted {
                                sourceRow(source, deleted: true)
                            } else {
                                NavigationLink { KnowledgeSourceView(source: source) } label: { sourceRow(source, deleted: false) }
                            }
                        }
                        if let expires = item.expiresAt {
                            Text("适用至 \(expires.formatted(date: .abbreviated, time: .omitted))").font(.footnote).foregroundStyle(.secondary)
                            if expires <= Date() { Text("适用期已结束，当前不会自动使用。").font(.footnote).foregroundStyle(.secondary) }
                        }
                    }
                    Section("最近变化") {
                        if item.history.isEmpty { Text("首次保存 · v\(item.revision)").foregroundStyle(.secondary) }
                        ForEach(item.history.reversed()) { revision in
                            NavigationLink { KnowledgeRevisionView(revision: revision) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(revision.reason).font(.subheadline)
                                    Text("v\(revision.version) · \(revision.date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if let notice = model.state.notices.last(where: { $0.itemID == id && !$0.undone }) {
                            Button("撤销最近变更") { model.perform(context) { try $0.undo(noticeID: notice.id) } }
                        }
                    }
                    Section {
                        Button(item.status == .archived ? "从归档恢复" : "归档") {
                            model.perform(context) { try $0.setStatus(item.status == .archived ? .active : .archived, id: id, expected: item.revision) }
                        }
                        Button("删除", role: .destructive) { confirmsDelete = true }
                    } footer: { Text("归档后保留内容，停止自动使用。删除后同时移除内容和历史版本。") }
                }.listStyle(.insetGrouped)
                .safeAreaInset(edge: .bottom) {
                    Button("编辑内容") { editing = item }
                        .buttonStyle(PrimaryButtonStyle()).padding().background(Theme.conversationCanvas)
                }
            } else { ContentUnavailableView("这条内容已删除", systemImage: "book.closed") }
        }
        .navigationTitle(item?.kind.title ?? "详情").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { snapshot in NavigationStack { KnowledgeEditView(original: snapshot, model: model) } }
        .confirmationDialog("删除这条内容？", isPresented: $confirmsDelete, titleVisibility: .visible) {
            if let item {
                Button("删除内容及历史版本", role: .destructive) {
                    model.perform(context) { try $0.delete(id: id, expected: item.revision) }
                    if model.error == nil { dismiss() }
                }
            }
        } message: { Text("同一来源不会再次自动保存；新的明确保存请求仍可创建。") }
    }
    private func sourceRow(_ source: KnowledgeEvidence, deleted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(source.kind.title).font(.subheadline)
            Text(source.date.formatted(date: .abbreviated, time: .omitted) + (deleted ? " · 原会话已删除或不在本机" : " · 查看来源"))
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 3)
    }
}

private struct KnowledgeSourceView: View {
    var source: KnowledgeEvidence
    @Query private var messages: [ChatMessage]
    @Query private var actions: [CoachActionRecord]
    var body: some View {
        ScrollView {
            if let message = messages.first(where: { $0.uuid == source.id && $0.conversationID == source.conversationID }) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(message.role == .user ? "你的消息" : "Milo 的建议").font(.headline)
                    Text(message.content).textSelection(.enabled)
                    Text(source.kind.title).font(.footnote).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding()
            } else if let action = actions.first(where: { $0.uuid == source.id && $0.conversationID == source.conversationID }) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("应用执行回执").font(.headline)
                    Text(action.receipt).textSelection(.enabled)
                    Text("操作完成不代表训练已完成或效果已验证。").font(.footnote).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding()
            } else { ContentUnavailableView("原会话已不可用", systemImage: "bubble.left", description: Text("已保存的内容仍然保留。")) }
        }.navigationTitle("来源").navigationBarTitleDisplayMode(.inline)
    }
}
private struct KnowledgeRevisionView: View {
    var revision: KnowledgeRevision
    var body: some View {
        List {
            Section { Text(revision.reason); Text(revision.date.formatted()).font(.caption).foregroundStyle(.secondary) }
            if revision.patches.isEmpty { Section("恢复后的内容") { Text(revision.after.body).textSelection(.enabled) } }
            ForEach(Array(revision.patches.enumerated()), id: \.offset) { _, patch in
                Section("\(patch.field == .body ? "正文片段" : (patch.field == .name ? "名称" : "简介"))") {
                    VStack(alignment: .leading, spacing: 8) { Text("修改前").font(.caption).foregroundStyle(.secondary); Text(patch.oldString).textSelection(.enabled) }
                    VStack(alignment: .leading, spacing: 8) { Text("修改后").font(.caption).foregroundStyle(Theme.accent); Text(patch.newString.isEmpty ? "已移除" : patch.newString).textSelection(.enabled) }
                }
            }
        }.navigationTitle("变更 · v\(revision.version)").navigationBarTitleDisplayMode(.inline)
    }
}
private struct KnowledgeEditView: View {
    let original: KnowledgeItem
    @ObservedObject var model: KnowledgeViewModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var summary: String
    @State private var bodyText: String
    @State private var error: String?
    @State private var base: KnowledgeItem
    @State private var draftBackup: KnowledgeContent?
    @State private var confirmsReload = false
    init(original: KnowledgeItem, model: KnowledgeViewModel) {
        self.original = original; self.model = model; _base = State(initialValue: original)
        _name = State(initialValue: original.content.name); _summary = State(initialValue: original.content.description); _bodyText = State(initialValue: original.content.body)
    }
    var body: some View {
        Form {
            Section("名称") { TextField("名称", text: $name) }
            Section("简介") { TextField("适用场景或事实摘要", text: $summary, axis: .vertical) }
            Section {
                TextEditor(text: $bodyText).frame(minHeight: 260)
            } header: {
                Text("内容")
            } footer: {
                Text("只修改需要调整的段落。技能请保留适用、步骤、注意三个章节。")
            }
            if let error { Section { Text(error).foregroundStyle(.red); Button("读取最新内容") { confirmsReload = true } } }
            if let backup = draftBackup { Section("之前的草稿") { Text(backup.name).font(.headline); Text(backup.description).foregroundStyle(.secondary); Text(backup.body).textSelection(.enabled); Text("草稿保留在这里，可以复制需要的片段，再编辑上方最新内容。").font(.footnote).foregroundStyle(.secondary) } }
        }
        .navigationTitle("编辑\(original.kind.title)").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("载入最新版本？", isPresented: $confirmsReload, titleVisibility: .visible) {
            Button("保留草稿副本并载入最新") { reload() }
        } message: { Text("不会覆盖已保存的内容；你的草稿副本会显示在编辑器下方。") }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } }
        }
    }
    private func reload() {
        draftBackup = .init(name: name, description: summary, body: bodyText)
        model.refresh(context)
        guard let current = model.state.items.first(where: { $0.id == original.id }) else { error = "内容已删除，草稿仍保留。"; return }
        base = current; name = current.content.name; summary = current.content.description; bodyText = current.content.body
        error = nil
    }

    private func save() {
        do {
            let content = KnowledgeContent(name: name, description: summary, body: bodyText)
            let patches = try KnowledgeRules.diff(from: base.content, to: content)
            if !patches.isEmpty {
                try PersonalKnowledgeStore.mutate(context, token: ServiceCredentials.session?.token) {
                    try $0.patch(id: original.id, expected: base.revision, operationID: UUID().uuidString, patches: patches, reason: "你编辑了内容", manual: true)
                }
            }
            model.refresh(context); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct KnowledgeImportView: View {
    var archive: KnowledgeArchive
    @ObservedObject var model: KnowledgeViewModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var replacements = Set<UUID>()
    @State private var crossAccountConfirmed = false
    @State private var previewState: KnowledgeState?
    @State private var error: String?
    private var foreign: Bool { archive.account != PersonalKnowledgeStore.account }
    var body: some View {
        List {
            Section("导入预览") {
                ForEach(KnowledgeKind.allCases, id: \.self) { kind in LabeledContent(kind.title, value: "\(archive.items.filter { $0.kind == kind }.count) 条") }
                Text("重复内容跳过。冲突默认保留本机；选择的项目才用文件内容恢复。").font(.footnote).foregroundStyle(.secondary)
            }
            if foreign {
                Section { Toggle("我确认将其他账号的个人内容导入当前账号", isOn: $crossAccountConfirmed) }
            }
            Section("版本冲突") {
                let conflicts = archive.conflicts(in: previewState ?? model.state)
                if conflicts.isEmpty { Text("没有版本冲突").foregroundStyle(.secondary) }
                ForEach(conflicts) { item in
                    Toggle(isOn: Binding(get: { replacements.contains(item.id) }, set: { if $0 { replacements.insert(item.id) } else { replacements.remove(item.id) } })) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.content.name)
                            Text("文件：\(item.content.description)").font(.caption).foregroundStyle(.secondary)
                            if let local = (previewState ?? model.state).items.first(where: { $0.id == item.id }) { Text("本机：\(local.content.description)").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    DisclosureGroup("查看文件内容") { Text(item.content.body).font(.subheadline).textSelection(.enabled) }
                }
            }
            Section {
                Button("确认导入") { save() }.disabled(foreign && !crossAccountConfirmed)
                if let error { Text(error).foregroundStyle(.red) }
            } footer: { Text("仅恢复个人知识，不继承自动执行授权，也不会执行文件中的指令。原对话不包含在文件内。") }
        }.navigationTitle("导入记忆").navigationBarTitleDisplayMode(.inline)
        .task { if previewState == nil { previewState = try? PersonalKnowledgeStore.load(context) } }
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
    }
    private func save() {
        do {
            guard let preview = previewState else { throw KnowledgeError.conflict }
            try PersonalKnowledgeStore.mutate(context, token: ServiceCredentials.session?.token) { state in
                for incoming in archive.items {
                    guard state.items.first(where: { $0.id == incoming.id }) == preview.items.first(where: { $0.id == incoming.id }) else { throw KnowledgeError.conflict }
                }
                state = try archive.applying(to: state, replaceIDs: replacements)
            }
            model.refresh(context); dismiss()
        } catch { self.error = error.localizedDescription; model.refresh(context); previewState = model.state; replacements = [] }
    }
}

struct KnowledgeHistoryView: View {
    @ObservedObject var model: KnowledgeViewModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\ChatConversation.updatedAt, order: .reverse)]) private var conversations: [ChatConversation]
    @State private var selected = Set<UUID>()
    @State private var error: String?
    var body: some View {
        List {
            Section {
                ForEach(conversations) { conversation in
                    Toggle(isOn: Binding(get: { selected.contains(conversation.uuid) }, set: { if $0 { selected.insert(conversation.uuid) } else { selected.remove(conversation.uuid) } })) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(conversation.title)
                            Text(conversation.updatedAt.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Button("整理所选对话") {
                    do {
                        for id in selected { try PersonalLearningCoordinator.shared.enqueue(conversation: id, context: context, historical: true) }
                        selected.removeAll(); model.refresh(context)
                    } catch { self.error = error.localizedDescription }
                }.disabled(selected.isEmpty)
            } footer: { Text("只整理选中的对话。需要联网，可能产生模型用量；App 在前台时继续，离开后暂停。实时通话文字暂不参与。") }
            Section("整理进度") {
                if model.state.jobs.isEmpty { Text("暂无整理任务").foregroundStyle(.secondary) }
                ForEach(model.state.jobs.reversed()) { job in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(conversations.first(where: { $0.uuid == job.conversationID })?.title ?? "原会话已删除").font(.subheadline)
                        Text(label(job.state)).font(.caption).foregroundStyle(.secondary)
                        if let message = job.error { Text(message).font(.caption).foregroundStyle(.secondary) }
                        if job.state == "failed" { Button("重试") { action { try PersonalLearningCoordinator.shared.retry(job: job.id, context: context) } } }
                        if ["queued", "running", "failed"].contains(job.state) { Button(job.state == "failed" ? "忽略这次整理" : "取消整理", role: .cancel) { action { try PersonalLearningCoordinator.shared.cancel(job: job.id, context: context) } } }
                    }.padding(.vertical, 6)
                }
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }.navigationTitle("整理历史对话").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
        .task {
            do { _ = try PersonalKnowledgeStore.prepareConversation(context); model.refresh(context) } catch { self.error = error.localizedDescription }
        }
        .onReceive(NotificationCenter.default.publisher(for: .personalKnowledgeChanged)) { _ in model.refresh(context) }
    }
    private func action(_ work: () throws -> Void) { do { try work(); model.refresh(context) } catch { self.error = error.localizedDescription } }
    private func label(_ state: String) -> String {
        switch state { case "queued": return "等待整理"; case "running": return "整理中（离开 App 后暂停）"; case "completed": return "整理完成"; case "cancelled": return "已取消"; default: return "未完成，可重试" }
    }
}
