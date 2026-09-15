import Foundation
import SwiftData
import Testing
@testable import Mindlore

@MainActor
struct DraftTests {
    private func trigger() -> AIPassTrigger {
        let settings = SettingsStore(store: FakeKeyValueStore(), diagnostics: .disabled, now: { Date(timeIntervalSince1970: 1_000) })
        settings.recordAutomationStartIfNeeded()
        return AIPassTrigger(settings: settings, presence: EditorPresence(), titleUsable: { true }, insightsUsable: { true }, diagnostics: .disabled)
    }

    private func draft(_ text: String, in context: ModelContext) -> Entry {
        let entry = Entry(createdAt: Date(timeIntervalSince1970: 5_000), text: text)
        entry.isDraft = true
        context.insert(entry)
        return entry
    }

    @Test func aDraftNeverGetsThePassUntilDone() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let entry = draft("half written", in: container.mainContext)
        let pass = trigger()

        #expect(!pass.fire(for: entry, at: .editorClosed))
        #expect(pass.sweep(context: container.mainContext) == 0)
        #expect(!entry.titlePending && !entry.insightsPending)

        #expect(entry.finishDraft())
        #expect(pass.fire(for: entry, at: .finished))
        #expect(entry.titlePending && entry.insightsPending)

        // Editing and finishing again doesn't bring the pass back.
        entry.text += " more"
        entry.userDidEditText()
        #expect(!entry.isDraft)
        #expect(!entry.finishDraft())
        #expect(!pass.fire(for: entry, at: .editorClosed))
    }

    @Test func typingOverAPendingRecordingMakesADraft() {
        let voice = Entry(createdAt: Date(timeIntervalSince1970: 5_000), source: .voice, awaitingText: true, audioData: Data([1]))
        voice.text = "typed instead"
        voice.userDidEditText()
        #expect(voice.isDraft)
    }

    @Test func editingATranscribedRecordingStaysFinished() {
        let voice = Entry(createdAt: Date(timeIntervalSince1970: 5_000), source: .voice, awaitingText: true, audioData: Data([1]))
        voice.applyGeneratedText("spoken words")
        voice.text += " fixed"
        voice.userDidEditText()
        #expect(!voice.isDraft)
        #expect(AIPassTrigger.isEligible(voice, automationStartedAt: .distantPast))
    }

    @Test func typingIntoUntranscribedPagesMakesADraftButEditingApprovedTextDoesnt() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let saved = Entry(createdAt: Date(timeIntervalSince1970: 5_000), source: .photo)
        container.mainContext.insert(saved)
        saved.pagesConfirmed = true
        saved.text = "typed from the pages"
        saved.userDidEditText()
        #expect(saved.isDraft)

        let transcribed = Entry(createdAt: Date(timeIntervalSince1970: 5_000), source: .photo, awaitingText: true)
        container.mainContext.insert(transcribed)
        transcribed.pagesConfirmed = true
        transcribed.applyGeneratedText("page text")
        transcribed.textReviewPending = true
        transcribed.approveText()
        transcribed.text += " corrected"
        transcribed.userDidEditText()
        #expect(!transcribed.isDraft)
    }

    @Test func entriesThatAlreadyHadTheirPassDontBecomeDrafts() {
        let entry = Entry(createdAt: Date(timeIntervalSince1970: 5_000), source: .voice, awaitingText: true, audioData: Data([1]))
        entry.automaticAIPassUsed = true
        entry.userDidEditText()
        #expect(!entry.isDraft)
    }

    @Test func draftsAreNeverAnalyzedUntilTheyAreFinished() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let entry = draft("text", in: container.mainContext)
        #expect(!InsightsCoordinator.canRunAI(on: entry))

        entry.finishDraft()
        #expect(InsightsCoordinator.canRunAI(on: entry))
    }

    @Test func insightsRunWhileAFinishedEntryIsOpenButCleanupWaits() async throws {
        let harness = try InsightsHarness()
        harness.autoApply = true
        let entry = try harness.entry("i walked to the river and it was calm", source: .voice)
        harness.presence.open(entry.id)
        harness.generator.results = [.success(InsightsHarness.fullResponse)]

        await harness.coordinator.processQueue(context: harness.context)

        #expect(entry.insights?.summary == "A river walk.")
        #expect(entry.text == "i walked to the river and it was calm")
        #expect(entry.originalText == nil)
    }
}
