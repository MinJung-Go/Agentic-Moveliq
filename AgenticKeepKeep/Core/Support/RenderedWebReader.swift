import Foundation
import WebKit

/// One isolated rendering operation per fallback. No App message handlers,
/// persistent cookies, UI presentation or shared continuation with Safari.
@MainActor
final class RenderedWebReader: NSObject, WKNavigationDelegate, WKUIDelegate {
    private let url: URL
    private let kind: RenderedWebKind
    private let policy: RenderedWebPolicy
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<RenderedWebSnapshot, Error>?
    private var setup: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var polling: Task<Void, Never>?
    private var navigations = 0
    private var redirects = 0
    private let ruleID = "moveliq-reader-" + UUID().uuidString

    private init(url: URL, kind: RenderedWebKind) throws {
        self.url = url
        self.kind = kind
        self.policy = try RenderedWebPolicy(url: url, kind: kind)
    }

    static func render(_ url: URL, kind: RenderedWebKind) async throws -> RenderedWebSnapshot {
        try Task.checkCancellation()
        let reader = try RenderedWebReader(url: url, kind: kind)
        return try await reader.run()
    }

    private func run() async throws -> RenderedWebSnapshot {
        try Task.checkCancellation()
        guard LocalBrowserPolicy.allows(url) else { throw PublicWebError.unsafeAddress }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                deadline = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 25_000_000_000)
                    guard !Task.isCancelled else { return }
                    self?.finish(.failure(PublicWebError.renderTimeout))
                }
                setup = Task { [self] in
                    do {
                        let addresses = policy.addressChecks
                        try await Task.detached {
                            for address in addresses { try PublicWebTransport.checkAddress(address) }
                        }.value
                        try Task.checkCancellation()
                        let rules = try await compileRules()
                        guard continuationIsActive else { removeRules(); return }
                        let configuration = WKWebViewConfiguration()
                        configuration.websiteDataStore = .nonPersistent()
                        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
                        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
                        configuration.mediaTypesRequiringUserActionForPlayback = .all
                        configuration.userContentController.add(rules)
                        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
                        view.navigationDelegate = self
                        view.uiDelegate = self
                        webView = view
                        view.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))
                    } catch { finish(.failure(error)) }
                }
            }
        } onCancel: {
            Task { @MainActor in self.finish(.failure(CancellationError())) }
        }
    }

    private var continuationIsActive: Bool { continuation != nil && !Task.isCancelled }
    private func allows(_ target: URL) -> Bool {
        policy.allowsNavigation(target)
    }

    private func compileRules() async throws -> WKContentRuleList {
        // Navigation delegates do not cover subresources. Search permits only
        // its named regional hosts; articles stay same-origin.
        let json = try RenderedWebRules.json(for: url, kind: kind)
        return try await withCheckedThrowingContinuation { cont in
            WKContentRuleListStore.default().compileContentRuleList(forIdentifier: ruleID, encodedContentRuleList: json) { rules, _ in
                if let rules { cont.resume(returning: rules) }
                else { cont.resume(throwing: PublicWebError.extraction) }
            }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard continuation != nil, action.targetFrame?.isMainFrame == true,
              action.request.httpMethod == "GET", let target = action.request.url else {
            decisionHandler(.cancel); return
        }
        guard allows(target), navigations < 8 else {
            decisionHandler(.cancel); finish(.failure(PublicWebError.renderRestricted)); return
        }
        navigations += 1
        Task {
            do {
                try await Task.detached { try PublicWebTransport.checkAddress(target) }.value
                guard continuation != nil else { decisionHandler(.cancel); return }
                decisionHandler(.allow)
            } catch { decisionHandler(.cancel); finish(.failure(error)) }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        // Reject subframes without failing an otherwise usable main document.
        guard continuation != nil, response.isForMainFrame else { decisionHandler(.cancel); return }
        guard response.canShowMIMEType,
              let http = response.response as? HTTPURLResponse, let target = http.url, allows(target) else {
            decisionHandler(.cancel); finish(.failure(PublicWebError.renderRestricted)); return
        }
        guard http.statusCode == 200 else {
            decisionHandler(.cancel)
            finish(.failure([403, 429].contains(http.statusCode) ? PublicWebError.verification : PublicWebError.network)); return
        }
        guard ["text/html", "application/xhtml+xml"].contains(http.mimeType ?? "") else {
            decisionHandler(.cancel); finish(.failure(PublicWebError.extraction)); return
        }
        // HTTP redirects may reach the response delegate without another action
        // callback. Validate the final DNS address here as well as the initial URL.
        Task {
            do {
                try await Task.detached { try PublicWebTransport.checkAddress(target) }.value
                guard continuation != nil else { decisionHandler(.cancel); return }
                decisionHandler(.allow)
            } catch { decisionHandler(.cancel); finish(.failure(error)) }
        }
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        redirects += 1
        // WKWebView.url may still describe a previous/provisional page here.
        // Content rules constrain the request; the response delegate checks its actual URL.
        guard redirects <= 8 else {
            finish(.failure(PublicWebError.renderRestricted)); return
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        polling?.cancel()
        polling = Task { [self] in
            do {
                var previous: RenderedWebSnapshot?
                for _ in 0..<10 {
                    try await Task.sleep(nanoseconds: 500_000_000)
                    guard continuation != nil, let target = webView.url, allows(target) else { throw PublicWebError.renderRestricted }
                    let json: String = try await withCheckedThrowingContinuation { cont in
                        webView.evaluateJavaScript(RenderedWebScript.script(for: kind), in: nil, in: .defaultClient) { result in
                            switch result {
                            case .success(let value):
                                if let json = value as? String { cont.resume(returning: json) }
                                else { cont.resume(throwing: PublicWebError.extraction) }
                            case .failure: cont.resume(throwing: PublicWebError.extraction)
                            }
                        }
                    }
                    try Task.checkCancellation()
                    let snapshot = try RenderedWebSnapshot.decode(json)
                    guard let extractedURL = URL(string: snapshot.url), allows(extractedURL) else { throw PublicWebError.renderRestricted }
                    if snapshot.state != "pending", snapshot == previous { finish(.success(snapshot)); return }
                    previous = snapshot
                }
                throw PublicWebError.extraction
            } catch is CancellationError { /* Re-navigation replaces this poll; caller cancellation resolves separately. */ }
            catch { finish(.failure(error)) }
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { polling?.cancel() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(.failure(PublicWebError.network)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(.failure(PublicWebError.network)) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { finish(.failure(PublicWebError.extraction)) }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) { decisionHandler(.deny) }

    private func removeRules() { WKContentRuleListStore.default().removeContentRuleList(forIdentifier: ruleID) { _ in } }
    private func finish(_ result: Result<RenderedWebSnapshot, Error>) {
        guard let cont = continuation else { return }
        continuation = nil
        setup?.cancel(); setup = nil
        deadline?.cancel(); deadline = nil
        polling?.cancel(); polling = nil
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView?.stopLoading()
        webView = nil
        removeRules()
        cont.resume(with: result)
    }
}
