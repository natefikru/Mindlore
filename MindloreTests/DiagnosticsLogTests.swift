import Foundation
import SwiftData
import Testing
@testable import Mindlore

@MainActor
final class DiagnosticsFile {
    let directory: URL
    let url: URL

    init() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("DiagnosticsLogTests-\(UUID().uuidString)", isDirectory: true)
        url = directory.appendingPathComponent("Logs/diagnostics.jsonl")
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func contents() -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func events() throws -> [[String: Any]] {
        try contents().split(separator: "\n").map { line in
            try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        }
    }
}

@MainActor
struct DiagnosticsLogTests {
    @Test func eachEventIsOneJSONLineWithTypedFields() throws {
        let file = DiagnosticsFile()
        let log = DiagnosticsLog(fileURL: file.url, session: "abc12345")
        let id = UUID()

        log.record("ingest.completed", ["id": .id(id), "audioBytes": 1_024, "seconds": 2.5, "converted": true, "reason": "test"])
        log.record("app.launch")

        let events = try file.events()
        #expect(events.count == 2)
        let first = events[0]
        #expect(first["event"] as? String == "ingest.completed")
        #expect(first["session"] as? String == "abc12345")
        #expect(first["id"] as? String == id.uuidString)
        #expect(first["audioBytes"] as? Int == 1_024)
        #expect(first["seconds"] as? Double == 2.5)
        #expect(first["converted"] as? Bool == true)
        #expect(first["reason"] as? String == "test")
        let timestamp = try #require(first["t"] as? String)
        #expect(timestamp.hasSuffix("Z") || timestamp.contains("+") || timestamp.dropFirst(19).contains("-"))
        #expect(events[1]["event"] as? String == "app.launch")
    }

    @Test func aNewInstanceAppendsToTheSameFile() throws {
        let file = DiagnosticsFile()
        DiagnosticsLog(fileURL: file.url, session: "first").record("one")
        DiagnosticsLog(fileURL: file.url, session: "second").record("two")

        let events = try file.events()
        #expect(events.map { $0["event"] as? String } == ["one", "two"])
        #expect(events.map { $0["session"] as? String } == ["first", "second"])
    }

    @Test func logRotatesWhenItGrowsPastTheLimit() throws {
        let file = DiagnosticsFile()
        let first = DiagnosticsLog(fileURL: file.url, maxBytes: 200)
        for index in 0..<10 {
            first.record("filler", ["index": .int(index)])
        }

        DiagnosticsLog(fileURL: file.url, maxBytes: 200).record("after.rotation")

        let rotated = file.url.deletingPathExtension().appendingPathExtension("1.jsonl")
        #expect(FileManager.default.fileExists(atPath: rotated.path))
        #expect(try file.events().map { $0["event"] as? String } == ["after.rotation"])
    }

    @Test func disabledLogWritesNothing() {
        let file = DiagnosticsFile()
        #expect(DiagnosticsLog.disabled.isEnabled == false)
        DiagnosticsLog.disabled.record("ignored")
        #expect(FileManager.default.fileExists(atPath: file.url.path) == false)
    }

    @Test func sharedLogIsDisabledUnderUnitTests() {
        #expect(DiagnosticsLog.shared.isEnabled == false)
    }

    @Test func concurrentWritesProduceOnlyCompleteLines() async throws {
        let file = DiagnosticsFile()
        let log = DiagnosticsLog(fileURL: file.url)

        await withTaskGroup(of: Void.self) { group in
            for worker in 0..<8 {
                group.addTask {
                    for index in 0..<50 {
                        log.record("concurrent", ["worker": .int(worker), "index": .int(index), "padding": .string(String(repeating: "x", count: 200))])
                    }
                }
            }
        }

        #expect(try file.events().count == 400)
    }

    @Test func saveErrorsAreReducedToDomainAndCode() {
        let error = NSError(domain: "NSCocoaErrorDomain", code: 1570, userInfo: [NSLocalizedDescriptionKey: "Entry text: my private thoughts"])
        #expect(DiagnosticValue.errorCode(error) == .string("NSCocoaErrorDomain 1570"))
    }
}

// Runs real app components against a sentinel used as entry text and generated text,
// then checks the sentinel never reached the log.
@MainActor
struct DiagnosticsPrivacyTests {
    static let sentinel = "PRIVATE-SENTINEL-7Q2X"

    @Test func entryTextNeverReachesTheLog() async throws {
        let file = DiagnosticsFile()
        let log = DiagnosticsLog(fileURL: file.url)
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext

        let saver = EntrySaver(context: context, interval: .milliseconds(10), diagnostics: log)
        let typed = Entry(text: "Dear diary \(Self.sentinel)")
        context.insert(typed)
        saver.noteChange()
        await saver.scheduledSave?.value
        typed.text += " more \(Self.sentinel)"
        saver.flush()

        let recordings = RecordingsDirectory(root: file.directory.appendingPathComponent("Recordings", isDirectory: true))
        let recordingURL = recordings.finished.appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
        try recordings.prepare()
        _ = try AudioFixtures.writePCM(to: recordingURL, seconds: 0.3)
        let ingestor = RecordingIngestor(diagnostics: log)
        let voice = try #require(await ingestor.ingest(recordingURL, context: context))

        let transcriber = FakeTranscriber()
        transcriber.automaticResult = .success("Spoken \(Self.sentinel)")
        let coordinator = TranscriptionCoordinator(transcriber: transcriber, temporaryDirectory: file.directory, diagnostics: log)
        await coordinator.processQueue(context: context)
        #expect(voice.text.contains(Self.sentinel))

        let failing = try #require(await ingestor.ingest(try {
            let url = recordings.finished.appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
            _ = try AudioFixtures.writePCM(to: url, seconds: 0.2)
            return url
        }(), context: context))
        transcriber.automaticResult = .failure(TranscriptionError.analysisFailed("framework said no"))
        await coordinator.processQueue(context: context)
        #expect(failing.awaitingText)

        let contents = file.contents()
        #expect(contents.contains("save.completed"))
        #expect(contents.contains("ingest.completed"))
        #expect(contents.contains("transcription.completed"))
        #expect(contents.contains("transcription.failed"))
        #expect(contents.contains(Self.sentinel) == false)
    }
}

