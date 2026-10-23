import SwiftUI
import SafariServices

@MainActor
final class LocalBrowserSession: ObservableObject {
    @Published var isPresented = false
    @Published var loading = false
    @Published var notice: String?
    @Published var title = "网页搜索"
    @Published private(set) var url: URL?
    @Published private(set) var result: CoachToolResult?
    @Published private(set) var generation = UUID()
    private(set) var opensSafari = false
    typealias Fetch = @Sendable (URL) async throws -> (Data, URL)
    private let fetch: Fetch
    init(fetch: @escaping Fetch = PublicWebTransport.fetch) { self.fetch = fetch }
    private var continuation: CheckedContinuation<CoachToolResult, Error>?
    private var pendingDismissal: (CheckedContinuation<CoachToolResult, Error>, Result<CoachToolResult, Error>)?
    private var worker: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var mode: Mode = .preview
    enum Mode { case search(String, Int, Bool), read, preview }

    func search(query: String, count: Int, health: Bool) async throws -> CoachToolResult {
        try await open(LocalBrowserPolicy.searchURL(query: query), mode: .search(query, count, health))
    }
    func preview(_ url: URL) async throws { _ = try await open(url, mode: .preview) }
    func read(_ url: URL) async throws -> CoachToolResult { try await open(url, mode: .read) }
    private func open(_ url: URL, mode: Mode) async throws -> CoachToolResult {
        guard LocalBrowserPolicy.allows(url) else { throw PublicWebError.unsafeAddress }
        guard continuation == nil, pendingDismissal == nil else { throw LLMError.network("请先完成当前网页读取") }
        try Task.checkCancellation()
        self.mode = mode; self.url = url; result = nil; notice = nil
        title = "网页搜索"
        if case .read = mode { title = "阅读来源"; opensSafari = false } else { opensSafari = true }
        let current = UUID(); generation = current
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                continuation = cont; isPresented = true
                retry()
                deadline = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 180_000_000_000)
                    guard !Task.isCancelled, let self, self.generation == current else { return }
                    self.worker?.cancel(); self.loading = false
                    self.notice = "本次读取已超时。网页仍可浏览；返回聊天后可重新发起搜索。"
                    self.resolve(.success(.init(content: "网页操作超时，未核实来源。", failed: true)), dismiss: false)
                }
            }
        } onCancel: { Task { @MainActor in if self.generation == current { self.cancel() } } }
    }
    func retry() {
        guard continuation != nil, let url else { return }
        worker?.cancel(); result = nil; notice = nil
        if case .preview = mode { loading = false; return }
        loading = true
        let current = generation
        worker = Task {
            do {
                let value: CoachToolResult
                switch mode {
                case let .search(query, count, health):
                    let (data, _) = try await fetch(LocalBrowserPolicy.searchURL(query: query, feed: true))
                    value = try PublicSearchFeed.decode(data, count: count, health: health, query: query)
                case .read:
                    let (data, finalURL) = try await fetch(url)
                    guard let html = String(data: data, encoding: .utf8) else { throw PublicWebError.extraction }
                    value = try PublicWebDocument.extract(html, url: finalURL)
                case .preview: return
                }
                try Task.checkCancellation()
                guard generation == current else { return }
                result = value; loading = false
                if value.failed { notice = value.content }
            } catch is CancellationError { }
            catch {
                guard !Task.isCancelled, generation == current else { return }
                loading = false; notice = error.localizedDescription
            }
        }
    }
    var isPreview: Bool { if case .preview = mode { return true }; return false }
    var canUse: Bool { continuation != nil && !loading && result?.failed == false }
    var canRetry: Bool { continuation != nil && !loading && !isPreview }
    var actionTitle: String { if case .search = mode { return "使用搜索结果" }; return "让 Milo 使用正文节选" }
    func accept() { if canUse, let result { resolve(.success(result), dismiss: true, afterDismissal: true) } }
    func cancel() {
        if let (cont, _) = pendingDismissal { pendingDismissal = nil; cont.resume(throwing: CancellationError()) }
        resolve(.failure(CancellationError()), dismiss: true)
    }
    /// Resume the Agent only after SwiftUI finishes dismissing the sheet. Otherwise
    /// a follow-up read can be cancelled by the preceding search's onDismiss.
    func presentationDidDismiss() {
        guard let (cont, value) = pendingDismissal else { return }
        pendingDismissal = nil
        cont.resume(with: value)
    }
    func returnWithoutSources() {
        if isPreview { resolve(.success(.init(content: "用户已浏览来源，未读取正文。")), dismiss: true, afterDismissal: true) }
        else { resolve(.success(.init(content: notice ?? "用户返回聊天，本次未使用搜索结果或正文。", failed: true)), dismiss: true, afterDismissal: true) }
    }
    private func resolve(_ value: Result<CoachToolResult, Error>, dismiss: Bool, afterDismissal: Bool = false) {
        worker?.cancel(); worker = nil; deadline?.cancel(); deadline = nil; loading = false
        let cont = continuation; continuation = nil
        if afterDismissal, isPresented, let cont { pendingDismissal = (cont, value) }
        else { cont?.resume(with: value) }
        if dismiss { isPresented = false }
    }
}

