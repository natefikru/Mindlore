import Foundation
import SwiftData
import Testing
@testable import Mindlore

@MainActor
final class FakePageTranscriber: PageTranscriber {
    var requests: [PageRequest] = []
    // Keyed by page number; a missing entry answers with "Text of page N."
    var failures: [Int: any Error] = [:]
    var writtenDates: [Int: Date] = [:]
    var suspendOnPage: Int?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var suspended: CheckedContinuation<Void, Never>?

    nonisolated func transcribe(_ request: PageRequest) async throws -> PageResult {
        try await handle(request)
    }

    private func handle(_ request: PageRequest) async throws -> PageResult {
        requests.append(request)
        let current = waiters
        waiters = []
        current.forEach { $0.resume() }
        if suspendOnPage == request.pageNumber {
            suspendOnPage = nil
            await withCheckedContinuation { suspended = $0 }
        }
        if let failure = failures.removeValue(forKey: request.pageNumber) { throw failure }
        return PageResult(text: "Text of page \(request.pageNumber).", writtenDate: writtenDates[request.pageNumber], inputTokens: 1, outputTokens: 1)
    }

    func waitForRequest(number: Int) async {
        while requests.count < number {
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    func resume() {
        suspended?.resume()
        suspended = nil
    }
}

@MainActor
final class PageHarness {
    let container: ModelContainer
    let transcriber = FakePageTranscriber()
    var unavailable: AIJobFailure?
    var suggestDates = true
    private(set) var coordinator: PageTranscriptionCoordinator!

    var context: ModelContext { container.mainContext }

    init() throws {
        container = try ModelContainerFactory.make(.inMemory)
        coordinator = makeCoordinator()
    }

    func makeCoordinator() -> PageTranscriptionCoordinator {
        PageTranscriptionCoordinator(
            resolve: { [unowned self] in
                if let unavailable = self.unavailable { return .failure(unavailable) }
                return .success(.init(transcriber: self.transcriber, label: "openai:vision"))
            },
            suggestEntryDates: { [unowned self] in self.suggestDates },
            diagnostics: .disabled,
            beginBackgroundTask: { _ in {} },
            prepareUpload: { $0 }
        )
    }

    func confirmedEntry(pages: Int, aiUsable: Bool = true) throws -> Entry {
        let entry = Entry(createdAt: Date(timeIntervalSince1970: 5_000), source: .photo)
        context.insert(entry)
        let processed = (0..<pages).map { PageImageProcessor.ProcessedPage(imageData: Data([UInt8($0)]), thumbnailData: Data([1]), pixelWidth: 100 + $0, pixelHeight: 100) }
        entry.addPages(processed, origin: .camera, in: context)
        entry.confirmPages(aiUsable: aiUsable)
        try context.save()
        return entry
    }
}

@MainActor
struct PageTranscriptionCoordinatorTests {
    @Test func transcribesPagesInOrderWithThePreviousTailAndWaitsForReview() async throws {
        let harness = try PageHarness()
        let entry = try harness.confirmedEntry(pages: 3)

        await harness.coordinator.processQueue(context: harness.context)

        #expect(harness.transcriber.requests.map(\.pageNumber) == [1, 2, 3])
        #expect(harness.transcriber.requests.map(\.pageCount) == [3, 3, 3])
        #expect(harness.transcriber.requests[0].previousPageTail == nil)
        #expect(harness.transcriber.requests[1].previousPageTail == "Text of page 1.")
        #expect(harness.transcriber.requests[0].imageJPEG == Data([0]))
        #expect(entry.text == "Text of page 1.\n\nText of page 2.\n\nText of page 3.")
        #expect(entry.textReviewPending)
        #expect(!entry.awaitingText)
        #expect(entry.textGeneratedBy == "openai:vision")
        #expect(entry.textAttempts == 0)
        #expect(entry.pageRequestCount == 3)
    }

    @Test func aFailureKeepsFinishedPagesAndResendsOnlyTheRest() async throws {
        let harness = try PageHarness()
        let entry = try harness.confirmedEntry(pages: 3)
        harness.transcriber.failures[3] = AIError.serverError(status: 500)

        await harness.coordinator.processQueue(context: harness.context)
        #expect(entry.sortedPages.map(\.transcribedText) == ["Text of page 1.", "Text of page 2.", nil])
        #expect(entry.awaitingText)
        // The pass saved pages, so it didn't use up an attempt.
        #expect(entry.textAttempts == 0)
        #expect(entry.textFailureRaw == "ai.serverError")

        await harness.makeCoordinator().processQueue(context: harness.context)
        #expect(harness.transcriber.requests.map(\.pageNumber) == [1, 2, 3, 3])
        #expect(harness.transcriber.requests.last?.previousPageTail == "Text of page 2.")
        #expect(entry.textReviewPending)
    }

    @Test func blankPagesCountAsDoneAndAreNotResent() async throws {
        let harness = try PageHarness()
        let entry = try harness.confirmedEntry(pages: 2)
        entry.sortedPages[0].transcribedText = ""
        try harness.context.save()

        await harness.coordinator.processQueue(context: harness.context)

        #expect(harness.transcriber.requests.map(\.pageNumber) == [2])
        #expect(entry.text == "Text of page 2.")
    }

    @Test func requestCapStopsAutomaticRetries() async throws {
        let harness = try PageHarness()
        let entry = try harness.confirmedEntry(pages: 1)
        harness.transcriber.failures = [1: AIError.serverError(status: 500)]

        for _ in 0..<6 {
            harness.transcriber.failures[1] = AIError.serverError(status: 500)
            await harness.makeCoordinator().processQueue(context: harness.context)
        }

        #expect(harness.transcriber.requests.count <= 1 + PageTranscriptionCoordinator.extraRequestsAllowed)
        #expect(!AIJobPolicy.canRunAutomatically(.text, entry))
    }

    @Test func offlineDoesNotCountAndPausesUntilTheNetworkReturns() async throws {
        let harness = try PageHarness()
        let entry = try harness.confirmedEntry(pages: 1)
        harness.transcriber.failures[1] = AIError.offline(.notConnectedToInternet)

        await harness.coordinator.processQueue(context: harness.context)
        #expect(harness.coordinator.pausedForOffline)
        #expect(entry.textAttempts == 0)

        await harness.coordinator.processQueue(context: harness.context)
        #expect(harness.transcriber.requests.count == 1)

        await harness.coordinator.networkBecameAvailable(context: harness.context)
        #expect(entry.textReviewPending)
    }

    @Test func typingDuringTranscriptionWinsAndPagesKeepTheirText() async throws {
        let harness = try PageHarness()
        let entry = try harness.confirmedEntry(pages: 2)
        harness.transcriber.suspendOnPage = 2

        let task = Task { await harness.coordinator.processQueue(context: harness.context) }
        await harness.transcriber.waitForRequest(number: 2)
        entry.text = "I typed it myself"
        entry.userDidEditText()
        harness.transcriber.resume()
        await task.value

        #expect(entry.text == "I typed it myself")
        #expect(!entry.textReviewPending)
        #expect(entry.allPagesTranscribed)
        #expect(entry.canReplaceWithPageTranscription)

        #expect(entry.replaceWithPageTranscription())
        #expect(entry.text == "Text of page 1.\n\nText of page 2.")
        #expect(entry.textReviewPending)
        #expect(!entry.canReplaceWithPageTranscription)
    }

    @Test func restartDuringAnInFlightPageWritesNothing() async throws {
        let harness = try PageHarness()
        let entry = try harness.confirmedEntry(pages: 2)
        harness.transcriber.suspendOnPage = 1

        let task = Task { await harness.coordinator.processQueue(context: harness.context) }
        await harness.transcriber.waitForRequest(number: 1)
        let draft = Array(PageDraftItem.draft(from: entry).reversed())
        entry.restartPages(applying: draft, aiUsable: false, in: harness.context)
        harness.transcriber.resume()
        await task.value

        #expect(entry.sortedPages.allSatisfy { $0.transcribedText == nil })
        #expect(entry.text.isEmpty)
        #expect(harness.transcriber.requests.count == 1)
    }

    // A date at the top of a page is the day the page was written, so the entry takes it without
    // asking (owner, 2026-09-23); the typed-entry setting has no say. Turning suggestions off
    // still turns this off.
    @Test func aPagesWrittenDateBecomesTheEntryDateWhenEnabled() async throws {
        let harness = try PageHarness()
        let march3 = Date(timeIntervalSince1970: 1_741_003_200)
        let entry = try harness.confirmedEntry(pages: 2)
        let added = entry.createdAt
        harness.transcriber.writtenDates = [2: march3]

        await harness.coordinator.processQueue(context: harness.context)
        #expect(EntryDates.isSameDay(entry.entryDate, march3))
        #expect(entry.entryDateIsDayOnly)
        #expect(entry.suggestedEntryDate == nil, "applied, so there is nothing left to offer")
        #expect(entry.createdAt == added, "the day it reached the app still drives automation")

        let picked = try PageHarness()
        picked.transcriber.writtenDates = [1: march3]
        let backdated = try picked.confirmedEntry(pages: 1)
        backdated.setEntryDay(Date(timeIntervalSince1970: 1_000_000_000))
        let day = backdated.entryDate
        await picked.coordinator.processQueue(context: picked.context)
        #expect(backdated.entryDate == day, "a picked day is only offered another")
        #expect(backdated.suggestedEntryDate != nil)

        let off = try PageHarness()
        off.suggestDates = false
        off.transcriber.writtenDates = [1: march3]
        let other = try off.confirmedEntry(pages: 1)
        await off.coordinator.processQueue(context: off.context)
        #expect(other.suggestedEntryDate == nil)
    }

    @Test func withoutAIThePagesWaitAndTranscribePagesStartsThem() async throws {
        let harness = try PageHarness()
        let entry = try harness.confirmedEntry(pages: 1, aiUsable: false)

        await harness.coordinator.processQueue(context: harness.context)
        #expect(harness.transcriber.requests.isEmpty)

        await harness.coordinator.transcribePages(for: entry, context: harness.context)
        #expect(entry.textReviewPending)
    }

    @Test func transcribePagesNeverOverwritesTypedText() async throws {
        let harness = try PageHarness()
        let entry = try harness.confirmedEntry(pages: 1, aiUsable: false)
        entry.text = "typed"
        entry.userDidEditText()

        await harness.coordinator.transcribePages(for: entry, context: harness.context)

        #expect(harness.transcriber.requests.isEmpty)
        #expect(entry.text == "typed")
    }

    @Test func unavailableAIShowsWhyWithoutSending() async throws {
        let harness = try PageHarness()
        let entry = try harness.confirmedEntry(pages: 1)
        harness.unavailable = AIJobFailure(.missingKey)

        await harness.coordinator.processQueue(context: harness.context)

        #expect(harness.transcriber.requests.isEmpty)
        #expect(harness.coordinator.activity[entry.id] == .failed(AIError.missingKey.userMessage))
        #expect(entry.awaitingText)
    }
}

@MainActor
struct PageReviewTests {
    private func reviewedEntry(_ harness: PageHarness) async throws -> Entry {
        let entry = try harness.confirmedEntry(pages: 2)
        await harness.coordinator.processQueue(context: harness.context)
        return entry
    }

    @Test func approvingClearsReviewAndFiresTheAutomaticPassOnce() async throws {
        let harness = try PageHarness()
        let entry = try await reviewedEntry(harness)
        let settings = SettingsStore(store: FakeKeyValueStore(), diagnostics: .disabled, now: { Date(timeIntervalSince1970: 1_000) })
        settings.recordAutomationStartIfNeeded()
        let trigger = AIPassTrigger(settings: settings, presence: EditorPresence(), titleUsable: { true }, diagnostics: .disabled)

        #expect(!trigger.fire(for: entry, at: .editorClosed))
        #expect(trigger.sweep(context: harness.context) == 0)

        #expect(entry.approveText())
        #expect(!entry.approveText())
        #expect(trigger.fire(for: entry, at: .approved))
        #expect(entry.titlePending)
        #expect(!trigger.fire(for: entry, at: .editorClosed))
    }

    @Test func restartClearsEverythingDerivedAndKeepsPagesAndDates() async throws {
        let harness = try PageHarness()
        let entry = try await reviewedEntry(harness)
        entry.approveText()
        entry.title = "Old title"
        entry.titleWasGenerated = true
        entry.automaticAIPassUsed = true
        entry.titlePending = true
        entry.setEntryDay(Date(timeIntervalSince1970: 0))
        entry.suggestedEntryDate = Date(timeIntervalSince1970: 86_400 * 400)
        let insights = EntryInsights(modelUsed: "m")
        harness.context.insert(insights)
        insights.entry = entry
        try harness.context.save()
        let createdAt = entry.createdAt
        let entryDate = entry.entryDate
        let revision = entry.contentRevision

        var draft = PageDraftItem.draft(from: entry)
        draft.swapAt(0, 1)
        #expect(PageDraftItem.differs(draft, from: entry))
        entry.restartPages(applying: draft, aiUsable: true, in: harness.context)
        try harness.context.save()

        #expect(entry.contentRevision == revision + 1)
        #expect(entry.text.isEmpty && entry.title.isEmpty && !entry.titleWasGenerated)
        #expect(!entry.textReviewPending && !entry.textWasGenerated && entry.textGeneratedBy == nil)
        #expect(entry.suggestedEntryDate == nil)
        #expect(!entry.titlePending && !entry.insightsPending && !entry.automaticAIPassUsed)
        #expect(entry.pageRequestCount == 0 && entry.textAttempts == 0)
        #expect(entry.insights == nil)
        #expect(try harness.context.fetchCount(FetchDescriptor<EntryInsights>()) == 0)
        #expect(entry.sortedPages.map(\.pixelWidth) == [101, 100])
        #expect(entry.sortedPages.allSatisfy { $0.transcribedText == nil })
        #expect(entry.pagesConfirmed && entry.awaitingText)
        #expect(entry.createdAt == createdAt && entry.entryDate == entryDate)
    }

    @Test func draftsAddAndRemovePagesOnRestart() async throws {
        let harness = try PageHarness()
        let entry = try await reviewedEntry(harness)
        var draft = PageDraftItem.draft(from: entry)
        #expect(!PageDraftItem.differs(draft, from: entry))

        draft.remove(at: 0)
        draft.append(PageDraftItem(content: .new(PageImageProcessor.ProcessedPage(imageData: Data([9]), thumbnailData: Data([9]), pixelWidth: 999, pixelHeight: 9), .library)))
        #expect(PageDraftItem.differs(draft, from: entry))
        entry.restartPages(applying: draft, aiUsable: false, in: harness.context)
        try harness.context.save()

        #expect(entry.sortedPages.map(\.pixelWidth) == [101, 999])
        #expect(entry.sortedPages.map(\.index) == [0, 1])
        #expect(try harness.context.fetchCount(FetchDescriptor<EntryPage>()) == 2)
        #expect(!entry.awaitingText)
    }

    @Test func aRestartedEntryCanBeTranscribedAndReviewedAgain() async throws {
        let harness = try PageHarness()
        let entry = try await reviewedEntry(harness)
        var draft = PageDraftItem.draft(from: entry)
        draft.swapAt(0, 1)
        entry.restartPages(applying: draft, aiUsable: true, in: harness.context)
        try harness.context.save()

        await harness.coordinator.processQueue(context: harness.context)

        #expect(entry.textReviewPending)
        #expect(harness.transcriber.requests.count == 4)
    }
}
