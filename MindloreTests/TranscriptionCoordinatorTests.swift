import Foundation
import SwiftData
import Testing
@testable import Mindlore

// Each call suspends until the test answers it, so tests can act while transcription is in flight.
@MainActor
final class FakeTranscriber: Transcriber {
    struct Call {
        let url: URL
        let locale: Locale
        let fileContents: Data?
    }

    private(set) var calls: [Call] = []
    private var pending: [CheckedContinuation<Result<String, any Error>, Never>] = []
    private var callWaiters: [CheckedContinuation<Void, Never>] = []
    var automaticResult: Result<String, any Error>?

    func transcribe(audioFileURL: URL, locale: Locale) async throws -> String {
        calls.append(Call(url: audioFileURL, locale: locale, fileContents: try? Data(contentsOf: audioFileURL)))
        let waiters = callWaiters
        callWaiters = []
        waiters.forEach { $0.resume() }

        if let automaticResult {
            return try automaticResult.get()
        }
        let result = await withCheckedContinuation { pending.append($0) }
        return try result.get()
    }

    func waitForCall(number: Int) async {
        while calls.count < number {
            await withCheckedContinuation { callWaiters.append($0) }
        }
    }

    func answer(_ result: Result<String, any Error>) {
        pending.removeFirst().resume(returning: result)
    }
}

@MainActor
final class TranscriptionHarness {
    let container: ModelContainer
    let transcriber = FakeTranscriber()
    let temporaryDirectory: URL
    private(set) var coordinator: TranscriptionCoordinator!

    var context: ModelContext { container.mainContext }

    init() throws {
        container = try ModelContainerFactory.make(.inMemory)
        temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("TranscriptionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        coordinator = TranscriptionCoordinator(
            transcriber: transcriber,
            locale: Locale(identifier: "en_US"),
            temporaryDirectory: temporaryDirectory
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    nonisolated static let m4aBytes = Data([0, 0, 0, 24]) + Data("ftypM4A ".utf8) + Data(repeating: 7, count: 16)

    @discardableResult
    func voiceEntry(createdAt: Date = .now, audio: Data = TranscriptionHarness.m4aBytes) throws -> Entry {
        let entry = Entry(createdAt: createdAt, source: .voice, awaitingText: true, audioData: audio, audioDuration: 1)
        context.insert(entry)
        try context.save()
        return entry
    }

    func persisted(_ id: UUID) throws -> Entry? {
        try ModelContext(container).fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id })).first
    }
}

@MainActor
struct TranscriptionCoordinatorTests {
    @Test func successfulTranscriptionFillsTheEntryAndSaves() async throws {
        let harness = try TranscriptionHarness()
        let entry = try harness.voiceEntry()
        harness.transcriber.automaticResult = .success("Walked to the river.")

        await harness.coordinator.processQueue(context: harness.context)

        #expect(entry.text == "Walked to the river.")
        #expect(entry.awaitingText == false)
        #expect(entry.textWasGenerated)
        #expect(harness.coordinator.activity[entry.persistentModelID] == nil)
        #expect(try harness.persisted(entry.id)?.text == "Walked to the river.")
    }

    @Test func generatedTextStampsUpdatedAt() async throws {
        let harness = try TranscriptionHarness()
        let entry = try harness.voiceEntry(createdAt: Date(timeIntervalSince1970: 100))
        harness.transcriber.automaticResult = .success("hello")

        await harness.coordinator.processQueue(context: harness.context)

        #expect(entry.updatedAt > Date(timeIntervalSince1970: 100))
    }

    @Test func emptyTranscriptKeepsTheEntryWaitingWithAnExplanation() async throws {
        let harness = try TranscriptionHarness()
        let entry = try harness.voiceEntry()
        harness.transcriber.automaticResult = .success("")

        await harness.coordinator.processQueue(context: harness.context)

        #expect(entry.awaitingText)
        #expect(entry.textWasGenerated == false)
        #expect(harness.coordinator.activity[entry.persistentModelID] == .unsupported(TranscriptionError.noSpeechDetected.userMessage))
    }

    @Test func transcriberReceivesTheAudioAsATemporaryFileThatIsCleanedUp() async throws {
        let harness = try TranscriptionHarness()
        try harness.voiceEntry()
        harness.transcriber.automaticResult = .success("ok")

        await harness.coordinator.processQueue(context: harness.context)

        let call = try #require(harness.transcriber.calls.first)
        #expect(call.fileContents == TranscriptionHarness.m4aBytes)
        #expect(call.url.pathExtension == "m4a")
        #expect(call.locale.identifier == "en_US")
        #expect(FileManager.default.fileExists(atPath: call.url.path) == false)
    }

    @Test func failureKeepsTheEntryWaitingAndIsNotRetriedAutomatically() async throws {
        let harness = try TranscriptionHarness()
        let entry = try harness.voiceEntry()
        harness.transcriber.automaticResult = .failure(TranscriptionError.assetsUnavailable("offline"))

        await harness.coordinator.processQueue(context: harness.context)

        #expect(entry.awaitingText)
        #expect(entry.text.isEmpty)
        #expect(harness.coordinator.activity[entry.persistentModelID] == .failed(TranscriptionError.assetsUnavailable("offline").userMessage))

        await harness.coordinator.processQueue(context: harness.context)
        #expect(harness.transcriber.calls.count == 1)
    }

    @Test func retryRunsAFailedEntryAgain() async throws {
        let harness = try TranscriptionHarness()
        let entry = try harness.voiceEntry()
        harness.transcriber.automaticResult = .failure(TranscriptionError.analysisFailed("boom"))
        await harness.coordinator.processQueue(context: harness.context)

        harness.transcriber.automaticResult = .success("second time lucky")
        await harness.coordinator.retry(entry.persistentModelID, context: harness.context)

        #expect(entry.text == "second time lucky")
        #expect(harness.coordinator.activity[entry.persistentModelID] == nil)
    }

