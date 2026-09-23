import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Mindlore

@MainActor
final class LockHarness {
    var enabled = true
    var covered: [Bool] = []
    var answers: [Bool] = []
    private(set) var asked = 0
    lazy var lock = AppLock(
        isEnabled: { [unowned self] in self.enabled },
        authenticate: { [unowned self] _ in
            self.asked += 1
            return self.answers.isEmpty ? false : self.answers.removeFirst()
        },
        cover: { [unowned self] in self.covered.append($0) },
        diagnostics: .disabled
    )
}

@MainActor
struct AppLockTests {
    @Test func offMeansNothingEverCovers() async {
        let harness = LockHarness()
        harness.enabled = false
        harness.lock.lockAtLaunch()
        harness.lock.sceneChanged(to: .background)
        harness.lock.sceneChanged(to: .active)

        #expect(!harness.lock.isLocked)
        #expect(harness.covered.allSatisfy { !$0 })
        #expect(harness.asked == 0)
    }

    @Test func leavingLocksAndComingBackAsks() async {
        let harness = LockHarness()
        harness.answers = [true]
        harness.lock.sceneChanged(to: .background)
        #expect(harness.lock.isLocked)
        #expect(harness.covered.last == true)

        await harness.lock.unlock()
        #expect(!harness.lock.isLocked)
        #expect(harness.covered.last == false)
        #expect(harness.asked == 1)
    }

    // A refused Face ID keeps the cover and doesn't ask again on its own, or it would loop.
    @Test func aRefusalKeepsTheCoverAndWaitsForTheButton() async {
        let harness = LockHarness()
        harness.answers = [false]
        harness.lock.lockAtLaunch()
        await harness.lock.unlock()

        #expect(harness.lock.isLocked)
        #expect(harness.lock.lastAttemptFailed)
        harness.lock.sceneChanged(to: .active)
        #expect(harness.asked == 1, "coming back active after a refusal doesn't re-prompt by itself")
    }

    // The app switcher's snapshot is taken while inactive; the cover must already be up.
    @Test func inactiveCoversWithoutLocking() {
        let harness = LockHarness()
        harness.lock.sceneChanged(to: .inactive)
        #expect(harness.covered.last == true)
        #expect(!harness.lock.isLocked)
        harness.lock.sceneChanged(to: .active)
        #expect(harness.covered.last == false)
    }

    @Test func turningItOffLiftsTheCover() {
        let harness = LockHarness()
        harness.lock.lockAtLaunch()
        harness.enabled = false
        harness.lock.disabled()
        #expect(!harness.lock.isLocked)
        #expect(harness.covered.last == false)
    }
}

