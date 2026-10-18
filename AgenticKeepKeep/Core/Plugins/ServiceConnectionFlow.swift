import Foundation

/// The first-run connection screen and Settings share the same six targets.
/// Health remains a read-only data source, rather than an Agent write tool.
enum ServiceConnectionTarget: String, CaseIterable, Identifiable {
    case health, calendar, alarms, music, maps, browser
    var id: String { rawValue }
    var plugin: CoachPlugin? { CoachPlugin(rawValue: rawValue) }
}

enum ServiceConnectionSelection {
    static func targets(config: CoachPluginConfiguration, onboarding: Bool, healthRequested: Bool) -> Set<ServiceConnectionTarget> {
        var result = Set(config.enabled.compactMap { ServiceConnectionTarget(rawValue: $0.rawValue) })
        if config.healthEnabled ?? (!onboarding && healthRequested) { result.insert(.health) }
        return result
    }
    static func applying(_ targets: Set<ServiceConnectionTarget>, to config: CoachPluginConfiguration) -> CoachPluginConfiguration {
        var result = config
        result.enabled = Set(targets.compactMap(\.plugin))
        result.healthEnabled = targets.contains(.health)
        return result
    }
}

/// A fresh platform snapshot. Completing the HealthKit sheet does not reveal
/// whether the person granted access to every requested read type.
enum ServiceConnectionAccess: Equatable {
    case notDetermined
    case upgradeNeeded
    case needsActivation
    case authorized
    case healthSelectionCompleted
    case needsCalendarSelection
    case denied
    case restricted
    case unavailable

    var needsRequest: Bool {
        switch self {
        case .notDetermined, .upgradeNeeded, .needsActivation: return true
        default: return false
        }
    }
}

enum ServiceConnectionStep: Equatable {
    case waiting
    case requesting
    case checked(ServiceConnectionAccess)
    case failed(String)
}

/// Serial orchestration only: adapters own system APIs and account validation.
/// This type never grants permissions, selects calendars, or changes sync rules.
@MainActor
final class ServiceConnectionFlow {
    struct Client {
        var inspect: (ServiceConnectionTarget) -> ServiceConnectionAccess
        var request: (ServiceConnectionTarget) async throws -> Void
        var validate: () throws -> Void
        var waitUntilActive: () async throws -> Void
    }

    private(set) var steps: [ServiceConnectionTarget: ServiceConnectionStep] = [:]
    private(set) var isRunning = false
    private(set) var hasOutstandingRequest = false
    private(set) var current: ServiceConnectionTarget?
    private(set) var stopped = false
    private(set) var failure: String?
    var onChange: (() -> Void)?

    var canStart: Bool { !isRunning && !hasOutstandingRequest }
    private var generation = UUID()

    func cancel() {
        guard isRunning else { return }
        generation = UUID()
        isRunning = false
        stopped = true
        if let current { steps[current] = .waiting }
        current = nil
        onChange?()
    }

    func connect(selected: Set<ServiceConnectionTarget>, client: Client) async {
        guard canStart else { return }
        let marker = UUID()
        generation = marker
        let targets = ServiceConnectionTarget.allCases.filter { selected.contains($0) }
        steps = Dictionary(uniqueKeysWithValues: targets.map { ($0, .waiting) })
        isRunning = true
        stopped = false
        failure = nil
        current = nil
        onChange?()
        defer {
            if generation == marker {
                isRunning = false
                current = nil
                onChange?()
            }
        }

        do {
            for target in targets {
                try check(marker, client: client)
                try await client.waitUntilActive()
                try check(marker, client: client)
                let before = client.inspect(target)
                if !before.needsRequest {
                    steps[target] = .checked(before)
                    onChange?()
                    continue
                }

                current = target
                steps[target] = .requesting
                onChange?()
                try check(marker, client: client)
                hasOutstandingRequest = true
                onChange?()
                do {
                    try check(marker, client: client)
                    try await client.request(target)
                } catch {
                    hasOutstandingRequest = false
                    onChange?()
                    try check(marker, client: client)
                    if error is CancellationError { throw error }
                    let actual = client.inspect(target)
                    steps[target] = actual.needsRequest
                        ? .failed(error.localizedDescription) : .checked(actual)
                    current = nil
                    onChange?()
                    continue
                }
                hasOutstandingRequest = false
                onChange?()
                try check(marker, client: client)

                let actual = client.inspect(target)
                steps[target] = actual.needsRequest
                    ? .failed("系统尚未完成授权选择，可稍后重试。") : .checked(actual)
                current = nil
                onChange?()
            }
        } catch {
            guard generation == marker else { return }
            if let current { steps[current] = .waiting }
            current = nil
            stopped = true
            if !(error is CancellationError) { failure = error.localizedDescription }
        }
    }

    private func check(_ marker: UUID, client: Client) throws {
        guard generation == marker else { throw CancellationError() }
        try Task.checkCancellation()
        try client.validate()
    }
}
