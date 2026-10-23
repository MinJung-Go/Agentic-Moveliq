import XCTest
@testable import AgenticKeepKeep

final class PublicWebRetrieverTests: XCTestCase {
    func testSuccessReturnsSourcesImmediately() async throws {
        let retriever = PublicWebRetriever { url in
            (Data("<rss><channel><item><title>Swift</title><link>https://www.swift.org/</link></item></channel></rss>".utf8), url)
        }
        let result = try await retriever.search(query: "Swift", count: 10, health: false)
        XCTAssertFalse(result.failed)
        XCTAssertEqual(result.sources, [URL(string: "https://www.swift.org/")!])
    }

    func testVerificationFailurePreservesReason() async throws {
        let retriever = PublicWebRetriever { _ in throw PublicWebError.verification }
        do {
            _ = try await retriever.search(query: "Swift", count: 10, health: false)
            XCTFail("Expected failure")
        } catch { XCTAssertEqual(error as? PublicWebError, .verification) }
    }

    func testEmptyAndMalformedResponsesAreNotSuccessful() async throws {
        let empty = PublicWebRetriever { url in (Data("<rss><channel/></rss>".utf8), url) }
        let result = try await empty.search(query: "Swift", count: 10, health: false)
        XCTAssertTrue(result.failed)
        XCTAssertTrue(result.sources.isEmpty)
        let malformed = PublicWebRetriever { url in (Data("<html>search page</html>".utf8), url) }
        do {
            _ = try await malformed.search(query: "Swift", count: 10, health: false)
            XCTFail("Expected extraction error")
        } catch { XCTAssertEqual(error as? PublicWebError, .extraction) }
    }

    func testCancellationWhileFetchingPropagates() async throws {
        actor State {
            var started = false
            func fetch(_ url: URL) async throws -> (Data, URL) {
                started = true
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return (Data("<rss><channel/></rss>".utf8), url)
            }
        }
        let state = State()
        let retriever = PublicWebRetriever { url in try await state.fetch(url) }
        let request = Task { try await retriever.search(query: "Swift", count: 10, health: false) }
        while !(await state.started) { await Task.yield() }
        request.cancel()
        do { _ = try await request.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testSubsequentSearchDoesNotReuseEarlierFailure() async throws {
        let retriever = PublicWebRetriever { url in
            if url.absoluteString.contains("first") { throw PublicWebError.network }
            return (Data("<rss><channel><item><title>Swift</title><link>https://www.swift.org/</link></item></channel></rss>".utf8), url)
        }
        do {
            _ = try await retriever.search(query: "first", count: 10, health: false)
            XCTFail("Expected network failure")
        } catch { XCTAssertEqual(error as? PublicWebError, .network) }
        let result = try await retriever.search(query: "Swift", count: 10, health: false)
        XCTAssertFalse(result.failed)
    }

    func testReaderReturnsExcerptWithoutConfirmation() async throws {
        let retriever = PublicWebRetriever { url in
            (Data(("<article>" + String(repeating: "Public documentation. ", count: 20) + "</article>").utf8), url)
        }
        let url = URL(string: "https://www.swift.org/")!
        let result = try await retriever.read(url)
        XCTAssertFalse(result.failed)
        XCTAssertEqual(result.sources, [url])
        XCTAssertTrue(result.content.contains("正文节选"))
    }

    func testReaderRejectsUnsafeFinalURL() async throws {
        let retriever = PublicWebRetriever { _ in (Data(), URL(string: "https://127.0.0.1/")!) }
        do {
            _ = try await retriever.read(URL(string: "https://www.swift.org/")!)
            XCTFail("Expected unsafe address")
        } catch { XCTAssertEqual(error as? PublicWebError, .unsafeAddress) }
    }
}
