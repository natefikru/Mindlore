import Foundation
import SwiftData
import Testing
@testable import Mindlore

// A builder that records what it was handed, and can be held mid-build so a test can prove the
// in-flight guard rather than a fingerprint comparison. No @concurrent on the methods: a fake does
// not need to leave the caller's actor, and the attribute on the protocol requirement is what
// matters in the app. (Which also means this fake cannot prove the real build runs off the main
// actor. Nothing at the unit level can; ask.indexed is how the device pass sees it.)
@MainActor
final class FakeAskIndexBuilder: AskIndexBuilding {
    private(set) var builds = 0
    private(set) var lastDocuments: [AskIndex.DocumentInput] = []
    private(set) var lastEntities: [AskIndex.Entity] = []

    // Awaited, never polled with Task.yield, which CLAUDE.md rules out for starving the main actor.
    private var gate: CheckedContinuation<Void, Never>?
    private var holds = false
    private var started: CheckedContinuation<Void, Never>?

    func hold() { holds = true }

    // Resumes once a build is actually in flight, so the second caller is racing a running build.
    func waitForBuildToStart() async {
        await withCheckedContinuation { started = $0 }
    }

    func release() {
        gate?.resume()
        gate = nil
        holds = false
    }

    nonisolated func build(_ inputs: [AskIndex.DocumentInput], entities: [AskIndex.Entity]) async -> AskIndex {
        await record(inputs, entities: entities)
    }

    private func record(_ inputs: [AskIndex.DocumentInput], entities: [AskIndex.Entity]) async -> AskIndex {
        builds += 1
        lastDocuments = inputs
        lastEntities = entities
        started?.resume()
        started = nil
        if holds {
            await withCheckedContinuation { gate = $0 }
        }
        return AskIndex.build(from: inputs, entities: entities)
    }
}

@MainActor
struct AskIndexStoreTests {
    private func makeStore() -> (store: AskIndexStore, builder: FakeAskIndexBuilder) {
        let builder = FakeAskIndexBuilder()
        return (AskIndexStore(builder: builder, diagnostics: DiagnosticsLog(fileURL: nil)), builder)
    }

    @discardableResult
    private func addEntry(_ text: String, to context: ModelContext, isDraft: Bool = false) -> Entry {
        let entry = Entry(text: text)
        entry.isDraft = isDraft
        context.insert(entry)
        try? context.save()
        return entry
    }

    // MARK: - When it rebuilds

    @Test func nothingChangedMeansNoRebuild() async throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        addEntry("the deadline moved", to: context)
        let (store, builder) = makeStore()