@MainActor
struct JournalExportTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ExportTests-\(UUID().uuidString)", isDirectory: true)
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    init() throws {
        container = try ModelContainerFactory.make(.inMemory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func date(_ day: Int) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 9, day: day, hour: 12))!
    }

    @Test func everyEntryBecomesAFileAndTheJSONCarriesTheRest() throws {
        let entry = Entry(createdAt: date(21), source: .voice, text: "Coffee with Maya by the river.", audioData: TranscriptionHarness.m4aBytes)
        entry.title = "Coffee with Maya"
        context.insert(entry)
        let insights = EntryInsights()
        insights.primaryMoodRaw = "calm"
        insights.tags = ["river"]
        insights.areasRaw = ["friends"]
        context.insert(insights)
        insights.entry = entry
        let maya = Entity(name: "Maya", key: "maya", kind: .person)
        context.insert(maya)
        let link = EntityLink(surface: "Maya", kind: .person)
        link.entityID = maya.id
        link.entryID = entry.id
        context.insert(link)
        // Same day and title: the second file must not overwrite the first.
        let twin = Entry(createdAt: date(21).addingTimeInterval(3_600), text: "Second one.")
        twin.title = "Coffee with Maya"
        twin.isDraft = true
        context.insert(twin)
        context.insert(LooseEnd(text: "call the landlord", sourceEntryID: entry.id, sourceEntryDate: date(21), entityIDs: [maya.id]))
        try context.save()

        let summary = try JournalExport.write(from: context, into: folder, now: date(22), calendar: utc)

        #expect(summary.folder.lastPathComponent == "Mindlore Export 2026-09-22")
        #expect(summary.entries == 2)
        #expect(summary.mediaFiles == 1)
        let files = try FileManager.default.contentsOfDirectory(atPath: summary.folder.appendingPathComponent("entries").path).sorted()
        #expect(files == ["2026-09-21 Coffee with Maya 2.md", "2026-09-21 Coffee with Maya.md"])

        let markdown = try String(contentsOf: summary.folder.appendingPathComponent("entries/2026-09-21 Coffee with Maya.md"), encoding: .utf8)
        #expect(markdown.contains("title: \"Coffee with Maya\""))
        #expect(markdown.contains("mood: calm"))
        #expect(markdown.contains("names: [\"Maya\"]"))
        #expect(markdown.contains("audio: ../media/\(entry.id.uuidString).m4a"))
        #expect(markdown.hasSuffix("Coffee with Maya by the river.\n"))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(JournalExport.Document.self, from: Data(contentsOf: summary.folder.appendingPathComponent("journal.json")))
        #expect(document.entries.map(\.isDraft) == [false, true])
        #expect(document.entries.first?.tags == ["river"])
        #expect(document.names.map(\.name) == ["Maya"])
        #expect(document.looseEnds.first?.names == ["Maya"])
        #expect(FileManager.default.fileExists(atPath: summary.folder.appendingPathComponent("media/\(entry.id.uuidString).m4a").path))
    }

    @Test func titlesCantEscapeTheFolderOrBreakTheFrontMatter() {
        #expect(JournalExport.yamlString("a \"quoted\" \\ title") == #""a \"quoted\" \\ title""#)
        let entry = JournalExport.ExportedEntry(
            id: UUID(), date: date(1), createdAt: date(1), updatedAt: date(1), source: "typed",
            title: "", text: "Just text.", isDraft: false, summary: nil, mood: nil, otherMoods: [],
            areas: [], tags: [], names: [], file: "entries/x.md", audio: nil, pages: []
        )
        let markdown = JournalExport.markdown(for: entry, calendar: utc)
        #expect(!markdown.contains("title:"))
        #expect(!markdown.contains("# "))
    }

    // The Markdown file shows the layout; the JSON keeps the plain words and the formatting apart.
    @Test func exportWritesFormattingAsMarkdownAndKeepsItInTheJSON() throws {
        let entry = Entry(createdAt: date(2), text: "Plan\nCall mum\nBuy milk")
        entry.formatting = EntryFormatting(
            paragraphs: [.init(index: 0, block: .heading2), .init(index: 1, block: .check), .init(index: 2, block: .checked)],
            spans: [.init(location: 5, length: 4, bold: true)]
        )
        context.insert(entry)
        try context.save()

        let summary = try JournalExport.write(from: context, into: folder, now: date(4), calendar: utc)
        let entries = summary.folder.appendingPathComponent("entries")
        let file = try #require(FileManager.default.contentsOfDirectory(atPath: entries.path).first)
        let markdown = try String(contentsOf: entries.appendingPathComponent(file), encoding: .utf8)
        #expect(markdown.contains("## Plan\n- [ ] **Call** mum\n- [x] Buy milk"))

        let json = try String(contentsOf: summary.folder.appendingPathComponent("journal.json"), encoding: .utf8)
        #expect(json.contains("Plan\\nCall mum\\nBuy milk"))
        #expect(json.contains("\"formatting\""))
    }

    @Test func slashesInATitleStayInOneFile() throws {
        let entry = Entry(createdAt: date(3), text: "x")
        entry.title = "../../etc/passwd"
        context.insert(entry)
        try context.save()

        let summary = try JournalExport.write(from: context, into: folder, now: date(4), calendar: utc)
        let files = try FileManager.default.contentsOfDirectory(atPath: summary.folder.appendingPathComponent("entries").path)
        #expect(files.count == 1)
        #expect(files.first?.contains("/") == false)
    }
}

