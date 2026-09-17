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

        router.tab = .mind
        router.tab = .ask
        router.tab = .journal
        #expect(log.opened.count == 1)
        #expect(log.closed.isEmpty)
    }

    @Test func showEntryReplacesThePathOnJournal() {
        let log = Log()
        let router = router(log)
        let open = UUID(), shown = UUID()
        router.journalPath = [JournalRoute(entryID: open)]
        router.tab = .mind
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
        #expect(router.pendingRoute == nil)
    }

    @Test func aRecordingOpensForTypingWithoutChangingWhichRouteItIs() {
        let log = Log()
        let router = router(log)
        let id = UUID()

        router.showEntry(id, forTyping: true)
        #expect(router.journalPath.first?.opensForTyping == true)
        #expect(router.journalPath == [JournalRoute(entryID: id)])

        router.setCover("pageOrder", open: true)
        router.showEntry(UUID(), forTyping: true)
        router.setCover("pageOrder", open: false)
        #expect(router.journalPath.first?.opensForTyping == true)
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
