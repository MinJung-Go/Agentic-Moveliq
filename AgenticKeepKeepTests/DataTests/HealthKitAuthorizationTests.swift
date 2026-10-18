import HealthKit
import XCTest
import SwiftData
@testable import AgenticKeepKeep

/// 真机反馈：侧载安装后 HealthKit 报 "missing entitlement"，
/// 必须翻译成用户看得懂、知道怎么办的说明，而不是抛原始错误。
@MainActor
final class HealthKitAuthorizationTests: XCTestCase {

    func testMissingEntitlementExplainedInChinese() {
        let error = NSError(domain: "com.apple.healthkit", code: 4)

        let (state, message) = HealthKitService.classify(error)

        XCTAssertEqual(state, .unsupportedSigning)
        XCTAssertTrue(message.contains("签名"), "要说明是签名的问题")
        XCTAssertFalse(message.contains("免费 Apple ID"), "不能将缺少权限归因于免费账号")
        XCTAssertTrue(message.contains("重新授权"))
        XCTAssertTrue(message.contains("不受影响"), "要安抚：其他功能可用")
        XCTAssertFalse(message.contains("HKError"), "不应该把原始错误码丢给用户")
    }

    func testHealthDataUnavailable() {
        let error = NSError(domain: "com.apple.healthkit", code: 1)

        let (state, message) = HealthKitService.classify(error)

        XCTAssertEqual(state, .unavailable)
        XCTAssertTrue(message.contains("不支持"))
    }

    /// 不同系统版本可能只在描述里提到 entitlement
    func testEntitlementMentionedInDescriptionStillClassified() {
        let error = NSError(
            domain: "com.apple.HealthKit",
            code: 100,
            userInfo: [NSLocalizedDescriptionKey: "Missing com.apple.developer.healthkit entitlement."]
        )

        let (state, _) = HealthKitService.classify(error)

        XCTAssertEqual(state, .unsupportedSigning)
    }

    func testOtherErrorsBecomeGenericFailure() {
        let error = NSError(
            domain: "com.apple.healthkit",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Some other problem"]
        )

        let (state, message) = HealthKitService.classify(error)

        XCTAssertEqual(state, .failed)
        XCTAssertTrue(message.contains("授权失败"))
        XCTAssertTrue(message.contains("Some other problem"), "保留原始信息便于排查")
    }

    func testStateTitlesAreUserFacing() {
        XCTAssertEqual(HealthKitService.AuthorizationState.unsupportedSigning.title, "上次授权缺少权限")
        XCTAssertEqual(HealthKitService.AuthorizationState.notRequested.title, "未接入")
    }

    func testPersistedSigningFailureCanBeRetriedAfterReinstall() async {
        let suite = "HealthKitRetry-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("unsupportedSigning", forKey: HealthKitService.stateKey)
        var requested = false
        let service = HealthKitService(defaults: defaults, authorizationRequest: { types in
            requested = true
            XCTAssertTrue(types.contains(HKObjectType.workoutType()))
        }, healthDataAvailable: { true })

        XCTAssertEqual(service.authorizationActionTitle, "重新授权并同步")
        let succeeded = await service.requestAuthorization()
        XCTAssertTrue(succeeded)
        XCTAssertTrue(requested)
        XCTAssertEqual(service.authorizationState, .requested)
        XCTAssertNil(service.lastError)
        XCTAssertFalse(service.isAuthorizing)
        XCTAssertEqual(defaults.string(forKey: HealthKitService.stateKey), "requested")
    }

    func testDisabledAccountHealthConnectionDoesNotImport() async throws {
        let suite = "HealthKitDisabled-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = HealthKitService(defaults: defaults, authorizationRequest: { _ in }, healthDataAvailable: { true })
        let requested = await service.requestAuthorization()
        XCTAssertTrue(requested)
        let container = try AppModelContainer.inMemory()
        var config = CoachPluginConfiguration(); config.healthEnabled = false
        try CoachLifeStore.save(plugins: config, in: container.mainContext)
        await service.sync(into: container.mainContext)
        XCTAssertNil(service.lastSyncDate)
        XCTAssertNil(service.lastError)
        XCTAssertFalse(service.isSyncing)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<HealthSnapshot>()), 0)
    }

    func testFailedAuthorizationDoesNotSyncOrOverwriteError() async throws {
        let suite = "HealthKitFailure-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = HealthKitService(defaults: defaults, authorizationRequest: { _ in
            throw NSError(domain: "com.apple.healthkit", code: 4)
        }, healthDataAvailable: { true })
        let container = try ModelContainer(for: HealthSnapshot.self, HealthWorkout.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))

        let succeeded = await service.authorizeAndSync(into: container.mainContext)
        XCTAssertFalse(succeeded)
        XCTAssertEqual(service.authorizationState, .unsupportedSigning)
        XCTAssertEqual(service.lastError, HealthKitService.signingHelp)
        XCTAssertNil(service.lastSyncDate)
        XCTAssertFalse(service.isSyncing)
        // A later automatic refresh must also preserve the actionable error.
        await service.sync(into: container.mainContext)
        XCTAssertEqual(service.lastError, HealthKitService.signingHelp)
        XCTAssertNil(service.lastSyncDate)
    }

}
