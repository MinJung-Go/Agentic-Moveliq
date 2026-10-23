import Foundation
import XCTest
@testable import AgenticKeepKeep

final class LocalBrowserSearchTests: XCTestCase {
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
