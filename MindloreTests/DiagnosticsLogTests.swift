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
// wording, page text, the API key, a provider error body, and a decoding error. None may reach the
// log, including during a merge or a local/global graph render over entities named with it.
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
        settings.rename(.work, to: "Work \(sentinel)")
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
            .success(#"{"summary":"About \#(sentinel)","primaryMood":"calm","lifeAreas":["work"],"tags":["\#(sentinel)"],"mentions":[{"name":"\#(sentinel)","kind":"person"}],"looseEnds":[{"text":"Call \#(sentinel)","about":["\#(sentinel)"],"due":null,"sameAs":null}]}"#),
            .failure(AIError.badRequest(code: "invalid_value")),
        ]
        let insights = InsightsCoordinator(
            resolve: { .success(.init(generator: generator, model: "m", label: "openai:m")) },
            sections: { AIServices.insightSections(settings) },
            // The user's own name goes into the system prompt under the name voice, so it runs
            // through a real pass here to prove it never reaches the log.
            promptVoice: { PromptVoice(voice: .name, name: sentinel) },
            autoApplyCleanedText: { false },
            presence: EditorPresence(),
            diagnostics: log
        )
        entry.textReviewPending = false
        entry.insightsPending = true
        await insights.processQueue(context: context)
        #expect(entry.insights?.summary?.contains(sentinel) == true)
        #expect(LooseEnd.all(in: context).contains { $0.text.contains(sentinel) })
        await insights.runAI(for: entry, context: context)
        #expect(LooseEnd.fade(in: context, now: .distantFuture, diagnostics: log) > 0)

        // Every section off asks the provider for an empty schema, so the run is skipped before
        // anything is sent. A voice entry, because a typed one would still be asked for its written
        // date and the schema would not be empty. The event names the entry and why, and gets the
        // same sentinel check as everything else here.
        settings.insightSummary = false
        settings.insightMoods = false
        settings.insightLifeAreas = false
        settings.insightTags = false
        settings.insightMentions = false
        settings.insightLooseEnds = false
        settings.insightCleanedText = false
        settings.customInsightPrompts = []
        let skipped = Entry(source: .voice, text: "Spoken \(sentinel)")
        context.insert(skipped)
        skipped.insightsPending = true
        try context.save()
        await insights.processQueue(context: context)
        #expect(skipped.insights == nil)
        // Left pending on purpose: turning a section back on runs it rather than skipping forever.
        #expect(skipped.insightsPending)

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
        #expect(graph.allLinks(in: context).contains { $0.entryID == entry.id })

        // Every edit the user can make, over entities whose every name carries the sentinel.
        let editor = GraphEditor(diagnostics: log)
        let named = try #require(graph.allLinks(in: context).first { $0.entryID == entry.id && $0.kind == .person })
        let namedID = try #require(named.entityID)
        let first = try #require(editor.entity(withID: namedID, in: context))
        let second = Entity(name: "Second \(sentinel)", key: "second", kind: .person)
        context.insert(second)
        try context.save()
        editor.rename(first, to: "Renamed \(sentinel)", in: context)
        editor.addAlias("Alias \(sentinel)", to: first, in: context)
        editor.setBio("Bio \(sentinel)", on: first)
        editor.setKind(.organization, on: first, in: context)
        editor.setHidden(true, on: second)
        editor.setHidden(false, on: second)
        editor.setResurfacingMuted(true, on: second)
        editor.markNotSame(first, as: second)
        editor.merge(second, into: first, in: context)
        editor.unmerge(second, in: context)
        editor.repoint(named, to: second, addingAlias: true, in: context)
        // The phone's own world: a contact identifier is not a name, but it identifies a person,
        // so only our own entity id is ever logged.
        let personForContact = Entity(name: "Contact \(sentinel)", key: "contact", kind: .person)
        context.insert(personForContact)
        try context.save()
        editor.linkContact(personForContact, identifier: "CN-\(sentinel)", in: context)
        editor.unlinkContact(personForContact, in: context)
        // A coordinate is personal data in its own right, so a linked place logs a bool.
        let placeForMap = Entity(name: "Place \(sentinel)", key: "place", kind: .place)
        context.insert(placeForMap)
        try context.save()
        editor.linkPlace(placeForMap, identifier: "MAPS-\(sentinel)", coordinate: PlaceCoordinate(latitude: 47.6062, longitude: -122.3321), in: context)
        editor.unlinkPlace(placeForMap, in: context)
        log.record("graph.contactAccess", ["status": .string(ContactAccess.denied.rawValue)])
        _ = graph.vocabulary(in: context)
        graph.sweep(in: context)

        // Mind: the map, the panel's rows, a review answer, and the focus and filter events,
        // over entities named with the sentinel. They carry counts and kinds only, but this proves
        // it over data that would leak if anything upstream forgot to resolve to plain ids first.
        let services = GraphServices(diagnostics: log)
        _ = services.primaryAreas(in: context)
        _ = MindDirectory.rows(in: context)
        let pair = ReviewQueue.Question.same(a: namedID, b: second.id)
        services.answer(pair, with: .skip, in: context)
        services.answer(pair, with: .notSame, in: context)
        services.recordMindFocused(source: .search, onMap: false)
        services.recordMindFiltersChanged(kinds: 3, minimum: 1, entries: true, regions: true, nodes: 2)
        let globalData = services.globalGraph(kinds: nil, minimumLinkCount: 0, in: context)
        services.recordGraphRendered(GraphRenderStats(
            nodes: globalData.nodes.count, edges: globalData.edges.count, settleMilliseconds: nil,
            frameSamples: 0, frameP50Milliseconds: nil, frameP95Milliseconds: nil, workP95Milliseconds: nil,
            entryNodes: 1, lens: .mood, replay: true
        ))

        // A5b: lenses, entry dots, regions, and a replay over the same data, with the renamed
        // Work area as a region label.
        let snapshot = services.mapSnapshot(in: context)
        let filters = MindFilters(kinds: Set(EntityKind.allCases), minimumMentions: 0, showsEntries: true, groupsByArea: true)
        let frame = MindView.frame(snapshot, filters: filters, visibleAreas: settings.visibleLifeAreas, asOf: .distantFuture)
        for lens in MindLens.allCases {
            _ = lens.paint(snapshot, onMap: Set(frame.nodes.map(\.id)), asOf: .distantFuture, generation: 1)
        }
        services.recordMindLensChanged(MindLens.recency.rawValue)
        let player = MindReplayPlayer()
        player.start(now: .distantFuture) { services.mapSnapshot(in: context) }
        _ = player.step(elapsed: 5)
        player.stop()
        services.recordMindReplayed(steps: 100, durationMilliseconds: 10_000, stepP95Milliseconds: 3, finished: true, nodes: frame.nodes.count)
        services.recordMindEntryOpened()

        let contents = file.contents()
        #expect(contents.contains("ai.keySaved"))
        #expect(contents.contains("pages.transcription.completed"))
        #expect(contents.contains("insights.completed"))
        #expect(contents.contains("insights.failed"))
        #expect(contents.contains("insights.skipped"))
        #expect(contents.contains("looseEnds.written"))
        #expect(contents.contains("looseEnds.faded"))
        for event in ["graph.indexed", "graph.entityEdited", "graph.hidden", "graph.resurfacingMuted",
                      "graph.suggestionDismissed",
                      "graph.merged", "graph.unmerged", "graph.repointed", "graph.rendered",
                      "mind.reviewAnswered", "mind.focused", "mind.filtersChanged",
                      "mind.lensChanged", "mind.replayed", "mind.entryOpened",
                      "graph.renameRewrote", "graph.contactLinked", "graph.contactUnlinked",
                      "graph.placeLinked", "graph.placeUnlinked", "graph.contactAccess"] {
            #expect(contents.contains(event), "\(event) was never exercised")
        }
        #expect(contents.contains("title.failed"))
        #expect(contents.contains("settings.changed"))
        #expect(contents.contains(sentinel) == false)
    }
}

