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

    func testSearchAllowsRegionalRedirectAndKeepsPublicSearchBoundary() throws {
        let policy = try RenderedWebPolicy(url: URL(string: "https://www.bing.com/search?q=Swift")!, kind: .search)
        for address in ["https://cn.bing.com/search?q=Swift", "https://bing.com/search?q=Swift", "https://www.bing.com:443/search?q=Swift"] {
            XCTAssertTrue(policy.allowsNavigation(URL(string: address)!), address)
        }
        for address in ["http://cn.bing.com/search", "https://cn.bing.com:8443/search", "https://cn.bing.com.evil.org/search",
                        "https://user:secret@cn.bing.com/search", "https://www.swift.org/search", "https://127.0.0.1/search",
                        "https://r.bing.com/search", "https://cn.bing.com/ck/a", "https://cn.bing.com/search/redirect"] {
            XCTAssertFalse(policy.allowsNavigation(URL(string: address)!), address)
        }
    }

    func testArticleDoesNotGainSearchRedirectOrAssetPrivileges() throws {
        let policy = try RenderedWebPolicy(url: URL(string: "https://www.bing.com/article")!, kind: .article)
        XCTAssertTrue(policy.allowsNavigation(URL(string: "https://www.bing.com/other")!))
        XCTAssertFalse(policy.allowsNavigation(URL(string: "https://cn.bing.com/search")!))
        XCTAssertFalse(policy.allowsNavigation(URL(string: "https://r.bing.com/rp/app.js")!))
        XCTAssertEqual(policy.addressChecks.map(\.host), ["www.bing.com"])
        XCTAssertThrowsError(try RenderedWebPolicy(url: URL(string: "https://www.swift.org/search")!, kind: .search))
    }

    func testSearchPreflightsEveryPermittedHost() throws {
        let policy = try RenderedWebPolicy(url: URL(string: "https://www.bing.com/search?q=Swift")!, kind: .search)
        XCTAssertEqual(Set(policy.addressChecks.compactMap(\.host)), ["bing.com", "www.bing.com", "cn.bing.com"])
    }

    func testSearchContentRulesPermitRegionalDocumentsButKeepOtherResourcesBlocked() throws {
        let json = try RenderedWebRules.json(for: URL(string: "https://www.bing.com/search?q=Swift")!, kind: .search)
        let rules = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        // Evaluate the ordered production rules for representative requests.
        func blocked(_ address: String, _ type: String) throws -> Bool {
            var blocked = false
            for rule in rules {
                let trigger = try XCTUnwrap(rule["trigger"] as? [String: Any])
                if let types = trigger["resource-type"] as? [String], !types.contains(type) { continue }
                let regex = try NSRegularExpression(pattern: XCTUnwrap(trigger["url-filter"] as? String))
                guard regex.firstMatch(in: address, range: NSRange(address.startIndex..., in: address)) != nil else { continue }
                blocked = (rule["action"] as? [String: String])?["type"] == "block"
            }
            return blocked
        }
        XCTAssertFalse(try blocked("https://cn.bing.com/search?q=Swift", "document"))
        XCTAssertFalse(try blocked("https://www.bing.com/search?q=Swift", "document"))
        for (address, type) in [("https://r.bing.com/rp/search.js", "script"), ("https://r.bing.com:443/rp/search.css", "style-sheet"),
                                ("https://r.bing.com/rp/search.js", "document"), ("https://r.bing.com/rp/data", "raw"),
                                ("https://r.bing.com/other/search.js", "script"), ("https://r.bing.com.evil.org/rp/app.js", "script"),
                                ("https://other.org/app.js", "script"), ("http://cn.bing.com/search", "document"),
                                ("https://user:secret@cn.bing.com/search", "document"), ("https://cn.bing.com/image.png", "image"),
                                ("https://cn.bing.com/font.woff", "font"), ("https://127.0.0.1/", "document")] {
            XCTAssertTrue(try blocked(address, type), address + " " + type)
        }
    }

    func testRegionalRenderedResultReturnsSourcesAfterFeedFailure() async throws {
        let retriever = PublicWebRetriever(fetch: { _ in throw PublicWebError.extraction }, render: { _, _ in
            var snapshot = Self.snapshot
            snapshot.url = "https://cn.bing.com/search?q=Swift"
            return snapshot
        })
        let result = try await retriever.search(query: "Swift", count: 10, health: false)
        XCTAssertFalse(result.failed)
        XCTAssertEqual(result.sources.first?.host, "www.swift.org")
    }

    func testRegionalPageDoesNotTurnStrengthDefinitionsIntoNews() throws {
        let snapshot = RenderedWebSnapshot(state: "ready", url: "https://cn.bing.com/search?q=力量新闻", rows: [
            .init(title: "力量（汉语词语）", url: "https://baike.baidu.com/item/力量/3110", text: "力量的释义为力气、能力。"),
            .init(title: "力量（状态效果）", url: "https://zh.minecraft.wiki/w/力量", text: "Minecraft 力量状态效果。")
        ], text: "")
        let result = try snapshot.searchResult(query: "力量新闻", count: 10, health: false)
        XCTAssertTrue(result.failed)
        XCTAssertTrue(result.sources.isEmpty)
        XCTAssertTrue(result.content.contains("不匹配"))
    }
}
