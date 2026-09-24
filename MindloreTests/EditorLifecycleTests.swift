import Foundation
import SwiftData
import Testing
@testable import Mindlore

@MainActor
struct EditorLifecycleTests {
    let container: ModelContainer
    let context: ModelContext
    let presence = EditorPresence()
    let aiPass: AIPassTrigger
    let lifecycle: EditorLifecycle
    let router: AppRouter
    let flagged: Counter

    final class Counter { var count = 0 }

    init() throws {
        container = try ModelContainerFactory.make(.inMemory)
        context = container.mainContext
        let settings = SettingsStore(store: FakeKeyValueStore(), diagnostics: .disabled, now: { Date(timeIntervalSince1970: 1_000) })
        settings.recordAutomationStartIfNeeded()
        aiPass = AIPassTrigger(settings: settings, presence: presence, titleUsable: { true }, insightsUsable: { true }, diagnostics: .disabled)
        let flagged = Counter()
        self.flagged = flagged
        aiPass.onFlagged = { flagged.count += 1 }
        lifecycle = EditorLifecycle(
            context: context,
            saver: EntrySaver(context: context, diagnostics: .disabled),
            presence: presence,
            aiPass: aiPass,
            keepAudio: { true },
            diagnostics: .disabled
        )
        router = AppRouter(opened: lifecycle.opened, closed: lifecycle.closed, closedForDeletion: lifecycle.closedForDeletion)
    }

    private func entries() throws -> [Entry] {
        try context.fetch(FetchDescriptor<Entry>())
    }

    @Test func aNewRouteWithNothingTypedClosesCleanly() throws {
        let route = JournalRoute.new()
        router.journalPath = [route]
        #expect(presence.isOpen(route.entryID))

        router.journalPath = []
        #expect(!presence.isOpen(route.entryID))
        #expect(try entries().isEmpty)
        #expect(flagged.count == 1)
    }

    @Test func aBlankCreatedEntryIsDeletedWithoutThePass() throws {
        let route = JournalRoute.new()
        router.journalPath = [route]
        // What the editor does on the first keystroke, then the user clears it.
        let entry = Entry(text: "x")
        entry.id = route.entryID
        entry.isDraft = true
        context.insert(entry)
        entry.text = ""

        router.journalPath = []
        #expect(try entries().isEmpty)
    }

    @Test func aFinishedEntryGetsThePassOnceWhenItLeavesThePath() throws {
        let entry = Entry(createdAt: Date(timeIntervalSince1970: 5_000), text: "A walk by the river.")
        context.insert(entry)
        try context.save()

        router.journalPath = [JournalRoute(entryID: entry.id)]
        #expect(!entry.automaticAIPassUsed)
        router.select(.mind)
        #expect(presence.isOpen(entry.id))
        #expect(!entry.automaticAIPassUsed)

        router.journalPath = []
        #expect(entry.automaticAIPassUsed)
        #expect(entry.titlePending)
        #expect(!presence.isOpen(entry.id))
        #expect(!context.hasChanges)
    }

    // A cover over the editor used to reopen the entry on return while closing it once, which left
    // it open for good. Presence now follows the path alone.
    @Test func presenceClosesExactlyOnceWhateverTheViewDoes() throws {
        let entry = Entry(createdAt: Date(timeIntervalSince1970: 5_000), text: "Pages")
        context.insert(entry)
        router.journalPath = [JournalRoute(entryID: entry.id)]
        router.journalPath = [JournalRoute(entryID: entry.id)]

        router.journalPath = []
        #expect(!presence.isOpen(entry.id))
    }

    @Test func aDraftStaysADraftAndKeepsItsText() throws {
        let route = JournalRoute.new()
        router.journalPath = [route]
        let entry = Entry(text: "half written")
        entry.id = route.entryID
        entry.isDraft = true
        context.insert(entry)

        router.journalPath = []
        let saved = try #require(try entries().first)
        #expect(saved.isDraft)
        #expect(!saved.automaticAIPassUsed)
        #expect(saved.text == "half written")
    }

    // Deleted from the editor's menu: the delete waits behind Undo, so no pass should send an
    // entry that is on its way out.
    @Test func closingForDeletionStartsNoPass() throws {
        let entry = Entry(createdAt: Date(timeIntervalSince1970: 5_000), text: "A walk by the river.")
        context.insert(entry)
        try context.save()
        router.journalPath = [JournalRoute(entryID: entry.id)]

        router.deleteEntry(entry.id)

        #expect(!presence.isOpen(entry.id))
        #expect(!entry.automaticAIPassUsed)
        #expect(!entry.titlePending)
        #expect(flagged.count == 0)
        #expect(try entries().count == 1)
    }
}
