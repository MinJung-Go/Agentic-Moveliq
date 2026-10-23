import Foundation
import XCTest
#if canImport(WebKit)
import WebKit
#endif
@testable import AgenticKeepKeep

final class LocalBrowserSearchTests: XCTestCase {
    func testContentRulesPreserveDomainAndProtocolBoundaries() throws {
        let rules = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(LocalBrowserPolicy.contentRulesJSON().utf8)) as? [[String: Any]])
        XCTAssertEqual((rules.first?["action"] as? [String: String])?["type"], "block")
        let patterns = try rules.dropFirst().map { rule -> NSRegularExpression in
            let trigger = try XCTUnwrap(rule["trigger"] as? [String: String])
            let pattern = try XCTUnwrap(trigger["url-filter"])
            XCTAssertFalse(pattern.contains("|"), "WebKit content filters do not support alternation")
            return try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        }
        func allowed(_ raw: String) -> Bool {
            patterns.contains { $0.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)) != nil }
        }
        for domain in LocalBrowserPolicy.domains {
            XCTAssertTrue(allowed("https://\(domain)/page"))
            XCTAssertTrue(allowed("https://sub.\(domain):443/page"))
            XCTAssertFalse(allowed("https://\(domain).evil.test/page"))
            XCTAssertFalse(allowed("https://evil\(domain)/page"))
        }
        for url in ["http://www.bing.com/", "https://www.bing.com:8443/", "https://127.0.0.1/", "https://user@bing.com/", "https://unknown.example/"] {
            XCTAssertFalse(allowed(url), url)
        }
    }

    func testRegionalSearchPagesAreNotTreatedAsArticleBodies() throws {
        for host in ["www.bing.com", "cn.bing.com", "bing.com"] {
            XCTAssertTrue(LocalBrowserPolicy.isSearchPage(try XCTUnwrap(URL(string: "https://\(host)/search?q=sleep"))))
        }
        for raw in ["https://cn.bing.com/", "https://www.bing.com/ck/a", "https://bing.com.evil.test/search", "https://www.nhs.uk/search", "http://cn.bing.com/search"] {
            XCTAssertFalse(LocalBrowserPolicy.isSearchPage(try XCTUnwrap(URL(string: raw))))
        }
    }

    func testRegionalWrappedResultsRespectSourceAllowlist() {
        for destination in ["https://www.nhs.uk/live-well/", "https://127.0.0.1/private", "https://unknown.example/page"] {
            let encoded = Data(destination.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            let result = LocalBrowserPolicy.sourceURL("https://cn.bing.com/ck/a?u=a1" + encoded)
            if destination.contains("www.nhs.uk") { XCTAssertEqual(result?.absoluteString, destination) }
            else { XCTAssertNil(result) }
        }
    }

    #if canImport(WebKit)
    @MainActor func testProductionContentRulesCompileInWebKit() async throws {
        let identifier = "moveliq-browser-test-" + UUID().uuidString
        let store = WKContentRuleListStore.default()!
        let list = try await store.compileContentRuleList(forIdentifier: identifier,
                                                         encodedContentRuleList: LocalBrowserPolicy.contentRulesJSON())
        XCTAssertNotNil(list)
        try await store.removeContentRuleList(forIdentifier: identifier)
    }
    #endif

    func testEveryGeneratedSearchPassesNavigationPolicy() {
        for topic in FitnessSearchTopic.allCases {
            let url = LocalBrowserPolicy.searchURL(topic: topic)
            XCTAssertTrue(LocalBrowserPolicy.allows(url), "Search blocked before loading: \(topic.rawValue)")
            XCTAssertFalse(url.absoluteString.contains("("))
            XCTAssertFalse(url.absoluteString.contains(")"))
        }
    }

    func testQueryRoundTripRetainsPublicTopicAndSiteGrouping() throws {
        let sites = " (site:mayoclinic.org OR site:nhs.uk OR site:who.int OR site:nih.gov OR site:acefitness.org OR site:acsm.org)"
        for topic in FitnessSearchTopic.allCases {
            let url = LocalBrowserPolicy.searchURL(topic: topic)
            let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            XCTAssertEqual(parts.scheme, "https")
            XCTAssertEqual(parts.host, "www.bing.com")
            XCTAssertEqual(parts.path, "/search")
            XCTAssertEqual(parts.queryItems, [URLQueryItem(name: "q", value: topic.query + sites)])
            XCTAssertTrue(url.absoluteString.contains("%28"))
            XCTAssertTrue(url.absoluteString.contains("%29"))
            XCTAssertFalse(url.absoluteString.contains("%2528"))
        }
    }

    func testEncodingFixDoesNotRelaxNavigationPolicy() throws {
        for raw in ["http://www.bing.com/search", "https://bing.com.evil.test/search",
                    "https://127.0.0.1/search", "https://user:password@www.bing.com/search",
                    "https://www.bing.com:8443/search", "https://www.bing.com/search?q=(sleep)",
                    "file:///private/data"] {
            XCTAssertFalse(LocalBrowserPolicy.allows(try XCTUnwrap(URL(string: raw))), raw)
        }
    }
}
