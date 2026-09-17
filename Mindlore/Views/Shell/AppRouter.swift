import Foundation
import Observation

enum AppTab: Hashable {
    case journal, mind, ask
}

// One entry on Journal's stack. It carries an id, never an Entry, so a deleted entry never leaves a
// dangling model on the path. A new written entry gets its id up front and the editor creates the
// Entry with it on the first keystroke, so closing finds it like any other.
nonisolated struct JournalRoute: Hashable, Sendable {
    let entryID: UUID
    var isNew = false
    // Set by a finished recording, so its entry lands in the editor rather than read mode.
    var opensForTyping = false

    static func new() -> JournalRoute {
        JournalRoute(entryID: UUID(), isNew: true)
    }

    // An entry that started as a new route is the same entry once it exists, so showing it again
    // doesn't close and reopen it.
    static func == (lhs: JournalRoute, rhs: JournalRoute) -> Bool { lhs.entryID == rhs.entryID }
    func hash(into hasher: inout Hasher) { hasher.combine(entryID) }
}

// The selected tab and each tab's path. Every jump between tabs goes through here, and an entry's
// close rules run when it leaves Journal's path, never when its view merely disappears (a tab
// switch or a cover over the editor).
@Observable
final class AppRouter {
    var tab: AppTab = .journal
    var journalPath: [JournalRoute] = [] {
        didSet { reportChanges(from: oldValue) }
    }
    // Sheets close when this changes, so a jump never lands underneath one.
    private(set) var dismissPresentationsToken = 0
    // Full-screen covers can't be closed from outside (the page screen has its own close rules),
    // so a jump waits until the last one is gone.
    @ObservationIgnored private var openCovers: Set<String> = []
    @ObservationIgnored private(set) var pendingRoute: JournalRoute?

    @ObservationIgnored private let opened: (UUID) -> Void
    @ObservationIgnored private let closed: (UUID) -> Void

    init(opened: @escaping (UUID) -> Void, closed: @escaping (UUID) -> Void) {
        self.opened = opened
        self.closed = closed
    }

    // Replaces Journal's path rather than appending, so a finished recording never lands on top of
    // another open entry.
    func showEntry(_ id: UUID, forTyping: Bool = false) {
        let route = JournalRoute(entryID: id, opensForTyping: forTyping)
        guard openCovers.isEmpty else {
            pendingRoute = route
            return
        }
        dismissPresentationsToken += 1
        tab = .journal
        journalPath = [route]
    }

    func setCover(_ name: String, open: Bool) {
        if open {
            openCovers.insert(name)
        } else {
            openCovers.remove(name)
        }
        guard openCovers.isEmpty, let pending = pendingRoute else { return }
        pendingRoute = nil
        showEntry(pending.entryID, forTyping: pending.opensForTyping)
    }

    private func reportChanges(from old: [JournalRoute]) {
        var remaining = Dictionary(old.map { ($0.entryID, 1) }, uniquingKeysWith: +)
        var arrived: [UUID] = []
        for route in journalPath {
            if let count = remaining[route.entryID], count > 0 {
                remaining[route.entryID] = count - 1
            } else {
                arrived.append(route.entryID)
            }
        }
        // Old routes are closed in stack order, top first, before new ones open.
        for route in old.reversed() {
            guard let count = remaining[route.entryID], count > 0 else { continue }
            remaining[route.entryID] = count - 1
            closed(route.entryID)
        }
        arrived.forEach(opened)
    }
}
