import XCTest
import WebKit
@testable import AgenticKeepKeep

@MainActor final class RenderedWebKitTests: XCTestCase {
    private final class Navigation: NSObject, WKNavigationDelegate {
        let ready: XCTestExpectation
        init(ready: XCTestExpectation) { self.ready = ready }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ready.fulfill() }
    }

    private func load(_ html: String) async -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        let ready = expectation(description: "Fixture loaded")
        let delegate = Navigation(ready: ready)
        view.navigationDelegate = delegate
        view.loadHTMLString("<meta charset='utf-8'>" + html, baseURL: URL(string: "https://www.swift.org/"))
        await fulfillment(of: [ready], timeout: 5)
        view.navigationDelegate = nil
        return view
    }

    private func evaluate(_ view: WKWebView, kind: RenderedWebKind) async throws -> RenderedWebSnapshot {
        let json: String = try await withCheckedThrowingContinuation { continuation in
            view.evaluateJavaScript(RenderedWebScript.script(for: kind), in: nil, in: .defaultClient) { result in
                switch result {
                case .success(let value):
                    if let json = value as? String { continuation.resume(returning: json) }
                    else { continuation.resume(throwing: PublicWebError.extraction) }
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
        return try RenderedWebSnapshot.decode(json)
    }

    func testWebKitExtractsDynamicallyInsertedResult() async throws {
        let view = await load(#"""
        <div id="b_results"></div><script>
        setTimeout(() => document.getElementById('b_results').innerHTML = '<li class="b_algo"><h2><a href="https://www.swift.org/">Swift documentation</a></h2><p>Official guide</p></li>', 100);
        </script>
        """#)
        defer { view.stopLoading() }
        var snapshot = try await evaluate(view, kind: .search)
        for _ in 0..<10 where snapshot.state == "pending" {
            try await Task.sleep(nanoseconds: 200_000_000)
            snapshot = try await evaluate(view, kind: .search)
        }
        XCTAssertEqual(snapshot.state, "ready")
        XCTAssertEqual(snapshot.rows.first?.title, "Swift documentation")
    }

    func testWebKitRejectsChallenge() async throws {
        let view = await load("<main><h1>Verify you are human</h1></main>")
        defer { view.stopLoading() }
        do { _ = try await evaluate(view, kind: .search); XCTFail("Expected verification") }
        catch { XCTAssertEqual(error as? PublicWebError, .verification) }
    }

    func testCancelledReaderDoesNotStartNavigation() async throws {
        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await RenderedWebReader.render(URL(string: "https://www.swift.org/")!, kind: .article)
        }
        do { _ = try await operation.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testWebKitCompilesExactOriginRules() async throws {
        try await compileRules(for: URL(string: "https://www.swift.org/")!, kind: .article)
    }

    func testWebKitCompilesRegionalSearchRules() async throws {
        try await compileRules(for: URL(string: "https://www.bing.com/search?q=Swift")!, kind: .search)
    }

    private func compileRules(for url: URL, kind: RenderedWebKind) async throws {
        let identifier = "moveliq-test-" + UUID().uuidString
        defer { WKContentRuleListStore.default().removeContentRuleList(forIdentifier: identifier) { _ in } }
        let json = try RenderedWebRules.json(for: url, kind: kind)
        let rules: WKContentRuleList = try await withCheckedThrowingContinuation { continuation in
            WKContentRuleListStore.default().compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) { list, error in
                if let list { continuation.resume(returning: list) }
                else { continuation.resume(throwing: error ?? PublicWebError.extraction) }
            }
        }
        XCTAssertEqual(rules.identifier, identifier)
    }
}
