import Foundation
import Testing
@testable import Mindlore

@MainActor
struct AppRouterTests {
    private final class Log {
        var opened: [UUID] = []
        var closed: [UUID] = []
    }

    private func router(_ log: Log) -> AppRouter {
        AppRouter(opened: { log.opened.append($0) }, closed: { log.closed.append($0) })
    }

    @Test func pushingOpensOnceAndPoppingClosesOnce() {
        let log = Log()
        let router = router(log)
        let id = UUID()

        router.journalPath.append(JournalRoute(entryID: id))
        #expect(log.opened == [id])
        #expect(log.closed.isEmpty)

        router.journalPath.removeLast()
        #expect(log.opened == [id])
        #expect(log.closed == [id])
    }

    @Test func writingAnEqualPathCallsNothing() {
        let log = Log()
        let router = router(log)
        let id = UUID()
        router.journalPath = [JournalRoute(entryID: id)]

        router.journalPath = [JournalRoute(entryID: id)]
        #expect(log.opened == [id])
        #expect(log.closed.isEmpty)
    }

    @Test func poppingSeveralClosesEachTopFirst() {
        let log = Log()
        let router = router(log)
        let first = UUID(), second = UUID()
        router.journalPath = [JournalRoute(entryID: first), JournalRoute(entryID: second)]

        router.journalPath = []
        #expect(log.closed == [second, first])
    }

    @Test func theSameEntryTwiceIsCountedTwice() {
        let log = Log()
        let router = router(log)
        let id = UUID()
        router.journalPath = [JournalRoute(entryID: id), JournalRoute(entryID: UUID()), JournalRoute(entryID: id)]

        router.journalPath.removeLast()
        #expect(log.closed == [id])
        router.journalPath = []
        #expect(log.closed.filter { $0 == id }.count == 2)
        #expect(log.opened.filter { $0 == id }.count == 2)
    }

    @Test func switchingTabsWithAnEntryOpenCallsNothing() {
        let log = Log()
        let router = router(log)
        router.journalPath = [JournalRoute(entryID: UUID())]

        router.select(.mind)
        router.select(.ask)
        router.select(.journal)
        #expect(log.opened.count == 1)
        #expect(log.closed.isEmpty)
    }

    @Test func showEntryReplacesThePathOnJournal() {
        let log = Log()
        let router = router(log)
        let open = UUID(), shown = UUID()
        router.journalPath = [JournalRoute(entryID: open)]
        router.select(.mind)
        let token = router.dismissPresentationsToken

        router.showEntry(shown)
        #expect(router.tab == .journal)
        #expect(router.journalPath == [JournalRoute(entryID: shown)])
        #expect(log.closed == [open])
        #expect(log.opened == [open, shown])
        #expect(router.dismissPresentationsToken == token + 1)
    }

    // The page screen is a full-screen cover with its own close rules, so a jump waits for it.
    @Test func aJumpWaitsForFullScreenCoversToClose() {
        let log = Log()
        let router = router(log)
        let open = UUID(), shown = UUID()
        router.journalPath = [JournalRoute(entryID: open)]
        router.setCover("pageOrder", open: true)
        router.setCover("editor", open: true)

        router.showEntry(shown)
        #expect(router.journalPath == [JournalRoute(entryID: open)])
        #expect(log.closed.isEmpty)

        router.setCover("pageOrder", open: false)
        #expect(router.journalPath == [JournalRoute(entryID: open)])

        router.setCover("editor", open: false)
        #expect(router.journalPath == [JournalRoute(entryID: shown)])
        #expect(log.closed == [open])
        #expect(router.pendingJump == nil)
    }

    // New routes and jumps open for typing unless asked; the flag isn't part of which route it is.
    @Test func routesOpenForTypingUnlessAskedAndTheModeIsntPartOfEquality() {
        let log = Log()
        let router = router(log)
        let id = UUID()

        #expect(JournalRoute.new().opensForReading == false)
        router.showEntry(id)
        #expect(router.journalPath.first?.opensForReading == false)
        #expect(router.journalPath == [JournalRoute(entryID: id, opensForReading: true)])

        router.setCover("pageOrder", open: true)
        router.showEntry(UUID(), forReading: true)
        router.setCover("pageOrder", open: false)
        #expect(router.journalPath.first?.opensForReading == true)
    }

