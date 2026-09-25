import Foundation
import SwiftData
import Testing
@testable import Mindlore

// An entry saved with a plain `context.save()` stands in for one CloudKit brought from another
// phone: it never passes through the two save paths that claim what this phone made.
@MainActor
struct LocalOriginTests {
    private func registered(_ container: ModelContainer, store: FakeKeyValueStore = FakeKeyValueStore()) -> LocalOrigin {
        let origin = LocalOrigin(store: store, diagnostics: .disabled)
        LocalOrigin.register(origin, for: container)
        return origin
    }

    private func synced(_ entry: Entry, in context: ModelContext) throws -> Entry {
        context.insert(entry)
        try context.save()
        return entry
    }

    @Test func aContextWithNoOriginTreatsEveryEntryAsLocal() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let entry = try synced(Entry(text: "from anywhere"), in: container.mainContext)
        #expect(LocalOrigin.isLocal(entry))
    }

    @Test func bothSavePathsClaimWhatThisPhoneMade() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let origin = registered(container)

        let typed = Entry(text: "typed here")
        context.insert(typed)
        #expect(LocalOrigin.isLocal(typed), "an entry not yet saved was made here")
        try context.saveStampingEntries()
        #expect(origin.contains(typed.id))

        let saver = EntrySaver(context: context, diagnostics: .disabled)
        let recorded = Entry(source: .voice, text: "recorded here")
        context.insert(recorded)
        saver.flush()
        #expect(origin.contains(recorded.id))

        let other = try synced(Entry(text: "from the other phone"), in: context)
        #expect(!LocalOrigin.isLocal(other))
        #expect(LocalOrigin.isLocal(typed) && LocalOrigin.isLocal(recorded))
    }

    @Test func theSetOutlivesTheObjectThatHeldIt() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let store = FakeKeyValueStore()
        let entry = Entry(text: "kept")
        container.mainContext.insert(entry)
        registered(container, store: store).claim([entry.id])

        #expect(LocalOrigin(store: store, diagnostics: .disabled).contains(entry.id))
    }

    @Test func seedingClaimsTheJournalOnceAndNeverAgain() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let store = FakeKeyValueStore()
        let first = try synced(Entry(text: "already here"), in: context)

        let origin = registered(container, store: store)
        #expect(try origin.seedIfNeeded(from: context) == 1)
        #expect(LocalOrigin.isLocal(first))

        let arrived = try synced(Entry(text: "arrived later"), in: context)
        let relaunched = registered(container, store: store)
        #expect(try relaunched.seedIfNeeded(from: context) == 0)
        #expect(!LocalOrigin.isLocal(arrived))
        #expect(LocalOrigin.isLocal(first))
    }

    // MARK: - The automatic pass

    @Test func anotherPhonesEntryKeepsItsPass() throws {
        let harness = try TitleHarness()
        registered(harness.container)
        let entry = try harness.typedEntry("Walked by the river")

        #expect(!harness.trigger.fire(for: entry, at: .launchSweep))
        #expect(harness.trigger.sweep(context: harness.context) == 0)
        #expect(!entry.automaticAIPassUsed && !entry.titlePending && !entry.insightsPending)
        #expect(!harness.trigger.requestTitle(for: entry))

        LocalOrigin.claim(entry)
        #expect(harness.trigger.fire(for: entry, at: .launchSweep))
        #expect(entry.titlePending)
    }

    // MARK: - Coordinators

    @Test func titlesSkipAPendingFlagThatSyncedInUntilRunAI() async throws {
        let harness = try TitleHarness()
        registered(harness.container)
        let entry = try harness.typedEntry("A pending flag from the other phone")
        entry.titlePending = true
        try harness.context.save()

        await harness.titles.processQueue(context: harness.context)
        #expect(harness.generator.requests.isEmpty)
        #expect(entry.titlePending)

        await harness.titles.runAI(for: entry, context: harness.context)
        #expect(harness.generator.requests.count == 1)
        #expect(LocalOrigin.isLocal(entry))
    }

    @Test func insightsSkipAnotherPhonesEntryUntilRunAI() async throws {
        let harness = try InsightsHarness()
        registered(harness.container)
        let entry = try harness.entry("I walked to the river with Sarah.")
        harness.generator.results = [.success(InsightsHarness.fullResponse)]

        await harness.coordinator.processQueue(context: harness.context)
        #expect(harness.generator.requests.isEmpty)
        #expect(entry.insightsPending && entry.insights == nil)

        await harness.coordinator.runAI(for: entry, context: harness.context)
        #expect(harness.generator.requests.count == 1)
        #expect(entry.insights != nil)
        #expect(LocalOrigin.isLocal(entry))
    }

    @Test func transcriptionWaitsForTheOtherPhoneUntilTranscribeHere() async throws {
        let harness = try TranscriptionHarness()
        registered(harness.container)
        let entry = try harness.voiceEntry()
        harness.transcriber.automaticResult = .success("Walked to the river.")

        await harness.coordinator.processQueue(context: harness.context)
        #expect(entry.awaitingText)
        #expect(harness.coordinator.activity[entry.persistentModelID] == nil)

        await harness.coordinator.retry(entry.persistentModelID, context: harness.context)
        #expect(entry.text == "Walked to the river.")
        #expect(LocalOrigin.isLocal(entry))
    }
}
