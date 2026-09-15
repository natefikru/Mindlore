import Foundation
import Observation

// Entries currently open in an editor or the page order screen. AI jobs that would change what the
// user is looking at wait until the entry is closed. Keyed by Entry.id because a new entry's
// persistent identifier changes when it is first saved.
@Observable
final class EditorPresence {
    private var counts: [UUID: Int] = [:]

    func open(_ id: UUID) {
        counts[id, default: 0] += 1
    }

    func close(_ id: UUID) {
        guard let count = counts[id] else { return }
        counts[id] = count > 1 ? count - 1 : nil
    }

    func isOpen(_ id: UUID) -> Bool {
        counts[id] != nil
    }
}
