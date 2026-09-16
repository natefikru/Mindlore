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

// Cloud routing, persisted failures, fallback, and offline behavior.
@MainActor
struct TranscriptionRoutingTests {
    private func coordinator(_ harness: TranscriptionHarness, cloud: FakeTranscriber?, fallback: Bool, onDevice: FakeTranscriber? = nil, prompts: PromptLog? = nil) -> TranscriptionCoordinator {
        let onDevice = onDevice ?? harness.transcriber
        return TranscriptionCoordinator(
            route: { _, _ in
                guard let cloud else { return .onDevice(onDevice) }
                return TranscriptionRoute(
                    cloud: .init(label: "openai:test", makeTranscriber: { prompt in prompts?.prompts.append(prompt); return cloud }, chunkTargetSeconds: 1_200, maxUploadBytes: 25_000_000),
                    onDevice: onDevice,
                    onDeviceLabel: "apple",
                    fallBackToOnDevice: fallback
                )
            },
            locale: Locale(identifier: "en_US"),
            temporaryDirectory: harness.temporaryDirectory,
            diagnostics: .disabled,
            beginBackgroundTask: { _ in {} }
        )
    }

    final class PromptLog {
        var prompts: [String?] = []
    }

    @Test func voiceQueueIgnoresPhotoEntries() async throws {
        let harness = try TranscriptionHarness()
        let photo = Entry(source: .photo, awaitingText: true, audioData: TranscriptionHarness.m4aBytes)
        harness.context.insert(photo)
        try harness.context.save()
        harness.transcriber.automaticResult = .success("should not happen")

        await harness.coordinator.processQueue(context: harness.context)

        #expect(harness.transcriber.calls.isEmpty)
        #expect(photo.textAttempts == 0)
    }

    @Test func permanentFailureIsNotRetriedAfterRelaunch() async throws {
        let harness = try TranscriptionHarness()
        let entry = try harness.voiceEntry()
        let cloud = FakeTranscriber()
        cloud.automaticResult = .failure(AIError.invalidKey)

        await coordinator(harness, cloud: cloud, fallback: false).processQueue(context: harness.context)
        #expect(entry.textFailureRaw == "ai.invalidKey")
        #expect(entry.textAttempts == 1)

        // A new coordinator over the same store stands in for the next launch.
        await coordinator(harness, cloud: cloud, fallback: false).processQueue(context: harness.context)
        #expect(cloud.calls.count == 1)
        #expect(entry.awaitingText)
    }

    @Test func retryableFailureRetriesOncePerLaunchUntilTheCap() async throws {
        let harness = try TranscriptionHarness()
        let entry = try harness.voiceEntry()
        let cloud = FakeTranscriber()
        cloud.automaticResult = .failure(AIError.serverError(status: 503))

        let first = coordinator(harness, cloud: cloud, fallback: false)
        await first.processQueue(context: harness.context)
        await first.processQueue(context: harness.context)
        #expect(cloud.calls.count == 1)

        for _ in 0..<4 {
            await coordinator(harness, cloud: cloud, fallback: false).processQueue(context: harness.context)
        }
        #expect(cloud.calls.count == 3)
        #expect(entry.textAttempts == 3)
    }

    @Test func attemptIsSavedBeforeTheRequestReturns() async throws {
        let harness = try TranscriptionHarness()
        let entry = try harness.voiceEntry()
        let cloud = FakeTranscriber()
        let running = coordinator(harness, cloud: cloud, fallback: false)

        let task = Task { await running.processQueue(context: harness.context) }
        await cloud.waitForCall(number: 1)
        #expect(try harness.persisted(entry.id)?.textAttempts == 1)

        cloud.answer(.success("done"))
        await task.value
        #expect(entry.textAttempts == 0)
        #expect(entry.text == "done")
        #expect(entry.textGeneratedBy == "openai:test")
    }

    @Test func offlineWithoutFallbackPausesAndResumesWhenTheNetworkReturns() async throws {
        let harness = try TranscriptionHarness()
        let entry = try harness.voiceEntry()
        let cloud = FakeTranscriber()
        cloud.automaticResult = .failure(AIError.offline(.notConnectedToInternet))
        let running = coordinator(harness, cloud: cloud, fallback: false)

        await running.processQueue(context: harness.context)
        #expect(running.pausedForOffline)
        #expect(entry.textAttempts == 0)

        await running.processQueue(context: harness.context)
        #expect(cloud.calls.count == 1)

        cloud.automaticResult = .success("back online")
        await running.networkBecameAvailable(context: harness.context)
        #expect(entry.text == "back online")
        #expect(!running.pausedForOffline)
    }

