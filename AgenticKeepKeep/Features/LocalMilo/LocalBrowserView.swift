import SwiftUI
import SafariServices

struct LocalBrowserPage: Identifiable {
    let id = UUID()
    let url: URL
}

@MainActor
final class LocalBrowserSession: ObservableObject {
    @Published var page: LocalBrowserPage?
    private let retriever: PublicWebRetriever

    convenience init() {
        self.init(fetch: { url in try await PublicWebTransport.fetch(url) },
                  render: { url, kind in try await RenderedWebReader.render(url, kind: kind) })
    }

    init(fetch: @escaping PublicWebRetriever.Fetch, render: PublicWebRetriever.Render? = nil) {
        retriever = PublicWebRetriever(fetch: fetch, render: render)
    }

    func search(query: String, count: Int, health: Bool) async throws -> CoachToolResult {
        try await retriever.search(query: query, count: count, health: health)
    }

    func read(_ url: URL) async throws -> CoachToolResult { try await retriever.read(url) }

    func preview(_ url: URL) throws {
        guard LocalBrowserPolicy.allows(url) else { throw PublicWebError.unsafeAddress }
        page = LocalBrowserPage(url: url)
    }

    // Browsing never resolves or cancels a tool request.
    func closePreview() { page = nil }
}

/// A single Safari sheet, opened only by a source link. No hidden result sheet
/// underneath, and no confirmation required before the Agent can use results.
struct LocalBrowserView: UIViewControllerRepresentable {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator { dismiss() } }
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        private let close: () -> Void
        init(close: @escaping () -> Void) { self.close = close }
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) { close() }
    }
}
