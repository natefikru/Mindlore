import Foundation
import SwiftData
import Testing
@testable import Mindlore

@MainActor
final class FakeTextGenerator: TextGenerator {
    var requests: [TextRequest] = []
    var results: [Result<String, any Error>] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var pending: [CheckedContinuation<Result<String, any Error>, Never>] = []
    var suspends = false

    nonisolated func generate(_ request: TextRequest) async throws -> TextResult {
        let text = try await record(request).get()
        return TextResult(text: text, model: request.model, inputTokens: 10, outputTokens: 5)
    }

    private func record(_ request: TextRequest) async -> Result<String, any Error> {
        requests.append(request)
        let current = waiters
        waiters = []
        current.forEach { $0.resume() }
        if suspends {
            return await withCheckedContinuation { pending.append($0) }
        }
        return results.isEmpty ? .success("Untitled Result") : results.removeFirst()
    }

    func waitForRequest(number: Int) async {
        while requests.count < number {
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    func answer(_ result: Result<String, any Error>) {
        pending.removeFirst().resume(returning: result)
    }
}

@MainActor
struct EntryTitleTests {
    @Test func displayTitlePrefersTheTitleThenTheFirstLine() {
        let entry = Entry(text: "  Walked to the river this morning.\nThe light was strange.")
        #expect(entry.displayTitle == "Walked to the river this morning.")

        entry.title = "River walk"
        #expect(entry.displayTitle == "River walk")

        #expect(Entry().displayTitle == "Untitled")
    }

    @Test func longFirstLinesAreCutAtAWordBoundary() {
        let entry = Entry(text: "Today I finally sat down to write about everything that happened at the reunion last weekend")
        #expect(entry.displayTitle == "Today I finally sat down to write about everything that…")
        #expect(entry.displayTitle.count <= 61)

        let oneWord = Entry(text: String(repeating: "a", count: 100))
        #expect(oneWord.displayTitle == String(repeating: "a", count: 60) + "…")
    }

    @Test func generatedTitlesNeverReplaceATypedOne() {
        let entry = Entry(text: "text")
        #expect(entry.applyGeneratedTitle("First Guess"))
        #expect(entry.titleWasGenerated)
        #expect(entry.applyGeneratedTitle("Better Guess"))
        #expect(entry.title == "Better Guess")

        entry.userDidEditTitle("Mine")
        #expect(!entry.titleWasGenerated)
        #expect(!entry.applyGeneratedTitle("Another"))
        #expect(entry.title == "Mine")

        entry.userDidEditTitle("")
        #expect(entry.applyGeneratedTitle("Handed back"))
    }

    @Test func cleaningStripsQuotesLabelsAndPunctuation() {
        #expect(TitleCoordinator.clean("\"A Walk by the River.\"") == "A Walk by the River")
        #expect(TitleCoordinator.clean("Title: Morning pages!\nextra line") == "Morning pages")
        #expect(TitleCoordinator.clean("   ") == "")
    }
}

@MainActor
final class TitleHarness {
    let container: ModelContainer
    let settings: SettingsStore
    let presence = EditorPresence()
    let generator = FakeTextGenerator()
    var resolveFailure: AIJobFailure?
    private(set) var trigger: AIPassTrigger!
    private(set) var titles: TitleCoordinator!
    var titleUsable = true

    var context: ModelContext { container.mainContext }

    init(started: Date = Date(timeIntervalSince1970: 1_000)) throws {
        container = try ModelContainerFactory.make(.inMemory)
        settings = SettingsStore(store: FakeKeyValueStore(), diagnostics: .disabled, now: { started })
        settings.recordAutomationStartIfNeeded()
        trigger = AIPassTrigger(settings: settings, presence: presence, titleUsable: { [unowned self] in self.titleUsable }, diagnostics: .disabled)
        titles = TitleCoordinator(
            resolve: { [unowned self] in
                if let failure = self.resolveFailure { return .failure(failure) }
                return .success(.init(generator: self.generator, model: "title-model", label: "test"))
            },
            presence: presence,
            diagnostics: .disabled
        )
    }

    func typedEntry(_ text: String, createdAt: Date = Date(timeIntervalSince1970: 5_000)) throws -> Entry {
        let entry = Entry(createdAt: createdAt, text: text)
        context.insert(entry)
        try context.save()
        return entry
    }
}

@MainActor
struct AIPassTriggerTests {
    @Test func firesOnceAndFlagsTheTitle() throws {
        let harness = try TitleHarness()
        let entry = try harness.typedEntry("Walked to the river.")

        #expect(harness.trigger.fire(for: entry, at: .editorClosed))
        #expect(entry.automaticAIPassUsed && entry.titlePending)

        entry.titlePending = false
        #expect(!harness.trigger.fire(for: entry, at: .editorClosed))
        #expect(!entry.titlePending)
    }

    @Test func entriesFromBeforeAutomationStartedNeverFire() throws {
        let harness = try TitleHarness()
        let old = try harness.typedEntry("Old entry", createdAt: Date(timeIntervalSince1970: 10))
        #expect(!harness.trigger.fire(for: old, at: .editorClosed))
    }

    @Test func aBackdatedEntryAddedTodayStillFires() throws {
        let harness = try TitleHarness()
        let entry = try harness.typedEntry("From an old notebook")
        entry.setEntryDay(Date(timeIntervalSince1970: 0))
        #expect(harness.trigger.fire(for: entry, at: .editorClosed))
    }

    @Test func passIsUsedEvenWhenNothingIsEnabled() throws {
        let harness = try TitleHarness()
        harness.titleUsable = false
        let entry = try harness.typedEntry("text")

        #expect(harness.trigger.fire(for: entry, at: .editorClosed))
        #expect(entry.automaticAIPassUsed && !entry.titlePending)

        harness.titleUsable = true
        #expect(!harness.trigger.fire(for: entry, at: .editorClosed))
    }

    @Test func voiceEntryTheUserTypedIntoFires() throws {
        let harness = try TitleHarness()
        let entry = Entry(createdAt: Date(timeIntervalSince1970: 5_000), source: .voice, awaitingText: true, audioData: Data([1]))
        harness.context.insert(entry)
        #expect(!harness.trigger.fire(for: entry, at: .editorClosed))

        entry.text = "typed instead"
        entry.userDidEditText()
        #expect(harness.trigger.fire(for: entry, at: .editorClosed))
    }

    @Test func unconfirmedOrUnapprovedPhotoEntriesNeverFire() throws {
        let harness = try TitleHarness()
        let entry = Entry(createdAt: Date(timeIntervalSince1970: 5_000), source: .photo, text: "page text")
        harness.context.insert(entry)
        #expect(!harness.trigger.fire(for: entry, at: .launchSweep))

        entry.pagesConfirmed = true
        entry.textReviewPending = true
        #expect(!harness.trigger.fire(for: entry, at: .editorClosed))

        entry.textReviewPending = false
        #expect(harness.trigger.fire(for: entry, at: .approved))
    }

    @Test func launchSweepCatchesKilledEntriesButNotOpenOnes() throws {
        let harness = try TitleHarness()
        let killed = try harness.typedEntry("never closed")
        let open = try harness.typedEntry("still open")
        harness.presence.open(open.id)

        #expect(harness.trigger.sweep(context: harness.context) == 1)
        #expect(killed.automaticAIPassUsed)
        #expect(!open.automaticAIPassUsed)
    }

    @Test func typedTitleIsNotFlagged() throws {
        let harness = try TitleHarness()
        let entry = try harness.typedEntry("text")
        entry.userDidEditTitle("My own title")
        harness.trigger.fire(for: entry, at: .editorClosed)
        #expect(!entry.titlePending)
    }
}

@MainActor
struct TitleCoordinatorTests {
    @Test func generatesAndAppliesATitle() async throws {
        let harness = try TitleHarness()
        let entry = try harness.typedEntry("Walked to the river and saw herons.")
        harness.trigger.fire(for: entry, at: .editorClosed)
        harness.generator.results = [.success("\"Herons by the River.\"")]

        await harness.titles.processQueue(context: harness.context)

        #expect(entry.title == "Herons by the River")
        #expect(entry.titleWasGenerated)
        #expect(!entry.titlePending && entry.titleAttempts == 0)
        let request = try #require(harness.generator.requests.first)
        #expect(request.model == "title-model")
        #expect(request.user == "Walked to the river and saw herons.")
        #expect(request.schema == nil)
    }

    @Test func waitsWhileTheEntryIsOpen() async throws {
        let harness = try TitleHarness()
        let entry = try harness.typedEntry("text")
        harness.trigger.fire(for: entry, at: .editorClosed)
        harness.presence.open(entry.id)

        await harness.titles.processQueue(context: harness.context)
        #expect(harness.generator.requests.isEmpty)

        harness.presence.close(entry.id)
        await harness.titles.processQueue(context: harness.context)
        #expect(entry.titleWasGenerated)
    }

    @Test func resultIsDroppedWhenTheEntryWasRestartedMeanwhile() async throws {
        let harness = try TitleHarness()
        let entry = try harness.typedEntry("text")
        harness.trigger.fire(for: entry, at: .editorClosed)
        harness.generator.suspends = true

        let task = Task { await harness.titles.processQueue(context: harness.context) }
        await harness.generator.waitForRequest(number: 1)
        entry.contentRevision += 1
        harness.generator.answer(.success("Stale Title"))
        await task.value

        #expect(entry.title.isEmpty)
    }

    @Test func typingATitleDuringGenerationWins() async throws {
        let harness = try TitleHarness()
        let entry = try harness.typedEntry("text")
        harness.trigger.fire(for: entry, at: .editorClosed)
        harness.generator.suspends = true

        let task = Task { await harness.titles.processQueue(context: harness.context) }
        await harness.generator.waitForRequest(number: 1)
        entry.userDidEditTitle("Typed meanwhile")
        harness.generator.answer(.success("Generated"))
        await task.value

        #expect(entry.title == "Typed meanwhile")
        #expect(!entry.titlePending)
    }

    @Test func aTitleThatFinishesWhileTheEntryIsOpenWaitsForItToClose() async throws {
        let harness = try TitleHarness()
        let entry = try harness.typedEntry("text")
        harness.trigger.fire(for: entry, at: .editorClosed)
        harness.generator.suspends = true

        let task = Task { await harness.titles.processQueue(context: harness.context) }
        await harness.generator.waitForRequest(number: 1)
        harness.presence.open(entry.id)
        harness.generator.answer(.success("Held Title"))
        await task.value
        #expect(entry.title.isEmpty)
        #expect(!entry.titlePending)

        harness.presence.close(entry.id)
        await harness.titles.processQueue(context: harness.context)
        #expect(entry.title == "Held Title")
        #expect(harness.generator.requests.count == 1)
    }

    @Test func unavailableOnDeviceModelRecordsTheReason() async throws {
        let harness = try TitleHarness()
        let entry = try harness.typedEntry("text")
        harness.trigger.fire(for: entry, at: .editorClosed)
        harness.resolveFailure = AIJobFailure(OnDeviceModelError.unavailable(.appleIntelligenceNotEnabled))

        await harness.titles.processQueue(context: harness.context)

        #expect(harness.generator.requests.isEmpty)
        #expect(entry.titleFailureRaw == "device.appleIntelligenceNotEnabled")
        #expect(!entry.titlePending)
    }

    @Test func modelNotReadyRetriesNextLaunchUpToTheCap() async throws {
        let harness = try TitleHarness()
        let entry = try harness.typedEntry("text")
        harness.trigger.fire(for: entry, at: .editorClosed)
        harness.generator.results = Array(repeating: .failure(OnDeviceModelError.unavailable(.modelNotReady)), count: 5)

        await harness.titles.processQueue(context: harness.context)
        await harness.titles.processQueue(context: harness.context)
        #expect(harness.generator.requests.count == 1)
        #expect(entry.titlePending)

        let relaunched = TitleCoordinator(resolve: { .success(.init(generator: harness.generator, model: "m", label: "test")) }, presence: harness.presence, diagnostics: .disabled)
        await relaunched.processQueue(context: harness.context)
        let again = TitleCoordinator(resolve: { .success(.init(generator: harness.generator, model: "m", label: "test")) }, presence: harness.presence, diagnostics: .disabled)
        await again.processQueue(context: harness.context)

        #expect(harness.generator.requests.count == 2)
        #expect(!entry.titlePending)
    }

    @Test func runAIRegeneratesAGeneratedTitleButNotATypedOne() async throws {
        let harness = try TitleHarness()
        let entry = try harness.typedEntry("text")
        entry.applyGeneratedTitle("Old")
        harness.generator.results = [.success("New")]

        await harness.titles.runAI(for: entry, context: harness.context)
        #expect(entry.title == "New")

        entry.userDidEditTitle("Mine")
        await harness.titles.runAI(for: entry, context: harness.context)
        #expect(entry.title == "Mine")
        #expect(harness.generator.requests.count == 1)
    }
}
