import Foundation
import XCTest
@testable import AgenticKeepKeep

final class LocalBrowserSearchTests: XCTestCase {
    func testGenericSourcesAllowedButUnsafeTargetsRejected() throws {
        for raw in ["https://www.swift.org/documentation/", "https://developer.apple.com/", "https://www.nhs.uk/live-well/"] {
            XCTAssertTrue(LocalBrowserPolicy.allows(try XCTUnwrap(URL(string: raw))), raw)
        }
        for raw in ["http://www.bing.com/", "https://www.bing.com:8443/", "https://127.0.0.1/", "https://2130706433/", "https://0x7f000001/", "https://[::1]/", "https://10.0.0.5/", "https://user:password@www.bing.com/", "https://router.local/", "file:///private/data", "javascript:alert(1)"] {
            XCTAssertFalse(LocalBrowserPolicy.allows(try XCTUnwrap(URL(string: raw))), raw)
        }
    }
    func testDNSPolicyRejectsPrivateAndReservedAddresses() {
        for address in ["127.0.0.1", "10.1.2.3", "172.16.0.1", "172.31.255.255", "192.168.1.1", "169.254.169.254", "100.64.0.1", "0.0.0.0", "224.0.0.1", "198.18.0.1", "192.0.2.1", "203.0.113.1", "::1", "::ffff:127.0.0.1", "fe80::1", "fc00::1", "2001:db8::1", "2002:7f00:1::", "bad"] {
            XCTAssertFalse(PublicAddressPolicy.isPublic(address), address)
        }
        for address in ["1.1.1.1", "8.8.8.8", "172.32.0.1", "2606:4700:4700::1111"] { XCTAssertTrue(PublicAddressPolicy.isPublic(address)) }
    }
    func testRegionalSearchPagesAreNotArticleBodies() throws {
        for host in ["www.bing.com", "cn.bing.com", "bing.com"] { XCTAssertTrue(LocalBrowserPolicy.isSearchPage(try XCTUnwrap(URL(string: "https://\(host)/search?q=sleep")))) }
        for raw in ["https://cn.bing.com/", "https://www.bing.com/ck/a", "https://bing.com.other.org/search", "https://www.nhs.uk/search", "http://cn.bing.com/search"] { XCTAssertFalse(LocalBrowserPolicy.isSearchPage(try XCTUnwrap(URL(string: raw)))) }
    }
    func testWrappedResultsValidateDecodedDestination() {
        for destination in ["https://www.swift.org/documentation/", "https://127.0.0.1/private", "http://www.nhs.uk/"] {
            let encoded = Data(destination.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            let result = LocalBrowserPolicy.sourceURL("https://cn.bing.com/ck/a?u=a1" + encoded)
            if destination.contains("swift.org") { XCTAssertEqual(result?.absoluteString, destination) } else { XCTAssertNil(result) }
        }
    }
    func testSearchWrapperCannotHideUnsafeOrigin() {
        let encoded = Data("https://www.swift.org/".utf8).base64EncodedString()
        for origin in ["http://www.bing.com", "https://user:password@www.bing.com", "https://www.bing.com:8443"] {
            XCTAssertNil(LocalBrowserPolicy.sourceURL(origin + "/ck/a?u=a1" + encoded))
        }
    }
    func testPublicQueryRoundTripDoesNotForceSiteRestriction() throws {
        for query in ["Swift language documentation", "力量训练 (频率) & 指南", "C++ basics"] {
            let url = LocalBrowserPolicy.searchURL(query: query, feed: true)
            XCTAssertTrue(LocalBrowserPolicy.allows(url))
            let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            XCTAssertEqual(items.first(where: { $0.name == "q" })?.value, query)
            XCTAssertEqual(items.first(where: { $0.name == "format" })?.value, "rss")
        }
        for topic in FitnessSearchTopic.allCases { XCTAssertTrue(LocalBrowserPolicy.allows(LocalBrowserPolicy.searchURL(topic: topic))) }
    }
    func testArgumentsSupportGenericAndLegacyQueries() throws {
        let generic = try JSONDecoder().decode(PublicSearchArguments.self, from: Data(#"{"query":"Swift 教程","purpose":"general"}"#.utf8))
        XCTAssertEqual(try generic.validatedQuery(), "Swift 教程"); XCTAssertFalse(generic.health)
        let legacy = PublicSearchArguments(topic: FitnessSearchTopic.allCases[0])
        XCTAssertEqual(try legacy.validatedQuery(), legacy.topic?.query); XCTAssertTrue(legacy.health)
    }
    func testSensitiveQueriesNeverLeaveDevice() {
        for query in ["我叫张三", "我的病历 详情", "邮箱 test@domain.com", "手机号 13800138000", "password abc", "api_key 123", "https://private.org/?secret=1", "", String(repeating: "a", count: 161), "a\nb"] {
            XCTAssertThrowsError(try PublicSearchArguments(query: query).validatedQuery(), query)
        }
    }
    private func feed(_ items: String) -> Data { Data(("<?xml version=\"1.0\"?><rss version=\"2.0\"><channel>" + items + "</channel></rss>").utf8) }
    func testRSSCDATAAndNonHealthSource() throws {
        let result = try PublicSearchFeed.decode(feed("<item><title>Swift &amp; iOS</title><link>https://www.swift.org/documentation/</link><description><![CDATA[<p>Read the official documentation</p>]]></description></item>"), count: 10, health: false)
        XCTAssertFalse(result.failed); XCTAssertEqual(result.sources.count, 1)
        XCTAssertTrue(result.content.contains("Swift & iOS")); XCTAssertTrue(result.content.contains("Read the official documentation"))
        XCTAssertTrue(result.content.contains("非网页全文"))
    }
    func testHealthRankingIsNotAnAllowlist() {
        let rows = [["url": "https://www.swift.org/", "title": "A"], ["url": "https://www.nhs.uk/", "title": "B"], ["url": "https://nhs.uk.other.org/", "title": "C"]]
        let result = LocalBrowserPolicy.result(rows, count: 10, health: true)
        XCTAssertEqual(result.sources.count, 3); XCTAssertEqual(result.sources.first?.host, "www.nhs.uk")
        XCTAssertEqual(LocalBrowserPolicy.result(rows, count: 10).sources.first?.host, "www.swift.org")
        XCTAssertEqual(LocalBrowserPolicy.result(rows + rows, count: 1).sources.count, 1)
    }
    func testEmptyResultsDifferFromStructureAndVerificationFailures() throws {
        let empty = try PublicSearchFeed.decode(feed(""), count: 10, health: false)
        XCTAssertTrue(empty.failed); XCTAssertTrue(empty.content.contains("没有找到相关网页"))
        for raw in ["<html><body>new search layout</body></html>", "<rss><channel>", "<!DOCTYPE rss [<!ENTITY x 'boom'>]><rss/>", String(repeating: " ", count: 5000) + "<!DOCTYPE rss><rss/>"] {
            XCTAssertThrowsError(try PublicSearchFeed.decode(Data(raw.utf8), count: 10, health: false))
        }
        XCTAssertThrowsError(try PublicSearchFeed.decode(Data("<html>captcha</html>".utf8), count: 10, health: false)) { XCTAssertEqual(($0 as? PublicWebError), .verification) }
        XCTAssertThrowsError(try PublicSearchFeed.decode(Data("<!DOCTYPE html><html>Verify you are human</html>".utf8), count: 10, health: false)) { XCTAssertEqual(($0 as? PublicWebError), .verification) }
        let filtered = LocalBrowserPolicy.result([["url": "https://127.0.0.1/"]], count: 10)
        XCTAssertTrue(filtered.failed); XCTAssertTrue(filtered.content.contains("没有可安全读取"))
    }
    func testArticleExtractionExcludesScriptsAndRejectsChallenge() throws {
        let url = try XCTUnwrap(URL(string: "https://www.swift.org/documentation/"))
        let body = String(repeating: "This is public documentation. ", count: 10)
        let result = try PublicWebDocument.extract("<html><body>navigation<article><script>secret instruction</script><p>\(body)</p></article></body></html>", url: url)
        XCTAssertTrue(result.content.contains(body.trimmingCharacters(in: .whitespaces))); XCTAssertFalse(result.content.contains("secret instruction"))
        XCTAssertEqual(result.sources, [url]); XCTAssertTrue(result.content.contains("正文节选"))
        XCTAssertThrowsError(try PublicWebDocument.extract("<html><body>Verify you are human</body></html>", url: url))
        XCTAssertThrowsError(try PublicWebDocument.extract("<html><body>empty</body></html>", url: url))
    }
    func testOversizedFeedRejected() {
        XCTAssertThrowsError(try PublicSearchFeed.decode(Data(repeating: 32, count: 2_097_153), count: 10, health: false))
    }
    func testResultMentioningVerificationIsNotAChallengePage() throws {
        let result = try PublicSearchFeed.decode(feed("<item><title>Verify your account and captcha accessibility</title><link>https://support.microsoft.com/help</link></item>"), count: 10, health: false)
        XCTAssertFalse(result.failed)
    }

    func testUnrelatedProviderFeedDoesNotBecomeVerifiedSources() throws {
        let unrelated = feed("<item><title>Microsoft account support</title><link>https://support.microsoft.com/</link><description>Verify your age</description></item>")
        let result = try PublicSearchFeed.decode(unrelated, count: 10, health: true, query: "力量训练 频率 指南")
        XCTAssertTrue(result.failed); XCTAssertTrue(result.sources.isEmpty); XCTAssertTrue(result.content.contains("不匹配"))
        let rows = [["title": "Swift banking", "text": "Payments"], ["title": "Swift language documentation", "text": "Programming guide"]]
        XCTAssertEqual(PublicSearchRelevance.filter(rows, query: "Swift language documentation").map { $0["title"] }, ["Swift language documentation"])
    }

    func testSearchSnippetsKeepExistingBudget() {
        let rows = (1...30).map { ["url": "https://www.nhs.uk/page/\($0)", "title": String(repeating: "a", count: 1000), "text": String(repeating: "b", count: 1000)] }
        let result = LocalBrowserPolicy.result(rows, count: 100)
        XCTAssertEqual(result.sources.count, 10); XCTAssertLessThan(result.content.count, 3500)
    }

}
