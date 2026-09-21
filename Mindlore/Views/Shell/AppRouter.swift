import Foundation
import Observation

enum AppTab: Hashable {
    case journal, mind, ask, settings
}

// One entry on Journal's stack. It carries an id, never an Entry, so a deleted entry never leaves a
// dangling model on the path. A new written entry gets its id up front and the editor creates the
// Entry with it on the first keystroke, so closing finds it like any other.
nonisolated struct JournalRoute: Hashable, Sendable {
    let entryID: UUID
    var isNew = false
    // Decided when the route is made (a list row knows its entry; a finished recording or page set
    // lands for typing), so the editor never re-decides while the entry changes under it.
    var opensForReading = false

    static func new() -> JournalRoute {
        JournalRoute(entryID: UUID(), isNew: true)
    }

    // An entry that started as a new route is the same entry once it exists, so showing it again
    // doesn't close and reopen it. For the same reason a route that differs only in
    // `opensForReading` replaces an open one without changing the open editor's mode.
    static func == (lhs: JournalRoute, rhs: JournalRoute) -> Bool { lhs.entryID == rhs.entryID }
    func hash(into hasher: inout Hasher) { hasher.combine(entryID) }
}

// A request for Mind to focus an entity. The token makes asking twice for the same one count.
nonisolated struct MindFocusRequest: Equatable, Sendable {
    let id: UUID
    let token: Int
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
    // Mind's stack of entity pages. Ids only, so a merge or prune never leaves a stale model.
    var mindPath: [EntityRoute] = []
    // Waits here until Mind takes it, since a jump can arrive before Mind was ever built.
    private(set) var mindFocusRequest: MindFocusRequest?
    // Sheets close when this changes, so a jump never lands underneath one.
    private(set) var dismissPresentationsToken = 0
    // Full-screen covers can't be closed from outside (the page screen has its own close rules),
    // so a jump waits until the last one is gone.
    @ObservationIgnored private var openCovers: Set<String> = []
    @ObservationIgnored private(set) var pendingJump: PendingJump?
    @ObservationIgnored private var mindFocusToken = 0

    enum PendingJump: Equatable {
        case entry(JournalRoute)
        case mind(UUID)
        case settings
    }

    @ObservationIgnored private let opened: (UUID) -> Void
    @ObservationIgnored private let closed: (UUID) -> Void

    init(opened: @escaping (UUID) -> Void, closed: @escaping (UUID) -> Void) {
        self.opened = opened
        self.closed = closed
    }

    // The entry the Keep card is showing, right after a recording. An overlay rather than a sheet: it
    // appears while the recorder's cover is still leaving, and a sheet presented then is dropped.
    private(set) var keptEntryID: UUID?

    func showKeep(_ id: UUID) {
        keptEntryID = id
    }

    func dismissKeep() {
        keptEntryID = nil
    }

    // Replaces Journal's path rather than appending, so a finished recording never lands on top of
    // another open entry.
    func showEntry(_ id: UUID, forReading: Bool = false) {
        let route = JournalRoute(entryID: id, opensForReading: forReading)
        guard openCovers.isEmpty else {
            pendingJump = .entry(route)
            return
        }
        keptEntryID = nil
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
        guard openCovers.isEmpty, let pending = pendingJump else { return }
        pendingJump = nil
        switch pending {
        case .entry(let route): showEntry(route.entryID, forReading: route.opensForReading)
        case .mind(let id): showInMind(id)
        case .settings: showSettings()
        }
    }

    // Switches to Mind at its map and asks it to focus the entity. Journal's path is left alone,
    // so an open entry stays open and no close rules run.
    func showInMind(_ entityID: UUID) {
        guard openCovers.isEmpty else {
            pendingJump = .mind(entityID)
            return
        }
        keptEntryID = nil
        dismissPresentationsToken += 1
        mindFocusToken += 1
        mindFocusRequest = MindFocusRequest(id: entityID, token: mindFocusToken)
        tab = .mind
        mindPath = []
    }

    // Switches to Settings. The insights sheet's "AI is off" recovery is the only caller: it is a
    // sheet, and a tab switch underneath a sheet leaves the sheet covering the tab it switched to,
    // so the token has to take the sheet down on the way. Journal's path is left alone, like Mind.
    func showSettings() {
        // Like the other jumps: a full-screen cover can't be closed from outside, so wait for it.
        guard openCovers.isEmpty else {
            pendingJump = .settings
            return
        }
        keptEntryID = nil
        dismissPresentationsToken += 1
        tab = .settings
    }

    // Mind takes the request once, whether it was built before the jump or because of it.
    func consumeMindFocus() -> UUID? {
        guard let request = mindFocusRequest else { return nil }
        mindFocusRequest = nil
        return request.id
    }

    // A merge made from a page on Mind's stack.
    func replaceInMind(_ loserID: UUID, with winnerID: UUID) {
        mindPath = EntityPagePresentation.replacing(loserID, with: winnerID, in: mindPath)
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
