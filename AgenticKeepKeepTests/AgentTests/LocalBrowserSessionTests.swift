import XCTest
@testable import AgenticKeepKeep

@MainActor final class LocalBrowserSessionTests: XCTestCase {
    private func waitFor(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<200 { if condition() { return }; try await Task.sleep(nanoseconds: 5_000_000) }
        XCTFail("Browser state did not settle")
        throw NSError(domain: "BrowserTestTimeout", code: 1)
    }
    func testSuccessStaysPresentedUntilUserUsesSources() async throws {
        let session = LocalBrowserSession { url in
            (Data("<rss><channel><item><title>Swift</title><link>https://www.swift.org/</link><description>Documentation</description></item></channel></rss>".utf8), url)
        }
        let request = Task { try await session.search(query: "Swift documentation", count: 10, health: false) }
        try await waitFor { session.canUse }
        XCTAssertTrue(session.isPresented); XCTAssertEqual(session.result?.sources.count, 1)
        session.accept(); session.presentationDidDismiss()
        let result = try await request.value
        XCTAssertFalse(result.failed); XCTAssertFalse(session.isPresented)
    }
    func testFailureRetainsBrowserAndRetryCanRecover() async throws {
        actor Attempt {
            var count = 0
            func fetch(_ url: URL) throws -> (Data, URL) {
                count += 1
                if count == 1 { throw PublicWebError.verification }
                return (Data("<rss><channel><item><title>Swift</title><link>https://www.swift.org/</link></item></channel></rss>".utf8), url)
            }
        }
        let attempt = Attempt(), session = LocalBrowserSession { url in try await attempt.fetch(url) }
        let request = Task { try await session.search(query: "Swift", count: 10, health: false) }
        try await waitFor { session.notice != nil }
        XCTAssertTrue(session.isPresented); XCTAssertFalse(session.canUse); XCTAssertNotNil(session.url)
        session.retry()
        try await waitFor { session.canUse }
        session.accept(); session.presentationDidDismiss(); let result = try await request.value; XCTAssertFalse(result.failed)
    }
    func testCancellationDoesNotLeakResultIntoNextSearch() async throws {
        let session = LocalBrowserSession { url in
            try await Task.sleep(nanoseconds: 100_000_000)
            return (Data("<rss><channel/></rss>".utf8), url)
        }
        let first = Task { try await session.search(query: "first", count: 10, health: false) }
        try await waitFor { session.isPresented }
        session.cancel()
        do { _ = try await first.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
        let second = Task { try await session.search(query: "second", count: 10, health: false) }
        try await waitFor { session.notice != nil }
        XCTAssertTrue(session.url?.absoluteString.contains("second") == true)
        XCTAssertTrue(session.isPresented)
        session.returnWithoutSources(); session.presentationDidDismiss()
        let result = try await second.value
        XCTAssertTrue(result.failed); XCTAssertTrue(result.sources.isEmpty)
    }
    func testSearchDismissalDoesNotCancelFollowUpRead() async throws {
        let session = LocalBrowserSession { url in
            if url.path == "/search" { return (Data("<rss><channel><item><title>Swift</title><link>https://www.swift.org/</link></item></channel></rss>".utf8), url) }
            return (Data(("<article>" + String(repeating: "Public documentation. ", count: 20) + "</article>").utf8), url)
        }
        let search = Task { try await session.search(query: "Swift", count: 10, health: false) }
        try await waitFor { session.canUse }
        session.accept()
        XCTAssertFalse(session.isPresented)
        session.presentationDidDismiss()
        let results = try await search.value
        let read = Task { try await session.read(results.sources[0]) }
        try await waitFor { session.canUse }
        session.presentationDidDismiss() // A redundant old callback cannot cancel the new request.
        XCTAssertTrue(session.isPresented)
        session.accept(); session.presentationDidDismiss()
        let article = try await read.value
        XCTAssertFalse(article.failed); XCTAssertTrue(article.content.contains("正文节选"))
    }

}