    @Test func permanentErrorsAreReportedAsUnsupported() async throws {
        let harness = try TranscriptionHarness()
        let entry = try harness.voiceEntry()
        harness.transcriber.automaticResult = .failure(TranscriptionError.unsupportedLocale)

        await harness.coordinator.processQueue(context: harness.context)

        #expect(harness.coordinator.activity[entry.persistentModelID] == .unsupported(TranscriptionError.unsupportedLocale.userMessage))
    }

    @Test func unexpectedErrorsAreReportedAsFailures() async throws {
        let harness = try TranscriptionHarness()
        let entry = try harness.voiceEntry()
        harness.transcriber.automaticResult = .failure(CocoaError(.fileReadCorruptFile))

        await harness.coordinator.processQueue(context: harness.context)

        guard case .failed = harness.coordinator.activity[entry.persistentModelID] else {
            Issue.record("expected a failure")
            return
        }
    }

    @Test func textTypedDuringTranscriptionIsNeverOverwritten() async throws {
        let harness = try TranscriptionHarness()
        let entry = try harness.voiceEntry()

        let processing = Task { await harness.coordinator.processQueue(context: harness.context) }
        await harness.transcriber.waitForCall(number: 1)
        #expect(harness.coordinator.activity[entry.persistentModelID] == .transcribing)

        entry.text = "I'll type it myself"
        entry.userDidEditText()
        harness.transcriber.answer(.success("generated text"))
        await processing.value

        #expect(entry.text == "I'll type it myself")
        #expect(entry.textWasGenerated == false)
        #expect(harness.coordinator.activity[entry.persistentModelID] == nil)
    }

    @Test func entryDeletedDuringTranscriptionIsSkippedSafely() async throws {
        let harness = try TranscriptionHarness()
        let entry = try harness.voiceEntry()
        let id = entry.id

        let processing = Task { await harness.coordinator.processQueue(context: harness.context) }
        await harness.transcriber.waitForCall(number: 1)
        Entry.delete(entry, in: harness.context)
        try harness.context.save()
        harness.transcriber.answer(.success("too late"))
        await processing.value

        #expect(try harness.persisted(id) == nil)
        #expect(try harness.context.fetch(FetchDescriptor<Entry>()).isEmpty)
    }

    @Test func entriesThatAreNotWaitingAreNeverTranscribed() async throws {
        let harness = try TranscriptionHarness()
        harness.context.insert(Entry(text: "typed"))
        harness.context.insert(Entry(source: .voice, text: "already has text", audioData: TranscriptionHarness.m4aBytes))
        try harness.context.save()
        harness.transcriber.automaticResult = .success("unused")

        await harness.coordinator.processQueue(context: harness.context)

        #expect(harness.transcriber.calls.isEmpty)
    }

    @Test func waitingEntryWithoutAudioIsSkipped() async throws {
        let harness = try TranscriptionHarness()
        harness.context.insert(Entry(source: .voice, awaitingText: true))
        try harness.context.save()
        harness.transcriber.automaticResult = .success("unused")

        await harness.coordinator.processQueue(context: harness.context)

        #expect(harness.transcriber.calls.isEmpty)
    }

    @Test func queuedEntriesAreProcessedOldestFirst() async throws {
        let harness = try TranscriptionHarness()
        let newer = try harness.voiceEntry(createdAt: Date(timeIntervalSince1970: 200))
        let older = try harness.voiceEntry(createdAt: Date(timeIntervalSince1970: 100))

        let processing = Task { await harness.coordinator.processQueue(context: harness.context) }
        await harness.transcriber.waitForCall(number: 1)
        harness.transcriber.answer(.success("older"))
        await harness.transcriber.waitForCall(number: 2)
        harness.transcriber.answer(.success("newer"))
        await processing.value

        #expect(older.text == "older")
        #expect(newer.text == "newer")
    }

    @Test func entryRecordedWhileBusyIsPickedUpInTheSameRun() async throws {
        let harness = try TranscriptionHarness()
        let first = try harness.voiceEntry(createdAt: Date(timeIntervalSince1970: 100))

        let processing = Task { await harness.coordinator.processQueue(context: harness.context) }
        await harness.transcriber.waitForCall(number: 1)
        let second = try harness.voiceEntry(createdAt: Date(timeIntervalSince1970: 200))
        await harness.coordinator.processQueue(context: harness.context)
        harness.transcriber.answer(.success("first"))
        await harness.transcriber.waitForCall(number: 2)
        harness.transcriber.answer(.success("second"))
        await processing.value

        #expect(first.text == "first")
        #expect(second.text == "second")
        #expect(harness.transcriber.calls.count == 2)
    }

    @Test func undecodedRecordingsAreHandedOverAsCAF() {
        #expect(TranscriptionCoordinator.fileExtension(for: TranscriptionHarness.m4aBytes) == "m4a")
        #expect(TranscriptionCoordinator.fileExtension(for: Data("caff....".utf8)) == "caf")
        #expect(TranscriptionCoordinator.fileExtension(for: Data([1, 2])) == "caf")
    }

    @Test func errorsThatNeedTheUserAreMarkedPermanent() {
        #expect(TranscriptionError.authorizationDenied.isPermanent)
        #expect(TranscriptionError.unsupportedLocale.isPermanent)
        #expect(TranscriptionError.noSpeechDetected.isPermanent)
        #expect(TranscriptionError.assetsUnavailable("x").isPermanent == false)
        #expect(TranscriptionError.analysisFailed("x").isPermanent == false)
    }
}