// Every AI path, run against a sentinel string: entry text, title, tags, mention names, custom prompt
// wording, page text, the API key, a provider error body, and a decoding error. None may reach the log.
@MainActor
struct AIDiagnosticsPrivacyTests {
    private static let sentinel = DiagnosticsPrivacyTests.sentinel

    private func log(_ file: DiagnosticsFile) -> DiagnosticsLog {
        DiagnosticsLog(fileURL: file.url)
    }

    @Test func aiPathsNeverLogTextKeysOrProviderBodies() async throws {
        let file = DiagnosticsFile()
        let log = log(file)
        let sentinel = Self.sentinel
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext

        // Settings and keys: prompt wording and the key itself pass through here.
        let settings = SettingsStore(store: FakeKeyValueStore(), diagnostics: log)
        settings.customInsightPrompts = [CustomInsightPrompt(id: UUID(), name: "Name \(sentinel)", instructions: "Ask about \(sentinel)", enabled: true)]
        let errorBody = #"{"error":{"message":"your text \#(sentinel) was rejected","code":"invalid_value"}}"#
        let http = FakeHTTPClient(
            .success(HTTPResponse(status: 400, headers: [:], data: Data(errorBody.utf8))),
            .success(HTTPResponse(status: 400, headers: [:], data: Data(errorBody.utf8)))
        )
        let accounts = ProviderAccountStore(settings: settings, secrets: FakeSecretStore(), http: http, diagnostics: log)
        try accounts.saveOpenAIKey("sk-\(sentinel)")
        settings.aiEnabled = true
        _ = await accounts.testConnection()

        // An entry with the sentinel everywhere its text can go.
        let entry = Entry(source: .photo, text: "Dear diary, \(sentinel)")
        entry.title = "Title \(sentinel)"
        entry.pagesConfirmed = true
        context.insert(entry)
        let page = EntryPage(index: 0, imageData: Data([1, 2, 3]), thumbnailData: Data([1]), pixelWidth: 10, pixelHeight: 10, origin: .camera)
        context.insert(page)
        page.entry = entry
        try context.save()

        // Pages: a transcriber that answers with the sentinel, then one that fails with a decoding error.
        let pages = PageTranscriptionCoordinator(
            resolve: { .success(.init(transcriber: SentinelPageTranscriber(text: "Page text \(sentinel)"), label: "openai:test")) },
            diagnostics: log,
            beginBackgroundTask: { _ in {} },
            prepareUpload: { $0 }
        )
        entry.awaitingText = true
        await pages.processQueue(context: context)
        #expect(entry.text.contains(sentinel))

        // Insights: sentinel text in, sentinel-laden result out, and a failing run.
        let generator = FakeTextGenerator()
        generator.results = [
            .success(#"{"summary":"About \#(sentinel)","primaryMood":"calm","themes":["\#(sentinel)"],"tags":["\#(sentinel)"],"mentions":[{"name":"\#(sentinel)","kind":"person"}],"openThreads":["\#(sentinel)"]}"#),
            .failure(AIError.badRequest(code: "invalid_value")),
        ]
        let insights = InsightsCoordinator(
            resolve: { .success(.init(generator: generator, model: "m", label: "openai:m")) },
            sections: { AIServices.insightSections(settings) },
            autoApplyCleanedText: { false },
            presence: EditorPresence(),
            diagnostics: log
        )
        entry.textReviewPending = false
        entry.insightsPending = true
        await insights.processQueue(context: context)
        #expect(entry.insights?.summary?.contains(sentinel) == true)
        await insights.runAI(for: entry, context: context)

        // Titles, including a generator that throws a DecodingError carrying the sentinel.
        let titles = TitleCoordinator(
            resolve: { .success(.init(generator: generator, model: "m", label: "openai:m")) },
            presence: EditorPresence(),
            diagnostics: log
        )
        generator.results = [.failure(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad value \(sentinel)")))]
        entry.title = ""
        entry.titlePending = true
        await titles.processQueue(context: context)

        // The graph: entity names, aliases, and surface text all come from the sentinel above.
        let graph = GraphIndexer(diagnostics: log)
        let alias = Entity(name: "Alias holder \(sentinel)", key: "alias holder", kind: .person)
        alias.aliases = ["Also \(sentinel)"]
        alias.bio = "Bio \(sentinel)"
        context.insert(alias)
        try context.save()
        graph.index(entry, in: context)
        graph.recount(in: context)
        try context.save()
        #expect(entry.entityLinks?.isEmpty == false)

        let contents = file.contents()
        #expect(contents.contains("ai.keySaved"))
        #expect(contents.contains("pages.transcription.completed"))
        #expect(contents.contains("insights.completed"))
        #expect(contents.contains("insights.failed"))
        #expect(contents.contains("graph.indexed"))
        #expect(contents.contains("title.failed"))
        #expect(contents.contains("settings.changed"))
        #expect(contents.contains(sentinel) == false)
    }
}

@MainActor
private final class SentinelPageTranscriber: PageTranscriber {
    let text: String

    init(text: String) {
        self.text = text
    }

    nonisolated func transcribe(_ request: PageRequest) async throws -> PageResult {
        PageResult(text: await text, writtenDate: nil, inputTokens: 1, outputTokens: 1)
    }
}