    @Test func cloudFailureFallsBackToOnDeviceAndRecordsWhy() async throws {
        let harness = try TranscriptionHarness()
        let entry = try harness.voiceEntry()
        let cloud = FakeTranscriber()
        cloud.automaticResult = .failure(AIError.network(.timedOut))
        harness.transcriber.automaticResult = .success("from the phone")
        var readyIDs: [PersistentIdentifier] = []
        let running = coordinator(harness, cloud: cloud, fallback: true)
        running.onTextReady = { readyIDs.append($0) }

        await running.processQueue(context: harness.context)

        #expect(entry.text == "from the phone")
        #expect(entry.textGeneratedBy == "apple")
        #expect(entry.textFallbackReasonRaw == "ai.network")
        #expect(entry.textAttempts == 0)
        #expect(entry.textFailureRaw == nil)
        #expect(readyIDs == [entry.persistentModelID])
        #expect(!running.pausedForOffline)
    }

    @Test func fallbackFailureRecordsTheOnDeviceError() async throws {
        let harness = try TranscriptionHarness()
        let entry = try harness.voiceEntry()
        let cloud = FakeTranscriber()
        cloud.automaticResult = .failure(AIError.serverError(status: 500))
        harness.transcriber.automaticResult = .failure(TranscriptionError.unsupportedLocale)

        await coordinator(harness, cloud: cloud, fallback: true).processQueue(context: harness.context)

        #expect(entry.textFailureRaw == "speech.unsupportedLocale")
        #expect(entry.awaitingText)
    }

    @Test func cloudNoSpeechIsNotUploadedAgain() async throws {
        let harness = try TranscriptionHarness()
        let entry = try harness.voiceEntry()
        let cloud = FakeTranscriber()
        cloud.automaticResult = .failure(TranscriptionError.noSpeechDetected)

        await coordinator(harness, cloud: cloud, fallback: true).processQueue(context: harness.context)
        await coordinator(harness, cloud: cloud, fallback: true).processQueue(context: harness.context)

        #expect(cloud.calls.count == 1)
        #expect(harness.transcriber.calls.isEmpty)
        #expect(entry.textFailureRaw == "speech.noSpeechDetected")
    }

    @Test func longRecordingsAreChunkedWithThePreviousTextAsPrompt() async throws {
        let harness = try TranscriptionHarness()
        let caf = harness.temporaryDirectory.appendingPathComponent("long.caf")
        _ = try AudioFixtures.writePCM(to: caf, seconds: 9)
        let entry = try harness.voiceEntry(audio: try AudioConverter.convertToAAC(caf).data)
        let cloud = FakeTranscriber()
        let prompts = PromptLog()
        let running = TranscriptionCoordinator(
            route: { _, _ in
                TranscriptionRoute(
                    cloud: .init(label: "openai:test", makeTranscriber: { prompt in prompts.prompts.append(prompt); return cloud }, chunkTargetSeconds: 4, maxUploadBytes: 25_000_000),
                    onDevice: harness.transcriber, onDeviceLabel: "apple", fallBackToOnDevice: false
                )
            },
            locale: Locale(identifier: "en_US"),
            temporaryDirectory: harness.temporaryDirectory,
            diagnostics: .disabled,
            chunkSearchSeconds: 1,
            beginBackgroundTask: { _ in {} }
        )

        let task = Task { await running.processQueue(context: harness.context) }
        await cloud.waitForCall(number: 1)
        cloud.answer(.success("first part"))
        await cloud.waitForCall(number: 2)
        cloud.answer(.success("second part"))
        await cloud.waitForCall(number: 3)
        cloud.answer(.success("third part"))
        await task.value

        #expect(prompts.prompts == [nil, "first part", "second part"])
        #expect(entry.text == "first part second part third part")
    }

    @Test func oneFailedChunkFailsTheEntryAsOneAttempt() async throws {
        let harness = try TranscriptionHarness()
        let caf = harness.temporaryDirectory.appendingPathComponent("long.caf")
        _ = try AudioFixtures.writePCM(to: caf, seconds: 9)
        let entry = try harness.voiceEntry(audio: try AudioConverter.convertToAAC(caf).data)
        let cloud = FakeTranscriber()
        let running = TranscriptionCoordinator(
            route: { _, _ in
                TranscriptionRoute(
                    cloud: .init(label: "openai:test", makeTranscriber: { _ in cloud }, chunkTargetSeconds: 4, maxUploadBytes: 25_000_000),
                    onDevice: harness.transcriber, onDeviceLabel: "apple", fallBackToOnDevice: false
                )
            },
            locale: Locale(identifier: "en_US"),
            temporaryDirectory: harness.temporaryDirectory,
            diagnostics: .disabled,
            chunkSearchSeconds: 1,
            beginBackgroundTask: { _ in {} }
        )

        let task = Task { await running.processQueue(context: harness.context) }
        await cloud.waitForCall(number: 1)
        cloud.answer(.success("first part"))
        await cloud.waitForCall(number: 2)
        cloud.answer(.failure(AIError.serverError(status: 502)))
        await task.value

        #expect(cloud.calls.count == 2)
        #expect(entry.textAttempts == 1)
        #expect(entry.text.isEmpty)
        #expect(entry.awaitingText)
    }

