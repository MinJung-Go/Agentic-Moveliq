import XCTest
@testable import AgenticKeepKeep

final class AuthPolicyTests: XCTestCase {
    func testOnlyApprovedHTTPDeploymentIsAllowed() throws {
        XCTAssertEqual(try ServiceEndpoint.url("/auth/login", baseURL: "http://47.100.234.212:8080").absoluteString,
                       "http://47.100.234.212:8080/v1/auth/login")
        for base in ["http://47.100.234.212", "http://47.100.234.212:8081", "http://47.100.234.213:8080",
                     "http://47.100.234.212:8080.evil.com", "http://47.100.234.212:8080@evil.com",
                     "http://47.100.234.212:8080?other=1", "http://47.100.234.212:8080/path"] {
            XCTAssertThrowsError(try ServiceEndpoint.url("/auth/me", baseURL: base))
        }
        XCTAssertNoThrow(try ServiceEndpoint.url("/auth/me", baseURL: "https://example.com"))
    }
    func testInvitationInputAcceptsGroupedShortAndLegacyCodes() {
        XCTAssertEqual(AuthInputPolicy.inviteCode(" k7mp-9x4r\n"), "K7MP9X4R")
        XCTAssertEqual(AuthInputPolicy.inviteCode("K7 MP\t9X4R"), "K7MP9X4R")
        XCTAssertEqual(AuthInputPolicy.inviteCode("a10f92b86d44c903e718002a"), "A10F92B86D44C903E718002A")
        XCTAssertEqual(AuthInputPolicy.inviteCode(" - "), "")
    }
    func testHTTPSPrefixIsSharedByAuthChatAndRealtime() throws {
        for base in ["https://moveliq.work/api", "https://moveliq.work/api/"] {
            XCTAssertEqual(try ServiceEndpoint.url("/auth/login", baseURL: base).absoluteString, "https://moveliq.work/api/v1/auth/login")
            XCTAssertEqual(try ServiceEndpoint.url("/chat/completions", baseURL: base).absoluteString, "https://moveliq.work/api/v1/chat/completions")
            XCTAssertEqual(try ServiceEndpoint.realtimeURL(baseURL: base).absoluteString, "wss://moveliq.work/api/v1/realtime")
        }
        XCTAssertEqual(try ServiceEndpoint.realtimeURL(baseURL: "https://moveliq.work").absoluteString, "wss://moveliq.work/v1/realtime")
        XCTAssertEqual(try ServiceEndpoint.realtimeURL(baseURL: "http://47.100.234.212:8080").absoluteString, "ws://47.100.234.212:8080/v1/realtime")
    }
    func testInvalidHTTPSBaseOrRequestPathCannotRedirectCredentials() {
        for base in ["https://user:pass@moveliq.work/api", "https://moveliq.work/api?token=x", "https://moveliq.work/api#x",
                     "https://moveliq.work/api/../admin", "https://moveliq.work/api/%2e%2e", "https://moveliq.work/api%2fv1",
                     "https://moveliq.work//api", "https://moveliq.work/api\\v1", "https://moveliq.work:0/api",
                     "https://moveliq.work:65536/api", "https://moveliq.work/a pi", "https:///api", ""] {
            XCTAssertThrowsError(try ServiceEndpoint.url("/auth/me", baseURL: base), base)
        }
        for path in ["//evil.com", "/../admin", "/auth/%2e%2e", "/auth/me?token=x", "/auth/me#x", "https://evil.com", ""] {
            XCTAssertThrowsError(try ServiceEndpoint.url(path, baseURL: "https://moveliq.work/api"), path)
        }
    }
    func testUsernameNormalizationAndBounds() {
        XCTAssertEqual(AuthInputPolicy.username("  Alice_01\n"), "alice_01")
        for value in ["user", String(repeating: "a", count: 24)] { XCTAssertTrue(AuthInputPolicy.validUsername(value)) }
        for value in ["abc", "用户名", "user-name", "abc\nxyz", String(repeating: "a", count: 25)] { XCTAssertFalse(AuthInputPolicy.validUsername(value)) }
    }
    func testPasswordBoundsMatchServerUTF16() {
        XCTAssertFalse(AuthInputPolicy.validPassword(String(repeating: "a", count: 11)))
        XCTAssertTrue(AuthInputPolicy.validPassword(String(repeating: "🙂", count: 6)))
        XCTAssertTrue(AuthInputPolicy.validPassword(String(repeating: "a", count: 128)))
        XCTAssertFalse(AuthInputPolicy.validPassword(String(repeating: "🙂", count: 65)))
    }
    func testRedactedInvitesAndSessionDecoding() throws {
        let data = Data(#"{"id":"1","code":null,"status":"used"}"#.utf8)
        XCTAssertFalse(try JSONDecoder().decode(ServiceInvite.self, from: data).available)
        let session = ServiceSession(user: ServiceUser(id: UUID().uuidString, username: "alice"), token: "secret", expiresAt: "2026-10-01T00:00:00.000Z")
        XCTAssertEqual(try JSONDecoder().decode(ServiceSession.self, from: JSONEncoder().encode(session)).user, session.user)
    }
    func testServiceBudgetRejectsImpossibleLimits() {
        func valid(_ window: Int, _ output: Int) -> Bool {
            ServiceConfiguration(model: "test", contextWindow: window, maxOutput: output, searchEnabled: false, supportContact: "").validBudget
        }
        XCTAssertTrue(valid(32768, 4096))
        XCTAssertFalse(valid(4096, 4096))
        XCTAssertFalse(valid(1000, 512))
        XCTAssertFalse(valid(32768, 0))
    }
    func testPreferencesRequireLegacyClaimAndStayWithAccount() throws {
        let suite = UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = AccountPreferences(defaults: defaults)
        defaults.set("旧个人偏好", forKey: "milo.preference")
        prefs.activate("other", adoptingLegacy: false)
        XCTAssertNil(defaults.string(forKey: "milo.preference"))
        prefs.activate("owner", adoptingLegacy: true)
        XCTAssertEqual(defaults.string(forKey: "milo.preference"), "旧个人偏好")
        defaults.set(12, forKey: "llm.usage.callCount")
        prefs.deactivate()
        XCTAssertNil(defaults.object(forKey: "llm.usage.callCount"))
        prefs.activate("other", adoptingLegacy: false)
        XCTAssertNil(defaults.string(forKey: "milo.preference"))
        prefs.activate("owner", adoptingLegacy: false)
        XCTAssertEqual(defaults.integer(forKey: "llm.usage.callCount"), 12)
        XCTAssertEqual(defaults.string(forKey: "milo.preference"), "旧个人偏好")
    }
}
