import Foundation
import Darwin

/// Retrieval has no access to Safari cookies, history, or DOM. Every redirect is
/// checked before following it; responses are bounded while streaming.
final class PublicWebTransport: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static func fetch(_ url: URL) async throws -> (Data, URL) {
        try await Task.detached(priority: .userInitiated) { try checkAddress(url) }.value
        try Task.checkCancellation()
        let delegate = PublicWebTransport()
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 35
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.setValue("Moveliq/1.0 PublicReader", forHTTPHeaderField: "User-Agent")
        request.setValue("application/rss+xml, application/xml, text/xml, text/html, text/plain", forHTTPHeaderField: "Accept")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, let finalURL = http.url,
                  LocalBrowserPolicy.allows(finalURL) else { throw PublicWebError.unsafeAddress }
            if [403, 429].contains(http.statusCode) { throw PublicWebError.verification }
            guard http.statusCode == 200 else { throw PublicWebError.network }
            guard ["application/rss+xml", "application/xml", "text/xml", "text/html", "text/plain"].contains(http.mimeType ?? "") else { throw PublicWebError.extraction }
            guard http.expectedContentLength <= 2_097_152 else { throw PublicWebError.tooLarge }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < 2_097_152 else { throw PublicWebError.tooLarge }
                data.append(byte)
            }
            return (data, finalURL)
        } catch is CancellationError { throw CancellationError() }
        catch let error as PublicWebError { throw error }
        catch { if Task.isCancelled { throw CancellationError() }; throw PublicWebError.network }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // URLSession invokes delegates serially, away from the main actor.
        guard task.countOfBytesReceived <= 2_097_152, let url = request.url,
              (try? Self.checkAddress(url)) != nil else { completionHandler(nil); return }
        // Foundation also caps redirect loops. Keep our own much smaller bound.
        let count = (task.taskDescription.flatMap(Int.init) ?? 0) + 1
        task.taskDescription = String(count)
        guard count <= 3 else { completionHandler(nil); return }
        completionHandler(URLRequest(url: url, timeoutInterval: 25))
    }

    static func checkAddress(_ url: URL) throws {
        guard LocalBrowserPolicy.allows(url), let host = url.host else { throw PublicWebError.unsafeAddress }
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var head: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, "443", &hints, &head) == 0, let first = head else { throw PublicWebError.network }
        defer { freeaddrinfo(first) }
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        var found = false
        while let current = cursor {
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(current.pointee.ai_addr, current.pointee.ai_addrlen, &buffer,
                              socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0,
                  PublicAddressPolicy.isPublic(String(cString: buffer)) else { throw PublicWebError.unsafeAddress }
            found = true
            cursor = current.pointee.ai_next
        }
        guard found else { throw PublicWebError.unsafeAddress }
    }
}