    @Test func showingAnEntryThatStartedAsANewRouteKeepsItOpen() {
        let log = Log()
        let router = router(log)
        let new = JournalRoute.new()
        router.journalPath = [new]

        router.showEntry(new.entryID)
        #expect(log.closed.isEmpty)
        #expect(log.opened == [new.entryID])
    }
}

@MainActor
struct AppRouterMindTests {
    private final class Log {
        var opened: [UUID] = []
        var closed: [UUID] = []
    }

    @Test func showInMindSelectsMindAndLeavesJournalAlone() {
        let log = Log()
        let router = AppRouter(opened: { log.opened.append($0) }, closed: { log.closed.append($0) })
        let entry = UUID(), sarah = UUID()
        router.journalPath = [JournalRoute(entryID: entry)]
        router.mindPath = [EntityRoute(id: UUID())]
        let token = router.dismissPresentationsToken

        router.showInMind(sarah)
        #expect(router.tab == .mind)
        #expect(router.mindPath.isEmpty)
        #expect(router.journalPath == [JournalRoute(entryID: entry)])
        #expect(log.closed.isEmpty)
        #expect(router.dismissPresentationsToken == token + 1)
        #expect(router.mindFocusRequest?.id == sarah)
    }

    // Mind may not exist yet when the jump happens, so the request waits and is taken once.
    @Test func aRequestIsConsumedExactlyOnceAndAskingAgainIsNew() throws {
        let router = AppRouter(opened: { _ in }, closed: { _ in })
        let sarah = UUID()
        router.showInMind(sarah)
        let first = try #require(router.mindFocusRequest)

        #expect(router.consumeMindFocus() == sarah)
        #expect(router.consumeMindFocus() == nil)

        router.showInMind(sarah)
        #expect(router.mindFocusRequest?.id == sarah)
        #expect(router.mindFocusRequest != first, "the same entity asked twice is a new request")
    }

    @Test func showInMindWaitsForCovers() {
        let router = AppRouter(opened: { _ in }, closed: { _ in })
        let sarah = UUID()
        router.setCover("pageOrder", open: true)
        router.showInMind(sarah)
        #expect(router.tab == .journal)
        #expect(router.mindFocusRequest == nil)

        router.setCover("pageOrder", open: false)
        #expect(router.tab == .mind)
        #expect(router.consumeMindFocus() == sarah)
    }

    @Test func thePlusOpensTheFanAndNeverBecomesTheTab() {
        let router = AppRouter(opened: { _ in }, closed: { _ in })
        for tab in [AppTab.journal, .mind, .reflect, .ask] {
            router.select(tab)
            router.select(.newEntry)
            #expect(router.tab == tab)
            #expect(router.showingNewEntryFan)
            router.select(.newEntry)
            #expect(!router.showingNewEntryFan, "a second tap on the + closes it")
        }
    }

    @Test func pickingAnotherTabClosesTheFan() {
        let router = AppRouter(opened: { _ in }, closed: { _ in })
        router.select(.newEntry)
        router.select(.mind)
        #expect(router.tab == .mind)
        #expect(!router.showingNewEntryFan)
    }

    @Test func everyJumpClosesTheFan() {
        let router = AppRouter(opened: { _ in }, closed: { _ in })
        let jumps: [(AppRouter) -> Void] = [
            { $0.showEntry(UUID()) },
            { $0.showNewEntry() },
            { $0.showNewPages() },
            { $0.showAsk(question: nil) },
            { $0.showInMind(UUID()) },
            { $0.showReflect(.looseEnds) },
        ]
        for jump in jumps {
            router.showingNewEntryFan = true
            jump(router)
            #expect(!router.showingNewEntryFan)
        }
    }

    @Test func showNewPagesSwitchesToJournalLeavesItsPathAndWaitsForCovers() {
        let router = AppRouter(opened: { _ in }, closed: { _ in })
        let open = UUID()
        router.journalPath = [JournalRoute(entryID: open)]
        router.select(.mind)
        router.setCover("recorder", open: true)
        router.showNewPages()
        #expect(router.newPagesRequest == 0)
        #expect(router.tab == .mind)

        router.setCover("recorder", open: false)
        #expect(router.newPagesRequest == 1)
        #expect(router.tab == .journal)
        #expect(router.journalPath == [JournalRoute(entryID: open)])
    }

