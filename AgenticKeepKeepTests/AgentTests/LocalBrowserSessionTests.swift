import XCTest
@testable import AgenticKeepKeep

@MainActor final class LocalBrowserSessionTests: XCTestCase {
    func testSearchReturnsWithoutOpeningBrowserOrConfirmation() async throws {
        let session = LocalBrowserSession { url in
            (Data("<rss><channel><item><title>Swift</title><link>https://www.swift.org/</link><description>Documentation</description></item></channel></rss>".utf8), url)
        }
        let result = try await session.search(query: "Swift documentation", count: 10, health: false)
        XCTAssertFalse(result.failed)
        XCTAssertEqual(result.sources.count, 1)
        XCTAssertNil(session.page)
    }

    func testSearchFailureDoesNotDismissUserOpenedPage() async throws {
        let session = LocalBrowserSession { _ in throw PublicWebError.verification }
        let url = URL(string: "https://www.swift.org/")!
        try session.preview(url)
        do {
            _ = try await session.search(query: "Swift", count: 10, health: false)
            XCTFail("Expected verification error")
        } catch { XCTAssertEqual(error as? PublicWebError, .verification) }
        XCTAssertEqual(session.page?.url, url)
        session.closePreview()
        XCTAssertNil(session.page)
    }

    func testClosingPreviewDuringSearchDoesNotCancelRetrieval() async throws {
        let session = LocalBrowserSession { url in
            try await Task.sleep(nanoseconds: 50_000_000)
            return (Data("<rss><channel><item><title>Swift</title><link>https://www.swift.org/</link></item></channel></rss>".utf8), url)
        }
        try session.preview(URL(string: "https://www.swift.org/")!)
        let request = Task { try await session.search(query: "Swift", count: 10, health: false) }
        await Task.yield()
        session.closePreview()
        let result = try await request.value
        XCTAssertFalse(result.failed)
        XCTAssertNil(session.page)
    }

    func testSearchThenReadNeedsNoPresentationCallbacks() async throws {
        let session = LocalBrowserSession { url in
            if url.path == "/search" {
                return (Data("<rss><channel><item><title>Swift</title><link>https://www.swift.org/</link></item></channel></rss>".utf8), url)
            }
            return (Data(("<article>" + String(repeating: "Public documentation. ", count: 20) + "</article>").utf8), url)
        }
        let search = try await session.search(query: "Swift", count: 10, health: false)
        let article = try await session.read(search.sources[0])
        XCTAssertFalse(article.failed)
        XCTAssertTrue(article.content.contains("正文节选"))
        XCTAssertNil(session.page)
    }
}
