import Foundation
import Observation

// The tab bar, left to right. `newEntry` is the + in the middle: it never becomes the selected
// tab, it opens the new-entry fan over whichever tab is showing (`AppRouter.select`).
enum AppTab: Hashable {
    case journal, mind, newEntry, reflect, ask
}

// The three sides of the Reflect tab.
enum ReflectPage: String, CaseIterable, Identifiable, Sendable {
    case life, recaps, looseEnds

    var id: String { rawValue }

    var title: String {
        switch self {
        case .life: "Life"
        case .recaps: "Recaps"
        case .looseEnds: "Loose ends"
        }
    }
}

nonisolated struct ReflectPageRequest: Equatable, Sendable {
    let page: ReflectPage
    let token: Int
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
    // A Reflect card's prompt, shown as a placeholder hint in the empty editor rather than real
    // content: nothing is created or saved unless the user actually types. Equality stays on
    // entryID alone, like every other field.
    var startingText: String? = nil

    static func new(startingText: String? = nil) -> JournalRoute {
        JournalRoute(entryID: UUID(), isNew: true, startingText: startingText)
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

nonisolated struct EntryDeletionRequest: Equatable, Sendable {
    let id: UUID
    let token: Int
}

// A request for Ask to take the field, with a question to put in it or none. Ask fills the field
// and focuses it; the user sends. With an entry, Ask starts a conversation about it. The token
// makes asking twice count.
nonisolated struct AskFieldRequest: Equatable, Sendable {
    let question: String?
    var entryID: UUID? = nil
    let token: Int
}

// The selected tab and each tab's path. Every jump between tabs goes through here, and an entry's
// close rules run when it leaves Journal's path, never when its view merely disappears (a tab
// switch or a cover over the editor).
@Observable
final class AppRouter {
    private(set) var tab: AppTab = .journal
    // The + tab's fan of ways to start an entry. Open over whatever tab is showing.
    var showingNewEntryFan = false
    var journalPath: [JournalRoute] = [] {
        didSet { reportChanges(from: oldValue) }
    }
    // Mind's stack of entity pages. Ids only, so a merge or prune never leaves a stale model.
    var mindPath: [EntityRoute] = []
    // Waits here until Mind takes it, since a jump can arrive before Mind was ever built.
    private(set) var mindFocusRequest: MindFocusRequest?
    // The same for Ask, which may not have been built when an intent asks for it.
    private(set) var askFieldRequest: AskFieldRequest?
    // Sheets close when this changes, so a jump never lands underneath one.
    private(set) var dismissPresentationsToken = 0
    // Full-screen covers can't be closed from outside (the page screen has its own close rules),
    // so a jump waits until the last one is gone.
    @ObservationIgnored private var openCovers: Set<String> = []
    @ObservationIgnored private(set) var pendingJump: PendingJump?
    @ObservationIgnored private var mindFocusToken = 0
    @ObservationIgnored private var askFieldToken = 0
    // Reflect's side to show, taken once by Reflect.
    private(set) var reflectPageRequest: ReflectPageRequest?
    @ObservationIgnored private var reflectPageToken = 0
    // A photographed-pages entry asked for from outside Journal (the fan): Journal owns the page
    // cover, so it takes this once and opens it.
    private(set) var newPagesRequest = 0
    // Where to go back to once the entry opened from there leaves Journal's path: an entry opened
    // from Reflect returns to Reflect. Cleared by any other move, so a tab the user picked by hand
    // is never overridden.
    @ObservationIgnored private(set) var returnTab: AppTab?
    @ObservationIgnored private var returnEntryID: UUID?

    enum PendingJump: Equatable {
        case entry(JournalRoute, AppTab?)
        case newEntry(String?, AppTab?)
        case newPages
        case mind(UUID)
        case ask(String?, UUID?)
        case reflect(ReflectPage)
    }

    @ObservationIgnored private let opened: (UUID) -> Void
    @ObservationIgnored private let closed: (UUID) -> Void
    @ObservationIgnored private let closedForDeletion: (UUID) -> Void
    // Entries leaving the path because the user deleted them from the editor, for the moment
    // their close rules run.
    @ObservationIgnored private var deleting: Set<UUID> = []

    // An entry the editor asked to delete. Journal's list owns the undo pill, so it takes this
    // and schedules the delete there. The token makes asking twice count.
    private(set) var entryDeletionRequest: EntryDeletionRequest?
    @ObservationIgnored private var entryDeletionToken = 0

    init(opened: @escaping (UUID) -> Void, closed: @escaping (UUID) -> Void, closedForDeletion: ((UUID) -> Void)? = nil) {
        self.opened = opened
        self.closed = closed
        self.closedForDeletion = closedForDeletion ?? closed
    }

    // Delete from the editor's own menu: the editor leaves the path first, with close rules that
    // start no AI pass for an entry about to go, and the list then schedules the delete behind Undo.
    func deleteEntry(_ id: UUID) {
        deleting.insert(id)
        journalPath.removeAll { $0.entryID == id }
        deleting.remove(id)
        entryDeletionToken += 1
        entryDeletionRequest = EntryDeletionRequest(id: id, token: entryDeletionToken)
    }

    // The list takes the request once.
    func consumeEntryDeletion() -> UUID? {
        guard let request = entryDeletionRequest else { return nil }
        entryDeletionRequest = nil
        return request.id
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

    // A tab picked in the tab bar. The + opens or closes the fan and leaves the tab where it was.
    func select(_ picked: AppTab) {
        if picked == .newEntry {
            showingNewEntryFan.toggle()
            return
        }
        showingNewEntryFan = false
        clearReturn()
        tab = picked
    }

    // Replaces Journal's path rather than appending, so a finished recording never lands on top of
    // another open entry. With `returningTo`, closing the entry goes back to that tab.
    func showEntry(_ id: UUID, forReading: Bool = false, returningTo: AppTab? = nil) {
        let route = JournalRoute(entryID: id, opensForReading: forReading)
        guard openCovers.isEmpty else {
            pendingJump = .entry(route, returningTo)
            return
        }
        open(route, returningTo: returningTo)
    }

    private func open(_ route: JournalRoute, returningTo: AppTab?) {
        beginJump()
        tab = .journal
        journalPath = [route]
        returnTab = returningTo
        returnEntryID = returningTo == nil ? nil : route.entryID
    }

    // What every jump does first: the Keep card, the fan, sheets, and any pending return go.
    private func beginJump() {
        keptEntryID = nil
        showingNewEntryFan = false
        clearReturn()
        dismissPresentationsToken += 1
    }

    private func clearReturn() {
        returnTab = nil
        returnEntryID = nil
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
        case .entry(let route, let returning): showEntry(route.entryID, forReading: route.opensForReading, returningTo: returning)
        case .newEntry(let startingText, let returning): showNewEntry(startingText: startingText, returningTo: returning)
        case .newPages: showNewPages()
        case .mind(let id): showInMind(id)
        case .ask(let question, let entryID): showAsk(question: question, aboutEntry: entryID)
        case .reflect(let page): showReflect(page)
        }
    }

    // A new written entry: the fan, Siri, a Reflect prompt. Replaces Journal's path like showEntry,
    // so it never lands on top of another open entry, whose close rules run as it goes.
    func showNewEntry(startingText: String? = nil, returningTo: AppTab? = nil) {
        guard openCovers.isEmpty else {
            pendingJump = .newEntry(startingText, returningTo)
            return
        }
        open(.new(startingText: startingText), returningTo: returningTo)
    }

    // A photographed-pages entry. Journal's path is left alone: the page cover opens over it.
    func showNewPages() {
        guard openCovers.isEmpty else {
            pendingJump = .newPages
            return
        }
        beginJump()
        tab = .journal
        newPagesRequest += 1
    }

    // Switches to Reflect on one of its sides.
    func showReflect(_ page: ReflectPage) {
        guard openCovers.isEmpty else {
            pendingJump = .reflect(page)
            return
        }
        beginJump()
        reflectPageToken += 1
        reflectPageRequest = ReflectPageRequest(page: page, token: reflectPageToken)
        tab = .reflect
    }

    // Reflect takes the request once, whether it was built before the jump or because of it.
    func consumeReflectPage() -> ReflectPage? {
        defer { reflectPageRequest = nil }
        return reflectPageRequest?.page
    }

    // Switches to Ask and asks it to take the field. Journal's path is left alone, like Mind, so
    // an entry opened from Chat about it is still open when the user comes back.
    func showAsk(question: String?, aboutEntry entryID: UUID? = nil) {
        guard openCovers.isEmpty else {
            pendingJump = .ask(question, entryID)
            return
        }
        beginJump()
        askFieldToken += 1
        askFieldRequest = AskFieldRequest(question: question, entryID: entryID, token: askFieldToken)
        tab = .ask
    }

    // Ask takes the request once, whether it was built before the jump or because of it.
    func consumeAskField() -> AskFieldRequest? {
        defer { askFieldRequest = nil }
        return askFieldRequest
    }

    // Switches to Mind at its map and asks it to focus the entity. Journal's path is left alone,
    // so an open entry stays open and no close rules run.
    func showInMind(_ entityID: UUID) {
        guard openCovers.isEmpty else {
            pendingJump = .mind(entityID)
            return
        }
        beginJump()
        mindFocusToken += 1
        mindFocusRequest = MindFocusRequest(id: entityID, token: mindFocusToken)
        tab = .mind
        mindPath = []
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
            if deleting.contains(route.entryID) {
                closedForDeletion(route.entryID)
            } else {
                closed(route.entryID)
            }
        }
        arrived.forEach(opened)
        // The entry opened from another tab has closed: go back there, if Journal is still showing.
        if let id = returnEntryID, !journalPath.contains(where: { $0.entryID == id }) {
            let back = returnTab
            clearReturn()
            if tab == .journal, let back { tab = back }
        }
    }
}
