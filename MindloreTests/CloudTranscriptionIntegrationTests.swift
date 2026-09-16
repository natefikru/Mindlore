import Foundation
import SwiftData
import Testing
@testable import Mindlore

// The real key setup, router, OpenAI transcriber, and coordinator working together. Only HTTP is faked.
@MainActor
final class CloudHarness {
    let container: ModelContainer
    let settings: SettingsStore
    let accounts: ProviderAccountStore
    let http: FakeHTTPClient
    let onDevice = FakeTranscriber()
    let directory: URL
    let log: DiagnosticsLog
    private(set) var coordinator: TranscriptionCoordinator!

    var context: ModelContext { container.mainContext }

    init(http: FakeHTTPClient, key: String? = "sk-integration", fallback: Bool = true, log: DiagnosticsLog = .disabled) throws {
        self.http = http
        self.log = log
        container = try ModelContainerFactory.make(.inMemory)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("CloudHarness-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        settings = SettingsStore(store: FakeKeyValueStore(), diagnostics: log, now: { Date(timeIntervalSince1970: 1_000) })
        accounts = ProviderAccountStore(settings: settings, secrets: FakeSecretStore(), http: http, diagnostics: log)
        if let key { try accounts.saveOpenAIKey(key) }
        settings.fallBackToOnDevice = fallback
        settings.aiEnabled = true
        let router = TranscriberRouter(settings: settings, accounts: accounts, http: accounts.http, onDevice: onDevice)
        coordinator = TranscriptionCoordinator(
            route: router.route(for:manualRetry:),
            locale: Locale(identifier: "en_US"),
            temporaryDirectory: directory,
            diagnostics: log,
            beginBackgroundTask: { _ in {} }
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func recording(seconds: Double = 1) throws -> Entry {
        let caf = directory.appendingPathComponent("\(UUID().uuidString).caf")
        _ = try AudioFixtures.writePCM(to: caf, seconds: seconds)
        let entry = Entry(createdAt: Date(timeIntervalSince1970: 5_000), source: .voice, awaitingText: true, audioData: try AudioConverter.convertToAAC(caf).data, audioDuration: seconds)
        context.insert(entry)
        try context.save()
        return entry
    }
}

@MainActor
struct CloudTranscriptionIntegrationTests {
    @Test func savedKeyTranscribesThroughOpenAI() async throws {
        let harness = try CloudHarness(http: FakeHTTPClient(FakeHTTPClient.json(200, ["text": "Hello from the cloud."])))
        let entry = try harness.recording()

        await harness.coordinator.processQueue(context: harness.context)

        #expect(entry.text == "Hello from the cloud.")
        #expect(entry.textGeneratedBy == "openai:gpt-transcribe")
        #expect(!entry.awaitingText)
        #expect(harness.onDevice.calls.isEmpty)
        let sent = try #require(harness.http.sent.first)
        #expect(sent.request.url?.absoluteString == "https://api.openai.com/v1/audio/transcriptions")
        #expect(sent.request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-integration")
        #expect(sent.bodyText.contains("name=\"model\"\r\n\r\ngpt-transcribe\r\n"))
        #expect(sent.body.map(OpenAICompatibleTranscriber.isM4AUpload) == true)
    }

    @Test func changedSpeechModelIsUsedForTheNextRecording() async throws {
        let harness = try CloudHarness(http: FakeHTTPClient(FakeHTTPClient.json(200, ["text": "one"])))
        harness.settings.speechModel = "gpt-4o-mini-transcribe"
        let entry = try harness.recording()

        await harness.coordinator.processQueue(context: harness.context)

        #expect(entry.textGeneratedBy == "openai:gpt-4o-mini-transcribe")
        #expect(harness.http.sent.first?.bodyText.contains("gpt-4o-mini-transcribe") == true)
    }

    @Test func rejectedKeyFallsBackToThePhoneAndSaysWhy() async throws {
        let harness = try CloudHarness(http: FakeHTTPClient(FakeHTTPClient.error(401, code: "invalid_api_key")))
        harness.onDevice.automaticResult = .success("From the phone.")
        let entry = try harness.recording()

        await harness.coordinator.processQueue(context: harness.context)

        #expect(entry.text == "From the phone.")
        #expect(entry.textGeneratedBy == "apple")
        #expect(entry.textFallbackReasonRaw == "ai.invalidKey")
        #expect(AIJobFailure(raw: entry.textFallbackReasonRaw!).userMessage == AIError.invalidKey.userMessage)
    }

    @Test func rejectedKeyWithoutFallbackWaitsForRetryAndIsNotResent() async throws {
        let harness = try CloudHarness(http: FakeHTTPClient(FakeHTTPClient.error(401)), fallback: false)
        let entry = try harness.recording()

        await harness.coordinator.processQueue(context: harness.context)
        await harness.coordinator.processQueue(context: harness.context)

        #expect(harness.http.sent.count == 1)
        #expect(entry.awaitingText)
        #expect(entry.textFailureRaw == "ai.invalidKey")
    }

    @Test func removingTheKeySendsRecordingsToThePhone() async throws {
        let harness = try CloudHarness(http: FakeHTTPClient())
        try harness.accounts.remove(try #require(harness.accounts.openAIAccount))
        harness.onDevice.automaticResult = .success("on device")
        let entry = try harness.recording()

        await harness.coordinator.processQueue(context: harness.context)

        #expect(harness.http.sent.isEmpty)
        #expect(entry.text == "on device")
        #expect(entry.textGeneratedBy == "apple")
    }

    @Test func turningAIOffSendsRecordingsToThePhone() async throws {
        let harness = try CloudHarness(http: FakeHTTPClient())
        harness.settings.aiEnabled = false
        harness.onDevice.automaticResult = .success("on device")
        let entry = try harness.recording()

        await harness.coordinator.processQueue(context: harness.context)

        #expect(harness.http.sent.isEmpty)
        #expect(entry.textGeneratedBy == "apple")
    }

    @Test func keyAndProviderErrorBodiesNeverReachTheLog() async throws {
        let file = DiagnosticsFile()
        let log = DiagnosticsLog(fileURL: file.url)
        let sentinel = DiagnosticsPrivacyTests.sentinel
        let errorBody = #"{"error":{"message":"You said \#(sentinel) in your audio","code":"invalid_value"}}"#
        let http = FakeHTTPClient(
            .success(HTTPResponse(status: 400, headers: [:], data: Data(errorBody.utf8))),
            .success(HTTPResponse(status: 400, headers: [:], data: Data(errorBody.utf8)))
        )
        let harness = try CloudHarness(http: http, key: "sk-\(sentinel)", log: log)
        harness.onDevice.automaticResult = .failure(TranscriptionError.analysisFailed(sentinel))
        _ = try harness.recording()

        await harness.coordinator.processQueue(context: harness.context)
        _ = await harness.accounts.testConnection()

        let contents = file.contents()
        #expect(contents.contains("transcription.fallback"))
        #expect(contents.contains("ai.error"))
        #expect(contents.contains("ai.keySaved"))
        #expect(contents.contains("ai.connectionTested"))
        #expect(contents.contains(sentinel) == false)
    }
}
