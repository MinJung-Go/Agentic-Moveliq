import Foundation

/// Uses a monotonic clock supplied by the call. Silence is still valid audio data.
struct RealtimeInputHealth {
    enum Failure: Equatable { case captureStopped, uploadStopped }
    private(set) var captured = 0
    private(set) var sent = 0
    private var lastCapture: TimeInterval = 0
    private var lastSend: TimeInterval = 0
    private var expecting = false

    mutating func reset(at now: TimeInterval) {
        captured = 0; sent = 0; lastCapture = now; lastSend = now; expecting = true
    }
    mutating func capture(at now: TimeInterval) { captured += 1; lastCapture = now }
    mutating func upload(at now: TimeInterval) { sent += 1; lastSend = now }
    mutating func failure(at now: TimeInterval, shouldSend: Bool) -> Failure? {
        guard shouldSend else {
            expecting = false; lastCapture = now; lastSend = now
            return nil
        }
        if !expecting { expecting = true; lastCapture = now; lastSend = now }
        if now - lastCapture >= 5 { return .captureStopped }
        if now - lastSend >= 8 { return .uploadStopped }
        return nil
    }
}
