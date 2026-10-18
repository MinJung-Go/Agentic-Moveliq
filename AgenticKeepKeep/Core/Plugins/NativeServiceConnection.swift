import CoreLocation
import EventKit
import Foundation
import MusicKit
import UIKit

@MainActor
enum NativeServiceConnection {
    private static var requesting = false

    static func inspect(_ target: ServiceConnectionTarget, config: CoachPluginConfiguration) -> ServiceConnectionAccess {
        switch target {
        case .health:
            let health = HealthKitService.shared
            guard health.isAvailable else { return .unavailable }
            return health.authorizationState == .requested ? .healthSelectionCompleted : .notDetermined
        case .calendar:
            switch EKEventStore.authorizationStatus(for: .event) {
            case .notDetermined: return .notDetermined
            case .writeOnly: return .upgradeNeeded
            case .denied: return .denied
            case .restricted: return .restricted
            case .fullAccess:
                let store = CalendarPluginService.shared.store
                let scopeValid = !config.calendarIDs.isEmpty && config.calendarIDs.allSatisfy { store.calendar(withIdentifier: $0) != nil }
                let writeValid = store.calendar(withIdentifier: config.writeCalendarID)?.allowsContentModifications == true
                return scopeValid && writeValid ? .authorized : .needsCalendarSelection
            @unknown default: return .unavailable
            }
        case .alarms: return AlarmPluginService.connectionAccess
        case .music:
            switch MusicAuthorization.currentStatus {
            case .notDetermined: return .notDetermined
            case .authorized: return .authorized
            case .denied: return .denied
            case .restricted: return .restricted
            @unknown default: return .unavailable
            }
        case .maps:
            switch MapsPluginService.shared.authorizationStatus {
            case .notDetermined: return .notDetermined
            case .authorizedAlways, .authorizedWhenInUse: return .authorized
            case .denied: return .denied
            case .restricted: return .restricted
            @unknown default: return .unavailable
            }
        case .browser: return LLMSettings.shared.webSearchEnabled ? .authorized : .needsActivation
        }
    }

    static func waitUntilActive() async throws {
        while UIApplication.shared.applicationState != .active {
            try await Task.sleep(for: .milliseconds(100))
        }
        try Task.checkCancellation()
    }

    static func request(_ target: ServiceConnectionTarget, validate: () throws -> Void) async throws {
        guard !requesting else { throw CoachPluginError.unavailable("另一个系统授权尚未结束，请稍后继续。") }
        requesting = true
        defer { requesting = false }
        try await waitUntilActive()
        try validate()
        switch target {
        case .health:
            guard await HealthKitService.shared.requestAuthorization() else {
                throw CoachPluginError.unavailable(HealthKitService.shared.lastError ?? "健康授权未完成，请稍后重试。")
            }
        case .calendar: try await CalendarPluginService.shared.authorize()
        case .alarms: try await AlarmPluginService.authorize()
        case .music: await MusicPluginService.shared.authorize()
        case .maps: try await MapsPluginService.shared.authorizeForConnection()
        case .browser: LLMSettings.shared.webSearchEnabled = true
        }
        // System permission is device-wide; this adapter never writes account preferences.
    }
}
