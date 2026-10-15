import Foundation

/// Only timestamps cross the audio/MainActor boundary; no audio or identifiers are retained.
final class RealtimeCaptureProgress: @unchecked Sendable {
    enum Stage: Equatable { case engineStopped, noCallback, emptyBuffer, noConversion, deliveryStopped }
    private let lock = NSLock()
    private var callback: TimeInterval?
    private var samples: TimeInterval?
    private var converted: TimeInterval?

    func received(frames: Int, at now: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        callback = now
        if frames > 0 { samples = now }
    }
    func produced(at now: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        converted = now
    }
    func stage(engineRunning: Bool, at now: TimeInterval) -> Stage {
        lock.lock(); defer { lock.unlock() }
        guard engineRunning else { return .engineStopped }
        guard let callback, now - callback < 5 else { return .noCallback }
        guard let samples, now - samples < 5 else { return .emptyBuffer }
        guard let converted, now - converted < 5 else { return .noConversion }
        return .deliveryStopped
    }
}

/// Recover a stopped engine at most once per connection, only while input is expected.
struct RealtimeEngineRecovery {
    private(set) var attempted = false
    mutating func shouldRestart(engineRunning: Bool, expectingInput: Bool) -> Bool {
        guard expectingInput, !engineRunning, !attempted else { return false }
        attempted = true
        return true
    }
}
