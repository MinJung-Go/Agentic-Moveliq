import Foundation

// Authentication and realtime requests require a trusted HTTPS service endpoint.
enum ServiceEndpoint {
    static var baseURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "MoveliqServiceURL") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
    static func url(_ path: String, baseURL: String = ServiceEndpoint.baseURL) throws -> URL {
        var normalized = baseURL
        while normalized.hasSuffix("/") { normalized.removeLast() }
        guard !normalized.isEmpty,
              !normalized.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }),
              !normalized.contains("\\"),
              let base = URLComponents(string: normalized),
              base.scheme == "https",
              let host = base.host, !host.isEmpty,
              base.user == nil, base.password == nil, base.query == nil, base.fragment == nil,
              base.port == nil || (1...65535).contains(base.port!),
              safePath(base.percentEncodedPath, allowEmpty: true), safePath(path),
              let url = URL(string: normalized + "/v1" + path) else {
            throw AuthServiceError(status: 0, message: "服务地址尚未配置，请联系管理员获取已配置的安装版本。")
        }
        return url
    }
    static func realtimeURL(baseURL: String = ServiceEndpoint.baseURL) throws -> URL {
        let endpoint = try url("/realtime", baseURL: baseURL)
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        guard let result = components.url else { throw URLError(.badURL) }
        return result
    }
    private static func safePath(_ path: String, allowEmpty: Bool = false) -> Bool {
        if path.isEmpty { return allowEmpty }
        guard path.first == "/", !path.contains("//") else { return false }
        return path.dropFirst().split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".." &&
            $0.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil
        }
    }
    static func isProxy(_ base: String) -> Bool { !baseURL.isEmpty && base == baseURL + "/v1" }
}
