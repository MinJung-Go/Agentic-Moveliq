import Foundation

/// A shared lease prevents one call view from restoring auto-lock while another owns it.
@MainActor
final class RealtimeIdleTimer {
    private let read: () -> Bool
    private let write: (Bool) -> Void
    private var owners = Set<UUID>()
    private var previous: Bool?

    init(read: @escaping () -> Bool, write: @escaping (Bool) -> Void) {
        self.read = read; self.write = write
    }
    func acquire(_ owner: UUID) {
        guard owners.insert(owner).inserted else { return }
        if owners.count == 1 { previous = read(); write(true) }
    }
    func release(_ owner: UUID) {
        guard owners.remove(owner) != nil, owners.isEmpty else { return }
        if let previous { write(previous) }
        previous = nil
    }
}