@MainActor
struct JournalWipeTests {
    @Test func everythingInTheJournalGoesAndSettingsStay() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let entry = Entry(text: "hello")
        context.insert(entry)
        let insights = EntryInsights()
        context.insert(insights)
        insights.entry = entry
        let entity = Entity(name: "Maya", key: "maya", kind: .person)
        context.insert(entity)
        let link = EntityLink(surface: "Maya", kind: .person)
        link.entityID = entity.id
        link.entryID = entry.id
        context.insert(link)
        context.insert(LooseEnd(text: "call", sourceEntryID: entry.id, sourceEntryDate: .now))
        context.insert(AskConversation(title: "q"))
        context.insert(ReflectSummary(kind: .week, periodStart: .now, generatedAt: .now, items: []))
        try context.save()
        let settings = SettingsStore(store: FakeKeyValueStore(), diagnostics: .disabled)
        settings.keepAudioAfterTranscription = false

        let recordings = RecordingsDirectory(root: FileManager.default.temporaryDirectory.appendingPathComponent("WipeTests-\(UUID().uuidString)"))
        try recordings.prepare()
        let finished = recordings.finished.appendingPathComponent("leftover.caf")
        try Data([1, 2, 3]).write(to: finished)

        let deleted = try JournalWipe.deleteEverything(in: context, recordings: recordings)

        #expect(deleted == 1)
        #expect(try context.fetchCount(FetchDescriptor<Entry>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<EntryInsights>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Entity>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<EntityLink>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<LooseEnd>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<AskConversation>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ReflectSummary>()) == 0)
        #expect(!FileManager.default.fileExists(atPath: finished.path))
        #expect(settings.keepAudioAfterTranscription == false)
    }
}

// Export and wipe handle every word in the journal; their log lines carry counts only.
@MainActor
struct TrustDiagnosticsPrivacyTests {
    @Test func exportWipeAndLockNeverLogJournalText() async throws {
        let sentinel = DiagnosticsPrivacyTests.sentinel
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let entry = Entry(text: "Spoken \(sentinel)")
        entry.title = "Title \(sentinel)"
        context.insert(entry)
        let entity = Entity(name: "Name \(sentinel)", key: "name", kind: .person)
        context.insert(entity)
        context.insert(LooseEnd(text: "Thread \(sentinel)", sourceEntryID: entry.id, sourceEntryDate: .now, entityIDs: [entity.id]))
        try context.save()

        let file = URL.temporaryDirectory.appending(path: "trust-\(UUID().uuidString).jsonl")
        let staging = URL.temporaryDirectory.appending(path: "trust-export-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: file)
            try? FileManager.default.removeItem(at: staging)
        }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let log = DiagnosticsLog(fileURL: file)

        let summary = try JournalExport.write(from: context, into: staging, diagnostics: log)
        let exported = try String(contentsOf: summary.folder.appendingPathComponent("journal.json"), encoding: .utf8)
        #expect(exported.contains(sentinel), "the sentinel really went through the export")
        let recordings = RecordingsDirectory(root: staging.appending(path: "Recordings"))
        try JournalWipe.deleteEverything(in: context, recordings: recordings, diagnostics: log)
        let lock = AppLock(isEnabled: { true }, authenticate: { _ in true }, cover: { _ in }, diagnostics: log)
        lock.sceneChanged(to: .background)
        await lock.unlock()

        let written = try String(contentsOf: file, encoding: .utf8)
        for event in ["journal.exported", "journal.wiped", "lock.locked", "lock.unlock"] {
            #expect(written.contains(event), "\(event) was written")
        }
        #expect(!written.contains(sentinel))
    }
}

struct WelcomeRuleTests {
    @Test func onlyANewInstallSeesTheWelcome() {
        #expect(RootView.showsWelcome(seen: false, arguments: [], entries: 0))
        #expect(!RootView.showsWelcome(seen: true, arguments: [], entries: 0), "once is enough")
        #expect(!RootView.showsWelcome(seen: false, arguments: [], entries: 3), "an existing journal skips it")
        #expect(!RootView.showsWelcome(seen: false, arguments: ["-uiTesting"], entries: 0), "UI tests don't see it")
        #expect(RootView.showsWelcome(seen: true, arguments: ["-uiTesting", "-showWelcome"], entries: 5), "unless they ask")
    }
}