private struct SafariPage: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
private struct BrowsingPage: Identifiable { let id = UUID(); let url: URL }
struct LocalBrowserView: View {
    @ObservedObject var browser: LocalBrowserSession
    @State private var page: BrowsingPage?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label(browser.isPreview ? "查看来源" : "公共资料", systemImage: "globe").font(.title3.weight(.medium))
                    if browser.loading { HStack { ProgressView(); Text("正在获取公开资料…").font(.subheadline) } }
                    if let notice = browser.notice { Text(notice).font(.subheadline).foregroundStyle(Theme.secondaryLabel) }
                    if let url = browser.url {
                        Button { page = .init(url: url) } label: { Label("在 Safari 中浏览", systemImage: "safari") }
                            .frame(minHeight: 44)
                    }
                    if let result = browser.result, !result.failed {
                        if result.sourcePreviews.isEmpty {
                            Text(result.content).font(.subheadline).foregroundStyle(Theme.Journal.label).textSelection(.enabled)
                            ForEach(result.sources, id: \.self) { url in
                                Button { page = .init(url: url) } label: { Label(url.host ?? "查看来源", systemImage: "arrow.up.right") }.frame(minHeight: 44)
                            }
                        } else {
                            Text("找到 \(result.sources.count) 个来源 · 摘要").font(.caption).foregroundStyle(Theme.secondaryLabel)
                            ForEach(Array(result.sourcePreviews.enumerated()), id: \.element.id) { index, source in
                                VStack(alignment: .leading, spacing: 8) {
                                    Button { page = .init(url: source.url) } label: {
                                        HStack(alignment: .top) {
                                            Text(source.title).font(.body.weight(.medium)).multilineTextAlignment(.leading)
                                            Spacer(minLength: 8); Image(systemName: "arrow.up.right").font(.caption)
                                        }.frame(minHeight: 44)
                                    }
                                    Text("[\(index + 1)] \(source.url.host ?? "网页")").font(.caption).foregroundStyle(Theme.secondaryLabel)
                                    Text(source.summary).font(.subheadline).foregroundStyle(Theme.Journal.label).textSelection(.enabled)
                                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                    if browser.canRetry { Button("重新获取") { browser.retry() }.frame(minHeight: 44) }
                    Text("Safari 用于浏览；Milo 通过独立通道读取公开资料，不能读取你的 Safari 页面或登录内容。搜索摘要不等于网页全文。")
                        .font(.caption).foregroundStyle(Theme.secondaryLabel)
                }.padding(20)
            }
            .background(Theme.canvas).foregroundStyle(Theme.Journal.label)
            .safeAreaInset(edge: .bottom) {
                if !browser.isPreview {
                    Button(browser.actionTitle) { browser.accept() }.buttonStyle(PrimaryButtonStyle())
                        .disabled(!browser.canUse).padding(16).background(Theme.canvas)
                }
            }
            .navigationTitle(browser.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("返回对话") { browser.returnWithoutSources() } } }
            .sheet(item: $page) { SafariPage(url: $0.url).ignoresSafeArea() }
            .task(id: browser.generation) {
                if browser.opensSafari, let url = browser.url { page = .init(url: url) }
            }
        }.tint(Theme.accent).interactiveDismissDisabled()
    }
}
