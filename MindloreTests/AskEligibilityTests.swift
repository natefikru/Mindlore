import Foundation
import SwiftData
import Testing
@testable import Mindlore

// What Ask may read at all. One index serves the search panel and Ask, so the rule is no longer
// "what is in the array" but `isSendable` on each document plus an entity table drawn only from the
// documents that carry it. An entry excluded here still cannot reach a provider through an entity's
// bio, an excerpt, or a rollup.
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

    private func gathered() -> AskSources.Gathered {
        AskSources.documents(in: context)
    }

    private func sendableIDs() -> [UUID] {
        gathered().documents.filter(\.isSendable).map(\.id)
    }

    @Test func draftsAwaitingTextAndUnapprovedPagesAreNeverSent() throws {
        let ready = entry("Paddled the river.")
        entry("Half written.") { $0.isDraft = true }
        entry("Still transcribing.") { $0.awaitingText = true }
        entry("Photographed pages.") {
            $0.source = .photo
            $0.textReviewPending = true
        }
        try context.save()

        #expect(sendableIDs() == [ready.id])
        // The panel may still show the two that aren't drafts. It reads the same index and doesn't
        // set sendableOnly, which is the whole difference between the two rules.
        #expect(gathered().documents.count == 3)
    }

    @Test func aSearchOfTheIndexOnlyEverReachesSendableEntries() throws {
        entry("Still transcribing the river trip.") { $0.awaitingText = true }
        try context.save()

        let gathered = gathered()
        let index = AskIndex.build(from: gathered.documents, entities: gathered.entities)
        let terms = [AskIndex.Term(text: "river")]
        #expect(index.search(AskIndex.Query(terms: terms, sendableOnly: true, asOf: now)).isEmpty)
        #expect(index.search(AskIndex.Query(terms: terms, sendableOnly: false, asOf: now)).isEmpty == false)
    }

    // Transcription keeps the aiEnabledAt boundary, because it uploads recordings nobody asked
    // it to. A question is the opposite: the user asked, and a journal that answers only the
    // weeks since AI went on answers nothing worth asking.
    @Test func howOldAnEntryIsNeverKeepsItOutOfAnAnswer() throws {
        let ancient = entry("Years ago.", createdAt: now.addingTimeInterval(-2_000 * 86_400))
        let yesterday = entry("Yesterday.", createdAt: now.addingTimeInterval(-86_400))
        try context.save()

        #expect(Set(sendableIDs()) == [ancient.id, yesterday.id])
    }

    @Test func anEntityWhoseOnlyEntryIsADraftIsNeverDescribedOrRetrievedBy() throws {
        let sarah = Entity(name: "Sarah", key: "sarah", kind: .person)
        sarah.bio = "Written from the draft."
        sarah.linkCount = 1
        sarah.lastLinkedAt = now
        context.insert(sarah)
        let draft = entry("Sarah came over.") { $0.isDraft = true }
        let link = EntityLink(surface: "Sarah", kind: .person)
        context.insert(link)
        link.entityID = sarah.id
        link.entryID = draft.id
        try context.save()

        let gathered = gathered()
        #expect(gathered.documents.isEmpty, "a draft is not in the index at all")
        #expect(gathered.entities.isEmpty, "and an entity reached only through one is not either")

        // Even if something asks for her by id, blocks() has the last word.
        var plan = AskRetrieval.Plan()
        plan.aboutEntityIDs = [sarah.id]
        let selection = AskSources.blocks(for: plan, in: context)
        #expect(selection.entries.isEmpty)
        // Her bio came out of the draft, so it does not go out as an About block either.
        let index = AskIndex.build(from: gathered.documents, entities: gathered.entities)
        #expect(index.entities(namedIn: "What's going on with Sarah?").isEmpty)
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

        #expect(gathered().entities.map(\.id) == [sarah.id])
        #expect(gathered().documents.first?.entityIDs == [sarah.id])

        var plan = AskRetrieval.Plan()
        plan.aboutEntityIDs = [sarah.id]
        plan.rankedEntryIDs = [entry.id]
        let selection = AskSources.blocks(for: plan, in: context)
        let found = try #require(selection.entities.first)
        #expect(found.bio == "My sister.")
        #expect(found.openLooseEnds == ["Call Sarah back"])
        #expect(selection.entries.map(\.id) == [entry.id])
    }

    @Test func aHiddenEntityIsNeverDescribedOrRetrievedBy() throws {
        let sarah = Entity(name: "Sarah", key: "sarah", kind: .person)
        sarah.hidden = true
        context.insert(sarah)
        let entry = entry("Sarah came over.")
        let link = EntityLink(surface: "Sarah", kind: .person)
        context.insert(link)
        link.entityID = sarah.id
        link.entryID = entry.id
        try context.save()

        let gathered = gathered()
        #expect(gathered.entities.isEmpty)
        #expect(gathered.documents.map(\.id) == [entry.id], "the entry itself is still fair game")
        // Her name isn't a term either, so hiding her also stops her being a way in.
        #expect(gathered.documents.first?.entityNames.isEmpty == true)

        var plan = AskRetrieval.Plan()
        plan.aboutEntityIDs = [sarah.id]
        #expect(AskSources.blocks(for: plan, in: context).entities.isEmpty)
    }
}