// Ask: the question, the entries it reads, their titles, an entity's name, and the answer are all
// the sentinel. Success, failure, and a journal with nothing to go on each write their event.
@MainActor
struct AskDiagnosticsPrivacyTests {
    private static let sentinel = DiagnosticsPrivacyTests.sentinel

    @Test func askNeverLogsTheQuestionTheEntriesOrTheAnswer() async throws {
        let file = DiagnosticsFile()
        let log = DiagnosticsLog(fileURL: file.url)
        let sentinel = Self.sentinel
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext

        let generator = FakeTextGenerator()
        // The real index store, so the build and the retrieval events are exercised rather than
        // stepped around. Ask takes no PromptVoice: it addresses the author rather than writing as
        // them, so the owner's name never reaches it in the first place.
        let ask = AskService(
            resolve: { .success(AskProvider(generator: generator, model: "m", label: "openai:m", kind: .openAI)) },
            index: AskIndexStore(diagnostics: log),
            revisions: { .init(saver: JournalSaves.revision, graph: 0, stamped: JournalSaves.revision) },
            store: AskStore(save: { try $0.save() }),
            diagnostics: log
        )

        // Nothing in the journal yet: the question still must not be logged.
        await ask.send("What about \(sentinel)?", in: context)
        #expect(ask.turns.last?.failureRaw == AskFailureText.noEntries)

        let entry = Entry(text: "Dear diary, \(sentinel)")
        entry.title = "Title \(sentinel)"
        context.insert(entry)
        let insights = EntryInsights()
        insights.tags = ["Tag \(sentinel)"]
        insights.areasRaw = [LifeArea.work.rawValue]
        insights.entry = entry
        context.insert(insights)
        let entity = Entity(name: "Name \(sentinel)", key: "name", kind: .person)
        entity.bio = "Bio \(sentinel)"
        context.insert(entity)
        let link = EntityLink(surface: "Surface \(sentinel)", kind: .person)
        context.insert(link)
        link.entityID = entity.id
        link.entryID = entry.id
        let looseEnd = LooseEnd(text: "Loose end \(sentinel)", sourceEntryID: entry.id, sourceEntryDate: .now, entityIDs: [entity.id])
        context.insert(looseEnd)
        try context.save()

        ask.newConversation()
        generator.results = [
            .success(#"{"answer":"Answer \#(sentinel)","citations":["E1"]}"#),
            .failure(AIError.badRequest(code: "invalid_value")),
        ]
        await ask.send("Tell me about \(sentinel)", in: context)
        #expect(ask.turns.last?.text.contains(sentinel) == true)
        await ask.send("And \(sentinel) since?", in: context)
        #expect(ask.turns.last?.failureRaw == "ai.badRequest")

        // An aggregate question, so the rollup path and its month counts are logged too.
        ask.newConversation()
        generator.results = [.success(#"{"answer":"Often \#(sentinel)","citations":["E1"]}"#)]
        await ask.send("How often do I write about \(sentinel)?", in: context)

        // And the search panel, which reads the same index.
        let results = JournalSearch.results(for: sentinel, index: ask.index, in: context)
        // Specifically the entries: `isEmpty` is also false when only the entity row matched, and
        // that row comes from MindDirectory without touching AskIndex at all.
        #expect(results.entries.isEmpty == false, "the panel has to have actually searched the index")

        let conversation = try #require(ask.conversations(in: context).first)
        ask.delete(conversation, in: context)

        // The streaming path, where the answer reaches the screen a few characters at a time, and
        // a stopped one, which keeps what arrived and logs an event of its own.
        let streaming = FakeStreamingTextGenerator()
        let streamed = #"{"answer":"Streamed \#(sentinel)","citations":["E1"]}"#
        streaming.deltas = [String(streamed.prefix(20)), String(streamed.dropFirst(20))]
        streaming.finished = streamed
        let streamingAsk = AskService(
            resolve: { .success(AskProvider(generator: streaming, model: "m", label: "openai:m", kind: .openAI)) },
            index: AskIndexStore(diagnostics: log),
            revisions: { .init(saver: JournalSaves.revision, graph: 0, stamped: JournalSaves.revision) },
            store: AskStore(save: { try $0.save() }),
            diagnostics: log
        )
        await streamingAsk.send("Streamed \(sentinel)?", in: context)
        #expect(streamingAsk.turns.last?.citedEntryIDs.isEmpty == false)

        streamingAsk.newConversation()
        streaming.pauseAfter = 1
        let stopping = Task { await streamingAsk.send("Stop \(sentinel)?", in: context) }
        await streaming.waitForDeltas(1)
        streamingAsk.stop()
        streaming.release()
        await stopping.value
        #expect(streamingAsk.turns.last?.wasStopped == true)
        #expect(streamingAsk.turns.last?.text.contains(sentinel) == true, "the partial answer is the sentinel, and it still must not be logged")

        let contents = file.contents()
        for event in ["ask.answered", "ask.stopped", "ask.failed", "ask.conversationDeleted", "ask.indexed", "ask.retrieved"] {
            #expect(contents.contains(event), "\(event) was never exercised")
        }
        #expect(contents.contains(sentinel) == false)
    }
}

// The AI paths that end somewhere other than success: no provider, offline, a result that lands
// after the text changed or the entry restarted, a title held while the editor is open, the
// automatic pass itself, and removing a key. Every entry and answer carries the sentinel.
@MainActor
struct AIEdgePathDiagnosticsPrivacyTests {
    private static let sentinel = DiagnosticsPrivacyTests.sentinel

    @Test func unhappyAIPathsNeverLogTextOrKeys() async throws {
        let file = DiagnosticsFile()
        let log = DiagnosticsLog(fileURL: file.url)
        let sentinel = Self.sentinel
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let presence = EditorPresence()

        let settings = SettingsStore(store: FakeKeyValueStore(), diagnostics: log)
        let accounts = ProviderAccountStore(settings: settings, secrets: FakeSecretStore(), http: FakeHTTPClient(), diagnostics: log)
        let account = try accounts.saveOpenAIKey("sk-\(sentinel)")
        settings.aiEnabled = true
        settings.recordAutomationStartIfNeeded()

        func voiceEntry() throws -> Entry {
            let entry = Entry(source: .voice, text: "Spoken \(sentinel)")
            context.insert(entry)
            try context.save()
            return entry
        }

        // The automatic pass.
        let trigger = AIPassTrigger(settings: settings, presence: presence, titleUsable: { true }, insightsUsable: { true }, diagnostics: log)
        #expect(trigger.fire(for: try voiceEntry(), at: .finished))

        // No provider: insights, titles, and pages each say so and stop.
        let refused: () -> AIJobFailure = { AIJobFailure(raw: "ai.missingKey") }
        let refusedInsights = InsightsCoordinator(
            resolve: { .failure(refused()) }, sections: { AIServices.insightSections(settings) },
            autoApplyCleanedText: { false }, presence: presence, diagnostics: log
        )
        let unanalyzed = try voiceEntry()
        unanalyzed.insightsPending = true
        await refusedInsights.processQueue(context: context)
        unanalyzed.insightsPending = false

        let refusedTitles = TitleCoordinator(resolve: { .failure(refused()) }, presence: presence, diagnostics: log)
        let untitled = try voiceEntry()
        untitled.titlePending = true
        await refusedTitles.processQueue(context: context)
        untitled.titlePending = false

        let photo = Entry(source: .photo, text: "")
        photo.pagesConfirmed = true
        photo.awaitingText = true
        context.insert(photo)
        let page = EntryPage(index: 0, imageData: Data([1, 2, 3]), thumbnailData: Data([1]), pixelWidth: 10, pixelHeight: 10, origin: .camera)
        context.insert(page)
        page.entry = photo
        try context.save()
        await PageTranscriptionCoordinator(
            resolve: { .failure(refused()) }, diagnostics: log,
            beginBackgroundTask: { _ in {} }, prepareUpload: { $0 }
        ).processQueue(context: context)

        // Offline pages: one ai.offline, and the page's failure.
        await PageTranscriptionCoordinator(
            resolve: { .success(.init(transcriber: OfflinePageTranscriber(), label: "openai:test")) }, diagnostics: log,
            beginBackgroundTask: { _ in {} }, prepareUpload: { $0 }
        ).processQueue(context: context)
        photo.awaitingText = false
        try context.save()

        // Insights that land after the entry changed underneath them: edited text is stale, a
        // restarted entry is discarded.
        let generator = FakeTextGenerator()
        generator.suspends = true
        let insights = InsightsCoordinator(
            resolve: { .success(.init(generator: generator, model: "m", label: "openai:m")) },
            sections: { AIServices.insightSections(settings) },
            autoApplyCleanedText: { false }, presence: presence, diagnostics: log
        )
        let answer = #"{"summary":"About \#(sentinel)","primaryMood":"calm","lifeAreas":["work"],"tags":["\#(sentinel)"],"mentions":[{"name":"\#(sentinel)","kind":"person"}],"looseEnds":[]}"#
        for change in [{ (entry: Entry) in entry.text = "Edited \(sentinel)" }, { (entry: Entry) in entry.contentRevision += 1 }] {
            let entry = try voiceEntry()
            entry.insightsPending = true
            try context.save()
            let run = Task { await insights.processQueue(context: context) }
            await generator.waitForRequest(number: generator.requests.count + 1)
            change(entry)
            generator.answer(.success(answer))
            await run.value
            entry.insightsPending = false
        }

        // Titles that land while the editor is open are held; after a restart they are discarded.
        let titles = TitleCoordinator(
            resolve: { .success(.init(generator: generator, model: "m", label: "openai:m")) },
            presence: presence, diagnostics: log
        )
        for opensEditor in [true, false] {
            let entry = try voiceEntry()
            entry.titlePending = true
            try context.save()
            let run = Task { await titles.processQueue(context: context) }
            await generator.waitForRequest(number: generator.requests.count + 1)
            if opensEditor { presence.open(entry.id) } else { entry.contentRevision += 1 }
            generator.answer(.success("Title \(sentinel)"))
            await run.value
            presence.close(entry.id)
        }

        try accounts.remove(account)

        let contents = file.contents()
        for event in ["ai.pass", "insights.unavailable", "title.unavailable", "pages.transcription.unavailable",
                      "ai.offline", "pages.transcription.failed", "insights.stale", "insights.discarded",
                      "title.held", "title.discarded", "ai.keyRemoved"] {
            #expect(contents.contains(event), "\(event) was never exercised")
        }
        #expect(contents.contains(sentinel) == false)
    }
}

private final class OfflinePageTranscriber: PageTranscriber {
    nonisolated func transcribe(_ request: PageRequest) async throws -> PageResult {
        throw AIError.offline(.notConnectedToInternet)
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
