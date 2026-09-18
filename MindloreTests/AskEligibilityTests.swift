import Foundation
import SwiftData
import Testing
@testable import Mindlore

// What Ask may read at all. Every tier draws from this one filtered set, so an entry excluded
// here can't reach a provider through an entity's excerpt either.
@MainActor
struct AskEligibilityTests {
    private let container: ModelContainer
    private let context: ModelContext
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    init() throws {
        container = try ModelContainerFactory.make(.inMemory)
        context = container.mainContext
    }

    @discardableResult
    private func entry(_ text: String, createdAt: Date? = nil, configure: (Entry) -> Void = { _ in }) -> Entry {
        let entry = Entry(createdAt: createdAt ?? now, text: text)
        entry.entryDate = createdAt ?? now
        configure(entry)
        context.insert(entry)
        return entry
    }

    private func journal(appliesAIEnabledAt: Bool = true, aiEnabledAt: Date? = nil, includesOlder: Bool = false) -> AskSources.Journal {
        AskSources.journal(in: context, appliesAIEnabledAt: appliesAIEnabledAt, aiEnabledAt: aiEnabledAt, includesOlderEntries: includesOlder)
    }

    @Test func draftsAwaitingTextAndUnapprovedPagesAreNeverSent() {
        let ready = entry("Paddled the river.")
        entry("Half written.") { $0.isDraft = true }
        entry("Still transcribing.") { $0.awaitingText = true }
        entry("Photographed pages.") {
            $0.source = .photo
            $0.textReviewPending = true
        }

        #expect(journal().entries.map(\.id) == [ready.id])
    }

    @Test func entriesFromBeforeAIWasOnGoToOpenAIOnlyWithTheSwitchOn() {
        let enabledAt = now.addingTimeInterval(-86_400)
        let older = entry("Before AI.", createdAt: now.addingTimeInterval(-2 * 86_400))
        let newer = entry("After AI.")

        #expect(journal(aiEnabledAt: enabledAt).entries.map(\.id) == [newer.id])
        #expect(Set(journal(aiEnabledAt: enabledAt, includesOlder: true).entries.map(\.id)) == [older.id, newer.id])
    }

    // Nothing leaves the phone on the on-device path, and with AI never turned on the switch
    // would otherwise leave a local-only Ask with nothing to read.
    @Test func theOnDevicePathIgnoresTheAIEnabledBoundary() {
        let enabledAt = now.addingTimeInterval(-86_400)
        let older = entry("Before AI.", createdAt: now.addingTimeInterval(-2 * 86_400))
        let newer = entry("After AI.")

        let entries = journal(appliesAIEnabledAt: false, aiEnabledAt: enabledAt).entries
        #expect(Set(entries.map(\.id)) == [older.id, newer.id])
    }

    @Test func anEntityWhoseOnlyEntryIsADraftContributesNoExcerpt() throws {
        let sarah = Entity(name: "Sarah", key: "sarah", kind: .person)
        sarah.linkCount = 1
        sarah.lastLinkedAt = now
        context.insert(sarah)
        let draft = entry("Sarah came over.") { $0.isDraft = true }
        let link = EntityLink(surface: "Sarah", kind: .person)
        context.insert(link)
        link.entityID = sarah.id
        link.entryID = draft.id
        try context.save()

        let journal = journal()
        #expect(journal.entries.isEmpty)
        #expect(journal.entities.isEmpty, "an entity reached only through an excluded entry never goes out")

        let built = AskContextBuilder.build(
            question: "What's going on with Sarah?",
            entries: journal.entries,
            entities: journal.entities,
            now: now,
            budget: AskContextBuilder.openAIBudget
        )
        #expect(built.blocks.isEmpty)
    }

    @Test func anEntityMentionedByAnEligibleEntryCarriesItsBioAndOpenLooseEnds() throws {
        let sarah = Entity(name: "Sarah", key: "sarah", kind: .person)
        sarah.bio = "My sister."
        context.insert(sarah)
        let entry = entry("Sarah came over.")
        let link = EntityLink(surface: "Sarah", kind: .person)
        context.insert(link)
        link.entityID = sarah.id
        link.entryID = entry.id
        let open = LooseEnd(text: "Call Sarah back", sourceEntryID: entry.id, sourceEntryDate: now, entityIDs: [sarah.id])
        context.insert(open)
        let done = LooseEnd(text: "Already settled", sourceEntryID: entry.id, sourceEntryDate: now, entityIDs: [sarah.id])
        done.setByUser(.resolved, at: now)
        context.insert(done)
        try context.save()

        let journal = journal()
        let found = try #require(journal.entities.first)
        #expect(found.bio == "My sister.")
        #expect(found.openLooseEnds == ["Call Sarah back"])
        #expect(journal.entries.first?.entityIDs == [sarah.id])
    }

    @Test func aHiddenEntityIsNeverDescribed() throws {
        let sarah = Entity(name: "Sarah", key: "sarah", kind: .person)
        sarah.hidden = true
        context.insert(sarah)
        let entry = entry("Sarah came over.")
        let link = EntityLink(surface: "Sarah", kind: .person)
        context.insert(link)
        link.entityID = sarah.id
        link.entryID = entry.id
        try context.save()

        #expect(journal().entities.isEmpty)
        #expect(journal().entries.map(\.id) == [entry.id], "the entry itself is still fair game")
    }
}