    @Test func showReflectSwitchesAndLeavesThePageForReflectOnce() {
        let router = AppRouter(opened: { _ in }, closed: { _ in })
        let token = router.dismissPresentationsToken
        router.showReflect(.looseEnds)
        #expect(router.tab == .reflect)
        #expect(router.dismissPresentationsToken == token + 1)
        #expect(router.consumeReflectPage() == .looseEnds)
        #expect(router.consumeReflectPage() == nil)
    }

    @Test func anEntryOpenedFromReflectReturnsThereWhenItCloses() {
        let router = AppRouter(opened: { _ in }, closed: { _ in })
        router.select(.reflect)
        router.showNewEntry(startingText: "How was the week?", returningTo: .reflect)
        #expect(router.tab == .journal)

        router.journalPath = []
        #expect(router.tab == .reflect)
        #expect(router.returnTab == nil)

        let read = UUID()
        router.showEntry(read, forReading: true, returningTo: .reflect)
        router.journalPath.removeAll()
        #expect(router.tab == .reflect)
    }

    @Test func aTabPickedByHandCancelsTheReturn() {
        let router = AppRouter(opened: { _ in }, closed: { _ in })
        router.showNewEntry(returningTo: .reflect)
        router.select(.mind)
        router.journalPath = []
        #expect(router.tab == .mind, "a move the user made is never overridden")
        #expect(router.returnTab == nil)
    }

    @Test func anotherJumpCancelsTheReturn() {
        let router = AppRouter(opened: { _ in }, closed: { _ in })
        router.showNewEntry(returningTo: .reflect)
        let other = UUID()
        router.showEntry(other)
        #expect(router.returnTab == nil)
        router.journalPath = []
        #expect(router.tab == .journal)
    }

    @Test func aReturnWaitsBehindACoverWithItsJump() {
        let router = AppRouter(opened: { _ in }, closed: { _ in })
        router.select(.reflect)
        router.setCover("pageOrder", open: true)
        router.showNewEntry(startingText: "Prompt", returningTo: .reflect)
        #expect(router.tab == .reflect)
        router.setCover("pageOrder", open: false)
        #expect(router.tab == .journal)
        router.journalPath = []
        #expect(router.tab == .reflect)
    }

    @Test func replacingInMindSwapsTheLastLoser() {
        let router = AppRouter(opened: { _ in }, closed: { _ in })
        let tom = UUID(), sarah = UUID(), other = UUID()
        router.mindPath = [EntityRoute(id: tom), EntityRoute(id: other), EntityRoute(id: tom)]
        router.replaceInMind(tom, with: sarah)
        #expect(router.mindPath == [EntityRoute(id: tom), EntityRoute(id: other), EntityRoute(id: sarah)])
    }

    @Test func deletingFromTheEditorClosesItForDeletionAndAsksTheListOnce() {
        var closed: [UUID] = [], deleted: [UUID] = []
        let router = AppRouter(opened: { _ in }, closed: { closed.append($0) }, closedForDeletion: { deleted.append($0) })
        let below = UUID(), id = UUID()
        router.journalPath = [JournalRoute(entryID: below), JournalRoute(entryID: id)]

        router.deleteEntry(id)

        #expect(router.journalPath == [JournalRoute(entryID: below)])
        #expect(deleted == [id])
        #expect(closed.isEmpty)
        #expect(router.consumeEntryDeletion() == id)
        #expect(router.consumeEntryDeletion() == nil)

        // An ordinary pop afterwards is an ordinary close again.
        router.journalPath = []
        #expect(closed == [below])
    }

    @Test func withoutADeletionCloseTheOrdinaryCloseRuns() {
        var closed: [UUID] = []
        let router = AppRouter(opened: { _ in }, closed: { closed.append($0) })
        let id = UUID()
        router.journalPath = [JournalRoute(entryID: id)]

        router.deleteEntry(id)
        #expect(closed == [id])
    }
}