    @Test func retryWhileOfflineStillSends() async throws {
        let harness = try TranscriptionHarness()
        let entry = try harness.voiceEntry()
        let cloud = FakeTranscriber()
        cloud.automaticResult = .failure(AIError.offline(.notConnectedToInternet))
        let running = coordinator(harness, cloud: cloud, fallback: false)
        await running.processQueue(context: harness.context)
        #expect(running.pausedForOffline)

        cloud.automaticResult = .success("sent on retry")
        await running.retry(entry.persistentModelID, context: harness.context)

        #expect(cloud.calls.count == 2)
        #expect(entry.text == "sent on retry")
        #expect(!running.pausedForOffline)
    }

    @Test func nonProviderCloudFailuresFallBackToo() async throws {
        let harness = try TranscriptionHarness()
        let entry = try harness.voiceEntry()
        let cloud = FakeTranscriber()
        cloud.automaticResult = .failure(TranscriptionError.analysisFailed("conversion"))
        harness.transcriber.automaticResult = .success("the phone read it")

        await coordinator(harness, cloud: cloud, fallback: true).processQueue(context: harness.context)

        #expect(entry.text == "the phone read it")
        #expect(entry.textFallbackReasonRaw == "speech.analysisFailed")
    }

    @Test func manualRetryResetsAPermanentFailure() async throws {
        let harness = try TranscriptionHarness()
        let entry = try harness.voiceEntry()
        let cloud = FakeTranscriber()
        cloud.automaticResult = .failure(AIError.quotaExceeded)
        let running = coordinator(harness, cloud: cloud, fallback: false)
        await running.processQueue(context: harness.context)

        cloud.automaticResult = .success("paid up")
        await running.retry(entry.persistentModelID, context: harness.context)

        #expect(entry.text == "paid up")
        #expect(entry.textFailureRaw == nil)
    }
}

@MainActor
struct TranscriberRouterTests {
    private func makeRouter(aiEnabled: Bool = true, engine: SpeechEngine = .cloud, key: Bool = true, fallback: Bool = true, enabledAt: Date = Date(timeIntervalSince1970: 1_000)) throws -> TranscriberRouter {
        var clock = enabledAt
        let settings = SettingsStore(store: FakeKeyValueStore(), diagnostics: .disabled, now: { clock })
        let accounts = ProviderAccountStore(settings: settings, secrets: FakeSecretStore(), diagnostics: .disabled)
        if key { try accounts.saveOpenAIKey("sk-test") }
        settings.speechEngine = engine
        settings.fallBackToOnDevice = fallback
        settings.aiEnabled = aiEnabled
        clock = .now
        return TranscriberRouter(settings: settings, accounts: accounts, http: FakeHTTPClient(), onDevice: FakeTranscriber())
    }

    private let newEntry = Entry(createdAt: Date(timeIntervalSince1970: 5_000), source: .voice)
    private let oldEntry = Entry(createdAt: Date(timeIntervalSince1970: 10), source: .voice)

    @Test func cloudWhenAIIsOnWithAKeyForNewRecordings() throws {
        let route = try makeRouter().route(for: newEntry, manualRetry: false)
        #expect(route.cloud?.label == "openai:gpt-transcribe")
        #expect(route.fallBackToOnDevice)
        #expect(route.cloud?.chunkTargetSeconds == 1_200)
    }

    @Test func onDeviceWhenAIIsOffTheKeyIsMissingOrEngineIsOnDevice() throws {
        #expect(try makeRouter(aiEnabled: false).route(for: newEntry, manualRetry: false).cloud == nil)
        #expect(try makeRouter(key: false).route(for: newEntry, manualRetry: false).cloud == nil)
        #expect(try makeRouter(engine: .onDevice).route(for: newEntry, manualRetry: false).cloud == nil)
    }

    // A live recording that couldn't run live, or dropped partway, falls back to the phone rather
    // than to OpenAI. Picking an on-device engine means audio never leaves the device, and the
    // batch tier behind tier 1 has to honour that too.
    @Test func aLiveRecordingFallsBackToThePhoneNeverToTheCloud() throws {
        let route = try makeRouter(engine: .onDeviceLive).route(for: newEntry, manualRetry: false)
        #expect(route.cloud == nil)
        #expect(route.onDeviceLabel == "apple")

        // Even a manual retry, which normally sends an old recording to the cloud, stays on-device.
        #expect(try makeRouter(engine: .onDeviceLive).route(for: oldEntry, manualRetry: true).cloud == nil)
    }

    @Test func recordingsFromBeforeAIWasOnGoToTheCloudOnlyOnRetry() throws {
        let router = try makeRouter()
        #expect(router.route(for: oldEntry, manualRetry: false).cloud == nil)
        #expect(router.route(for: oldEntry, manualRetry: true).cloud != nil)
    }

    @Test func fallbackFollowsTheSetting() throws {
        #expect(try makeRouter(fallback: false).route(for: newEntry, manualRetry: false).fallBackToOnDevice == false)
    }
}
