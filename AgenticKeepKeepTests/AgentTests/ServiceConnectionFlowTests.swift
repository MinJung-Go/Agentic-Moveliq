import XCTest
@testable import AgenticKeepKeep

@MainActor
final class ServiceConnectionFlowTests: XCTestCase {
    private enum Failure: Error { case request, account }
    func testLegacyConfigurationDecodesWithoutResettingScope() throws {
        let data = Data(#"{"enabled":["calendar"],"calendarIDs":["private-calendar"],"writeCalendarID":"write-target","syncTrainingCalendar":true,"syncTrainingAlarms":false,"reminderMinutes":25}"#.utf8)
        let value = try JSONDecoder().decode(CoachPluginConfiguration.self, from: data)
        XCTAssertNil(value.healthEnabled)
        XCTAssertEqual(value.calendarIDs, ["private-calendar"])
        XCTAssertTrue(value.syncTrainingCalendar)
    }

    func testNewAccountDoesNotInheritDeviceWideHealthSelection() {
        let config = CoachPluginConfiguration()
        XCTAssertFalse(ServiceConnectionSelection.targets(config: config, onboarding: true, healthRequested: true).contains(.health))
        XCTAssertTrue(ServiceConnectionSelection.targets(config: config, onboarding: false, healthRequested: true).contains(.health))
    }

    func testServiceSelectionPreservesScopeAndIndependentSyncSettings() {
        var config = CoachPluginConfiguration()
        config.calendarIDs = ["chosen"]; config.writeCalendarID = "write"
        config.syncTrainingCalendar = true; config.syncTrainingAlarms = true; config.reminderMinutes = 30
        let value = ServiceConnectionSelection.applying([.health, .music], to: config)
        XCTAssertEqual(value.enabled, [.music])
        XCTAssertEqual(value.healthEnabled, true)
        XCTAssertEqual(value.calendarIDs, config.calendarIDs)
        XCTAssertEqual(value.writeCalendarID, config.writeCalendarID)
        XCTAssertTrue(value.syncTrainingCalendar)
        XCTAssertTrue(value.syncTrainingAlarms)
        XCTAssertEqual(value.reminderMinutes, 30)
        XCTAssertEqual(ServiceConnectionSelection.applying([], to: value).healthEnabled, false)
    }
    private final class Stub {
        var access: [ServiceConnectionTarget: ServiceConnectionAccess] = [:]
        var requests: [ServiceConnectionTarget] = []
        var activeWaits = 0
        var valid = true
        var onRequest: ((ServiceConnectionTarget) async throws -> Void)?
        var onWait: (() async throws -> Void)?
        var client: ServiceConnectionFlow.Client {
            .init(inspect: { self.access[$0] ?? .notDetermined }, request: { target in
                self.requests.append(target)
                if let operation = self.onRequest { try await operation(target) }
                else { self.access[target] = .authorized }
            }, validate: {
                if !self.valid { throw Failure.account }
            }, waitUntilActive: {
                self.activeWaits += 1
                try await self.onWait?()
            })
        }
    }

    func testOnlySelectedServicesRequestInStableOrder() async {
        let stub = Stub(), flow = ServiceConnectionFlow()
        await flow.connect(selected: [.music, .calendar], client: stub.client)
        XCTAssertEqual(stub.requests, [.calendar, .music])
        XCTAssertEqual(Set(flow.steps.keys), [.calendar, .music])
        XCTAssertFalse(flow.isRunning)
    }

    func testExistingAuthorizationAndBlockedStatesNeverReRequest() async {
        let stub = Stub(), flow = ServiceConnectionFlow()
        stub.access = [.health: .healthSelectionCompleted, .calendar: .needsCalendarSelection,
                       .alarms: .unavailable, .music: .denied, .maps: .restricted, .browser: .authorized]
        await flow.connect(selected: Set(ServiceConnectionTarget.allCases), client: stub.client)
        XCTAssertTrue(stub.requests.isEmpty)
        XCTAssertEqual(flow.steps[.health], .checked(.healthSelectionCompleted))
        XCTAssertEqual(flow.steps[.calendar], .checked(.needsCalendarSelection))
        XCTAssertEqual(flow.steps[.music], .checked(.denied))
    }

    func testDenialContinuesWithOtherSelectedServices() async {
        let stub = Stub(), flow = ServiceConnectionFlow()
        stub.onRequest = { target in stub.access[target] = target == .calendar ? .denied : .authorized }
        await flow.connect(selected: [.calendar, .alarms], client: stub.client)
        XCTAssertEqual(stub.requests, [.calendar, .alarms])
        XCTAssertEqual(flow.steps[.calendar], .checked(.denied))
        XCTAssertEqual(flow.steps[.alarms], .checked(.authorized))
    }

    func testRequestFailureDoesNotDiscardOtherResults() async {
        let stub = Stub(), flow = ServiceConnectionFlow()
        stub.onRequest = { target in
            if target == .calendar { throw Failure.request }
            stub.access[target] = .authorized
        }
        await flow.connect(selected: [.calendar, .alarms], client: stub.client)
        guard case .some(.failed(_)) = flow.steps[.calendar] else { return XCTFail("Expected failed calendar request") }
        XCTAssertEqual(flow.steps[.alarms], .checked(.authorized))
        XCTAssertTrue(flow.canStart)
    }

    func testSystemStateIsReadAfterRequestInsteadOfAssumingSuccess() async {
        let stub = Stub(), flow = ServiceConnectionFlow()
        stub.onRequest = { _ in }
        await flow.connect(selected: [.music], client: stub.client)
        guard case .some(.failed(_)) = flow.steps[.music] else { return XCTFail("No grant must not become success") }
    }

    func testBrowserActivationDoesNotNeedAPermissionGrant() async {
        let stub = Stub(), flow = ServiceConnectionFlow()
        stub.access[.browser] = .needsActivation
        await flow.connect(selected: [.browser], client: stub.client)
        XCTAssertEqual(stub.requests, [.browser])
        XCTAssertEqual(flow.steps[.browser], .checked(.authorized))
    }

    func testAccountChangeAfterRequestStopsRemainingServices() async {
        let stub = Stub(), flow = ServiceConnectionFlow()
        stub.onRequest = { target in stub.access[target] = .authorized; stub.valid = false }
        await flow.connect(selected: [.calendar, .alarms], client: stub.client)
        XCTAssertEqual(stub.requests, [.calendar])
        XCTAssertEqual(flow.steps[.calendar], .waiting)
        XCTAssertEqual(flow.steps[.alarms], .waiting)
        XCTAssertNotNil(flow.failure)
        XCTAssertTrue(flow.stopped)
    }

    func testCancelAtProgressCallbackPreventsStartingRequest() async {
        let stub = Stub(), flow = ServiceConnectionFlow()
        flow.onChange = { if flow.current != nil { flow.cancel() } }
        await flow.connect(selected: [.calendar, .music], client: stub.client)
        XCTAssertTrue(stub.requests.isEmpty)
        XCTAssertTrue(flow.stopped)
        XCTAssertTrue(flow.canStart)
        flow.onChange = nil
    }

    func testInFlightCancellationBlocksRestartAndIgnoresLateResults() async {
        let stub = Stub(), flow = ServiceConnectionFlow()
        var release: CheckedContinuation<Void, Never>?
        let started = expectation(description: "system request started")
        stub.onRequest = { target in
            await withCheckedContinuation { continuation in release = continuation; started.fulfill() }
            stub.access[target] = .authorized
        }
        let task = Task { await flow.connect(selected: [.calendar, .music], client: stub.client) }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(flow.hasOutstandingRequest)
        flow.cancel()
        XCTAssertFalse(flow.canStart)
        await flow.connect(selected: [.alarms], client: stub.client)
        XCTAssertEqual(stub.requests, [.calendar])
        release?.resume()
        await task.value
        XCTAssertTrue(flow.canStart)
        XCTAssertEqual(flow.steps[.calendar], .waiting)
        XCTAssertEqual(flow.steps[.music], .waiting)
        XCTAssertNil(flow.steps[.alarms])
    }

    func testDuplicateStartWhileWaitingCannotOpenAnotherPrompt() async {
        let stub = Stub(), flow = ServiceConnectionFlow()
        var release: CheckedContinuation<Void, Never>?
        let started = expectation(description: "request started")
        stub.onRequest = { target in
            await withCheckedContinuation { release = $0; started.fulfill() }
            stub.access[target] = .authorized
        }
        let task = Task { await flow.connect(selected: [.music], client: stub.client) }
        await fulfillment(of: [started], timeout: 2)
        await flow.connect(selected: [.calendar], client: stub.client)
        XCTAssertEqual(stub.requests, [.music])
        release?.resume()
        await task.value
        XCTAssertEqual(flow.steps[.music], .checked(.authorized))
    }

    func testAccountMustStillMatchAfterWaitingForForeground() async {
        let stub = Stub(), flow = ServiceConnectionFlow()
        stub.onWait = { stub.valid = false }
        await flow.connect(selected: [.calendar, .music], client: stub.client)
        XCTAssertEqual(stub.activeWaits, 1)
        XCTAssertTrue(stub.requests.isEmpty)
        XCTAssertTrue(flow.stopped)
    }

    func testEmptySelectionDoesNotRequestOrWait() async {
        let stub = Stub(), flow = ServiceConnectionFlow()
        await flow.connect(selected: [], client: stub.client)
        XCTAssertTrue(stub.requests.isEmpty)
        XCTAssertEqual(stub.activeWaits, 0)
        XCTAssertTrue(flow.steps.isEmpty)
        XCTAssertTrue(flow.canStart)
    }
}