        await store.refreshIfNeeded(revisions: .init(saver: 1, graph: 1), in: context)
        #expect(builder.builds == 1)
        await store.refreshIfNeeded(revisions: .init(saver: 1, graph: 1), in: context)
        #expect(builder.builds == 1)
    }

    @Test func anEntryAddedForcesARebuild() async throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let (store, builder) = makeStore()
        await store.refreshIfNeeded(revisions: .init(saver: 1, graph: 1), in: context)

        addEntry("something new", to: context)
        await store.refreshIfNeeded(revisions: .init(saver: 2, graph: 1), in: context)
        #expect(builder.builds == 2)
        #expect(store.index.documents.count == 1)
    }

    // The one that matters most. Writing insights deliberately does not stamp the entry:
    // ModelContext.saveStampingEntries(except:) exists for that, and InsightsCoordinator and
    // GraphIndexer both use it. So an entry's tags, mood, and life areas can all land with no count
    // and no entry timestamp moving, and graph.revision is the only thing that sees it. Miss this
    // and a freshly analysed entry is unfindable by its tag or its person until the next launch.
    @Test func insightsWrittenThroughTheExemptingSaveStillForceARebuild() async throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let entry = addEntry("an ordinary day", to: context)
        let (store, builder) = makeStore()
        await store.refreshIfNeeded(revisions: .init(saver: 1, graph: 1), in: context)
        #expect(store.index.search(AskIndex.Query(terms: [.init(text: "deadline")], asOf: .now)).isEmpty)

        let insights = EntryInsights()
        insights.tags = ["deadline"]
        insights.entry = entry
        context.insert(insights)
        try context.saveStampingEntries(except: [entry.persistentModelID])

        // Entry count, link count, and entity count are all unchanged, and the entry's own stamp was
        // deliberately not touched. Only the graph revision moved.
        await store.refreshIfNeeded(revisions: .init(saver: 1, graph: 2), in: context)
        #expect(builder.builds == 2)
        #expect(store.index.search(AskIndex.Query(terms: [.init(text: "deadline")], asOf: .now)).isEmpty == false)
    }

    // The one the review caught. TranscriptionCoordinator, TitleCoordinator, and
    // PageTranscriptionCoordinator all write through saveStampingEntries, touching neither
    // EntrySaver nor GraphServices. Without a counter in the save path itself, a recording's
    // transcribed text never reached the index: the entry count doesn't move (the entry was already
    // there, awaiting text), and graph.revision only moves if insights later succeed, which they
    // don't when insights are off, the key is missing, or the phone is offline. Asking about the
    // entry you just recorded answered "nothing to go on" for the rest of the session.
    @Test func aSaveThroughTheStampingPathAloneForcesARebuild() async throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let entry = Entry(text: "")
        entry.awaitingText = true
        context.insert(entry)
        try context.saveStampingEntries()

        let (store, builder) = makeStore()
        func revisions() -> AskIndexStore.Revisions { .init(saver: 1, graph: 1, stamped: JournalSaves.revision) }
        await store.refreshIfNeeded(revisions: revisions(), in: context)
        #expect(store.index.search(AskIndex.Query(terms: [.init(text: "river")], asOf: .now)).isEmpty)

        // Exactly what the transcriber does when the text lands.
        entry.text = "Paddled the river for two hours"
        entry.awaitingText = false
        try context.saveStampingEntries()

        await store.refreshIfNeeded(revisions: revisions(), in: context)
        #expect(builder.builds == 2)
        #expect(store.index.search(AskIndex.Query(terms: [.init(text: "river")], asOf: .now)).isEmpty == false)
    }

    // The other half of the same rule, found on the phone: asking a question saves the conversation
    // through the same path, so every question bumped the counter and the next keystroke rebuilt an
    // index identical to the one it replaced. 565ms and three hundred documents, for nothing.
    @Test func savingAConversationDoesNotForceARebuild() async throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        addEntry("the deadline moved", to: context)
        try context.saveStampingEntries()

        let (store, builder) = makeStore()
        func revisions() -> AskIndexStore.Revisions { .init(saver: 1, graph: 1, stamped: JournalSaves.revision) }
        await store.refreshIfNeeded(revisions: revisions(), in: context)
        #expect(builder.builds == 1)

        // Exactly what AskService does when an answer lands.
        let conversation = AskConversation(title: "What happened with the deadline?")
        context.insert(conversation)
        let message = AskMessage(conversationID: conversation.id, index: 0, role: .user, text: "What happened with the deadline?")
        context.insert(message)
        try context.saveStampingEntries()

        await store.refreshIfNeeded(revisions: revisions(), in: context)
        #expect(builder.builds == 1, "a conversation is not journal content")

        // And an entry saved in the same breath as a conversation still counts, because the rule is
        // a list of what doesn't count rather than what does.
        addEntry("the kayak went in the water", to: context)
        context.insert(AskMessage(conversationID: conversation.id, index: 1, role: .assistant, text: "It moved twice."))
        try context.saveStampingEntries()

        await store.refreshIfNeeded(revisions: revisions(), in: context)
        #expect(builder.builds == 2)
    }

    @Test func theSaverRevisionAloneForcesARebuild() async throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        addEntry("an ordinary day", to: context)
        let (store, builder) = makeStore()
        await store.refreshIfNeeded(revisions: .init(saver: 1, graph: 1), in: context)
        await store.refreshIfNeeded(revisions: .init(saver: 2, graph: 1), in: context)
        #expect(builder.builds == 2)
    }

    @Test func aLinkOrAnEntityForcesARebuild() async throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let entry = addEntry("Maya came by", to: context)
        let (store, builder) = makeStore()
        await store.refreshIfNeeded(revisions: .init(), in: context)

        let entity = Entity(name: "Maya", key: "maya", kind: .person)
        context.insert(entity)
        try context.save()
        await store.refreshIfNeeded(revisions: .init(), in: context)
        #expect(builder.builds == 2)

        let link = EntityLink(surface: "Maya", kind: .person)
        context.insert(link)
        link.entityID = entity.id
        link.entryID = entry.id
        try context.save()
        await store.refreshIfNeeded(revisions: .init(), in: context)
        #expect(builder.builds == 3)
    }

    @Test func aSecondCallWaitsOnTheBuildAlreadyRunning() async throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        addEntry("the deadline moved", to: context)
        let (store, builder) = makeStore()

        // Ask appears and a question is sent a moment later. That is one intent, not two journals.
        // The builder is held mid-build, so the second caller genuinely arrives while the first is
        // running rather than finding a fingerprint already stamped.
        builder.hold()
        let first = Task { await store.refreshIfNeeded(revisions: .init(), in: context) }
        await builder.waitForBuildToStart()
        #expect(builder.builds == 1)

        let second = Task { await store.refreshIfNeeded(revisions: .init(), in: context) }
        builder.release()
        await first.value
        await second.value
        #expect(builder.builds == 1)
        #expect(store.index.documents.count == 1)
    }

    // MARK: - What the index holds

    @Test func draftsAreNeverIndexedAndHeldEntriesAreIndexedButNotSendable() async throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        addEntry("a draft in progress", to: context, isDraft: true)
        addEntry("a finished entry", to: context)
        let awaiting = addEntry("a recording", to: context)
        awaiting.awaitingText = true
        try context.save()

        let (store, _) = makeStore()
        await store.refreshIfNeeded(revisions: .init(), in: context)

        // The panel can show the entry awaiting text; Ask may not send it. The draft is in neither.
        #expect(store.index.documents.count == 2)
        #expect(store.index.documents.count { $0.isSendable } == 1)
    }

    @Test func aHiddenEntityIsNeitherATermNorNameable() async throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let entry = addEntry("dinner and a long talk", to: context)
        let hidden = Entity(name: "Hidden", key: "hidden", kind: .person)
        hidden.hidden = true
        context.insert(hidden)
        try context.save()
        let link = EntityLink(surface: "Hidden", kind: .person)
        context.insert(link)
        link.entityID = hidden.id
        link.entryID = entry.id
        try context.save()

        let (store, _) = makeStore()
        await store.refreshIfNeeded(revisions: .init(), in: context)
        #expect(store.index.entities.isEmpty)
        #expect(store.index.search(AskIndex.Query(terms: [.init(text: "hidden")], asOf: .now)).isEmpty)
    }

    @Test func anEntrysTagsAreasAndMoodBecomeSearchableTerms() async throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let entry = addEntry("nothing in the words themselves", to: context)
        let insights = EntryInsights()
        insights.tags = ["deadline"]
        insights.areasRaw = [LifeArea.work.rawValue]
        insights.primaryMoodRaw = Mood.allCases.first?.rawValue
        insights.entry = entry
        context.insert(insights)
        try context.save()

        let (store, _) = makeStore()
        await store.refreshIfNeeded(revisions: .init(), in: context)
        let document = try #require(store.index.document(withID: entry.id))
        #expect(document.tags == ["deadline"])
        #expect(document.areas == ["Work"])
        #expect(store.index.search(AskIndex.Query(terms: [.init(text: "work")], asOf: .now)).isEmpty == false)
    }

    // MARK: - The estimate reads a snapshot, never the journal

    @Test func theSnapshotSurvivesTheJournalGoingAway() async throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        addEntry("the deadline moved", to: context)
        let (store, _) = makeStore()
        await store.refreshIfNeeded(revisions: .init(), in: context)

        for entry in (try? context.fetch(FetchDescriptor<Entry>())) ?? [] {
            context.delete(entry)
        }
        try context.save()

        // Nothing re-read the store, so the numbers the cost line would show still come from the
        // snapshot. This is what "the estimate performs no fetch" looks like from outside.
        #expect(store.index.documents.count == 1)
        #expect(store.index.search(AskIndex.Query(terms: [.init(text: "deadline")], asOf: .now)).isEmpty == false)
    }

    // MARK: - The gate

    @Test func blocksFetchOnlyWhatThePlanChoseAndCheckEligibilityAgain() async throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let wanted = addEntry("the deadline moved", to: context)
        let other = addEntry("something else entirely", to: context)
        let stale = addEntry("was fine when the index was built", to: context)

        var plan = AskRetrieval.Plan()
        plan.rankedEntryIDs = [wanted.id, stale.id]

        // The index is a snapshot, so an entry can have gone back to awaiting text since.
        stale.awaitingText = true
        try context.save()

        let selection = AskSources.blocks(for: plan, in: context)
        #expect(selection.entries.map(\.id) == [wanted.id])
        #expect(selection.entries.contains { $0.id == other.id } == false)
    }

    @Test func blocksKeepThePlansRanking() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let first = addEntry("one", to: context)
        let second = addEntry("two", to: context)
        let third = addEntry("three", to: context)

        var plan = AskRetrieval.Plan()
        plan.rankedEntryIDs = [third.id, first.id]
        plan.continuityEntryIDs = [second.id]

        // A fetch returns whatever order the store likes; the ranking has to survive it.
        let selection = AskSources.blocks(for: plan, in: context)
        #expect(selection.entries.map(\.id) == [third.id, first.id, second.id])
    }

    @Test func blocksDescribeOnlyBrowsableEntitiesAMentionableEntryStillCarries() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let entry = addEntry("Maya and Hidden both came by", to: context)
        let visible = Entity(name: "Maya", key: "maya", kind: .person)
        visible.bio = "A friend from the climbing gym."
        let hidden = Entity(name: "Hidden", key: "hidden", kind: .person)
        hidden.hidden = true
        hidden.bio = "Should never be described."
        context.insert(visible)
        context.insert(hidden)
        try context.save()
        for entity in [visible, hidden] {
            let link = EntityLink(surface: entity.name, kind: .person)
            context.insert(link)
            link.entityID = entity.id
            link.entryID = entry.id
        }
        try context.save()

        var plan = AskRetrieval.Plan()
        plan.aboutEntityIDs = [visible.id, hidden.id]
        #expect(AskSources.blocks(for: plan, in: context).entities.map(\.id) == [visible.id])
    }

    // The index is a snapshot. In the window where an entry has gone back to awaiting text, the
    // entity it was the only mention of must stop being describable too: its bio and its loose ends
    // were written out of that entry's text.
    @Test func anEntityLosesItsBlockWhenItsOnlyMentionStopsBeingSendable() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let entry = addEntry("Maya came by", to: context)
        let maya = Entity(name: "Maya", key: "maya", kind: .person)
        maya.bio = "Written out of that one entry."
        context.insert(maya)
        try context.save()
        let link = EntityLink(surface: "Maya", kind: .person)
        context.insert(link)
        link.entityID = maya.id
        link.entryID = entry.id
        try context.save()

        var plan = AskRetrieval.Plan()
        plan.aboutEntityIDs = [maya.id]
        #expect(AskSources.blocks(for: plan, in: context).entities.map(\.id) == [maya.id])

        entry.awaitingText = true
        try context.save()
        #expect(AskSources.blocks(for: plan, in: context).entities.isEmpty)
    }

    @Test func anEmptyPlanFetchesNothing() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        addEntry("the deadline moved", to: context)
        let selection = AskSources.blocks(for: AskRetrieval.Plan(), in: context)
        #expect(selection.entries.isEmpty)
        #expect(selection.entities.isEmpty)
    }
}
