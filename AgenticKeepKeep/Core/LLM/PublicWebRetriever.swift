import Foundation

/// Tool retrieval is independent of Safari presentation. Results return directly
/// to the Agent; cancellation belongs to the caller's conversation task.
struct PublicWebRetriever {
    typealias Fetch = @Sendable (URL) async throws -> (Data, URL)
    typealias Render = @Sendable (URL, RenderedWebKind) async throws -> RenderedWebSnapshot
    let fetch: Fetch
    var render: Render? = nil

    private func mayRender(_ error: Error) -> Bool {
        guard !Task.isCancelled, let error = error as? PublicWebError else { return false }
        return [.network, .extraction, .verification].contains(error)
    }

    func search(query: String, count: Int, health: Bool) async throws -> CoachToolResult {
        let query = try PublicSearchArguments(query: query, purpose: nil, topic: nil, count: count).validatedQuery()
        try Task.checkCancellation()
        do {
            let (data, _) = try await fetch(LocalBrowserPolicy.searchURL(query: query, feed: true))
            try Task.checkCancellation()
            let result = try PublicSearchFeed.decode(data, count: count, health: health, query: query)
            if !result.failed || render == nil { return result }
        } catch {
            guard render != nil, mayRender(error) else { throw error }
        }
        try Task.checkCancellation()
        guard let render else { throw PublicWebError.extraction }
        let snapshot = try await render(LocalBrowserPolicy.searchURL(query: query), .search)
        try Task.checkCancellation()
        return try snapshot.searchResult(query: query, count: count, health: health)
    }

    func read(_ url: URL) async throws -> CoachToolResult {
        guard LocalBrowserPolicy.allows(url) else { throw PublicWebError.unsafeAddress }
        try Task.checkCancellation()
        do {
            let (data, finalURL) = try await fetch(url)
            try Task.checkCancellation()
            guard LocalBrowserPolicy.allows(finalURL) else { throw PublicWebError.unsafeAddress }
            guard let html = String(data: data, encoding: .utf8) else { throw PublicWebError.extraction }
            return try PublicWebDocument.extract(html, url: finalURL)
        } catch {
            guard render != nil, mayRender(error) else { throw error }
        }
        try Task.checkCancellation()
        guard let render else { throw PublicWebError.extraction }
        let snapshot = try await render(url, .article)
        try Task.checkCancellation()
        return try snapshot.articleResult()
    }
}
