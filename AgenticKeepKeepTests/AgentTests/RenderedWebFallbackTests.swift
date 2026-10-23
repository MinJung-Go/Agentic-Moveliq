import XCTest
@testable import AgenticKeepKeep

final class RenderedWebFallbackTests: XCTestCase {
    private static var snapshot: RenderedWebSnapshot {
        .init(state: "ready", url: "https://www.bing.com/search?q=Swift", rows: [
            .init(title: "Swift documentation", url: "https://www.swift.org/", text: "Official Swift documentation")
        ], text: "")
    }
    private actor Counter {
        var value = 0
        func increment() { value += 1 }
    }

    func testSuccessfulPrimaryDoesNotRender() async throws {
        let count = Counter()
        let retriever = PublicWebRetriever(fetch: { url in
            (Data("<rss><channel><item><title>Swift</title><link>https://www.swift.org/</link></item></channel></rss>".utf8), url)
        }, render: { _, _ in await count.increment(); return Self.snapshot })
        let result = try await retriever.search(query: "Swift", count: 10, health: false)
        XCTAssertFalse(result.failed)
        let calls = await count.value
        XCTAssertEqual(calls, 0)
    }

    func testNetworkAndExtractionFailuresRenderOnce() async throws {
        for error in [PublicWebError.network, .extraction, .verification] {
            let count = Counter()
            let retriever = PublicWebRetriever(fetch: { _ in throw error }, render: { url, kind in
                XCTAssertEqual(kind, .search)
                XCTAssertFalse(url.absoluteString.contains("format=rss"))
                await count.increment(); return Self.snapshot
            })
            let result = try await retriever.search(query: "Swift", count: 10, health: false)
            XCTAssertFalse(result.failed)
            let calls = await count.value
            XCTAssertEqual(calls, 1)
        }
    }

    func testUnrelatedFeedUsesRenderedSearch() async throws {
        let retriever = PublicWebRetriever(fetch: { url in
            (Data("<rss><channel><item><title>Weather</title><link>https://www.swift.org/</link></item></channel></rss>".utf8), url)
        }, render: { _, _ in Self.snapshot })
        let result = try await retriever.search(query: "Swift", count: 10, health: false)
        XCTAssertEqual(result.sources.first?.host, "www.swift.org")
    }

    func testForbiddenAndCancelledRequestsNeverRender() async throws {
        let errors: [Error] = [PublicWebError.unsafeAddress, PublicWebError.privateQuery, PublicWebError.tooLarge, CancellationError()]
        for error in errors {
            let count = Counter()
            let retriever = PublicWebRetriever(fetch: { _ in throw error }, render: { _, _ in
                await count.increment(); return Self.snapshot
            })
            do { _ = try await retriever.search(query: "Swift", count: 10, health: false); XCTFail("Expected error") }
            catch { }
            let calls = await count.value
            XCTAssertEqual(calls, 0)
        }
    }

    func testRenderedFailureDoesNotRetryOrBecomeSuccess() async throws {
        let count = Counter()
        let retriever = PublicWebRetriever(fetch: { _ in throw PublicWebError.extraction }, render: { _, _ in
            await count.increment(); throw PublicWebError.verification
        })
        do { _ = try await retriever.search(query: "Swift", count: 10, health: false); XCTFail("Expected error") }
        catch { XCTAssertEqual(error as? PublicWebError, .verification) }
        let calls = await count.value
        XCTAssertEqual(calls, 1)
    }

    func testRenderedArticleRemainsMarkedAsExcerpt() async throws {
        let retriever = PublicWebRetriever(fetch: { _ in throw PublicWebError.extraction }, render: { url, kind in
            XCTAssertEqual(kind, .article)
            return .init(state: "ready", url: url.absoluteString, rows: [], text: String(repeating: "Public document. ", count: 30))
        })
        let result = try await retriever.read(URL(string: "https://www.swift.org/")!)
        XCTAssertFalse(result.failed)
        XCTAssertTrue(result.content.contains("正文节选"))
        XCTAssertEqual(result.sources.count, 1)
    }

    func testSnapshotRejectsVerificationUnknownAndOversizedData() throws {
        for state in ["verification", "unrecognized"] {
            XCTAssertThrowsError(try RenderedWebSnapshot.decode("{\"state\":\"\(state)\",\"url\":\"https://www.swift.org/\",\"rows\":[],\"text\":\"\"}"))
        }
        XCTAssertThrowsError(try RenderedWebSnapshot.decode(String(repeating: "x", count: 262_145)))
        let pending = RenderedWebSnapshot(state: "pending", url: "https://www.swift.org/", rows: [], text: "")
        XCTAssertThrowsError(try pending.searchResult(query: "Swift", count: 10, health: false))
    }

    func testPrivateQueryNeverReachesEitherChannel() async throws {
        let count = Counter()
        let retriever = PublicWebRetriever(fetch: { url in
            await count.increment(); return (Data(), url)
        }, render: { _, _ in await count.increment(); return Self.snapshot })
        do { _ = try await retriever.search(query: "我的手机号13800138000", count: 10, health: false); XCTFail("Expected privacy rejection") }
        catch { XCTAssertEqual(error as? PublicWebError, .privateQuery) }
        let calls = await count.value
        XCTAssertEqual(calls, 0)
    }

    func testCancellingRenderedFetchDoesNotReturnSources() async throws {
        let count = Counter()
        let retriever = PublicWebRetriever(fetch: { _ in throw PublicWebError.extraction }, render: { _, _ in
            await count.increment()
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return Self.snapshot
        })
        let task = Task { try await retriever.search(query: "Swift", count: 10, health: false) }
        while await count.value == 0 { await Task.yield() }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testContentRulesAllowOnlyExactHTTPSOrigin() throws {
        let json = try RenderedWebRules.json(for: URL(string: "https://www.swift.org/article")!)
        let rules = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        XCTAssertEqual((rules[0]["action"] as? [String: String])?["type"], "block")
        let pattern = try XCTUnwrap((rules[1]["trigger"] as? [String: String])?["url-filter"])
        let regex = try NSRegularExpression(pattern: pattern)
        for address in ["https://www.swift.org/", "https://www.swift.org:443/app.js"] {
            XCTAssertNotNil(regex.firstMatch(in: address, range: NSRange(address.startIndex..., in: address)))
        }
        for address in ["http://www.swift.org/", "https://www.swift.org.evil.test/", "https://127.0.0.1/", "https://other.test/", "https://www.swift.org:80/"] {
            XCTAssertNil(regex.firstMatch(in: address, range: NSRange(address.startIndex..., in: address)))
        }
    }
}
