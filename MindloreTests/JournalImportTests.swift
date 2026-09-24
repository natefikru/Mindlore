import Foundation
import SwiftData
import Testing
@testable import Mindlore

// Importing a Mindlore export (owner, 2026-09-23). The main test is the round trip: a journal
// with every kind of record, exported, imported into an empty store, and exported again, must
// write the same records. The rest are the rules for a journal that already has some of it.
@MainActor
struct JournalImportTests {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ImportTests-\(UUID().uuidString)", isDirectory: true)
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    init() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func date(_ day: Int, hour: Int = 12) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }

    // Everything a restore has to bring back, in one journal.
    private struct Fixture {
        let voice: Entry
        let photo: Entry
        let maya: Entity
        let sam: Entity
    }

    @discardableResult
    private func fixture(in context: ModelContext) throws -> Fixture {
        let maya = Entity(name: "Maya", key: "maya", kind: .person, createdAt: date(1))
        maya.aliases = ["M"]
        maya.bio = "A friend from work."
        maya.bioWasGenerated = true
        maya.bioDraftedAt = date(2)
        maya.bioModelUsed = "openai:gpt"
        maya.resurfacingMuted = true
        maya.confirmedByUser = true
        let sam = Entity(name: "Sam", key: "sam", kind: .person, createdAt: date(1, hour: 13))
        maya.notSameAs = [sam.id]
        let loser = Entity(name: "M", key: "m", kind: .person, createdAt: date(1, hour: 14))
        loser.mergedIntoID = maya.id
        loser.mergedAt = date(3)
        maya.contributedAliases = ["M"]
        let cafe = Entity(name: "The Corner Cafe", key: "the corner cafe", kind: .place, createdAt: date(1, hour: 15))
        cafe.placeIdentifier = "place-1"
        cafe.placeLatitude = 51.5
        cafe.placeLongitude = -0.1
        cafe.hidden = true
        let river = Entity(name: "river", key: "river", kind: .tag, createdAt: date(1, hour: 16))
        for entity in [maya, sam, loser, cafe, river] { context.insert(entity) }

        let voice = Entry(createdAt: date(10), source: .voice, text: "Coffee with Maya by the river.", audioData: TranscriptionHarness.m4aBytes, audioDuration: 12.5)
        context.insert(voice)
        voice.title = "Coffee with Maya"
        voice.titleWasGenerated = true
        voice.formattingRaw = #"{"blocks":[]}"#
        voice.textWasGenerated = true
        voice.textGeneratedBy = "openai:whisper"
        voice.originalText = "um coffee with maya by the river"
        voice.cleanupAppliedHash = "abc"
        voice.entryDate = date(9)
        voice.entryDateIsDayOnly = true
        voice.kind = .note
        voice.automaticAIPassUsed = true
        let insights = EntryInsights(generatedAt: date(10, hour: 13), modelUsed: "openai:gpt", sourceTextHash: "hash")
        context.insert(insights)
        insights.summary = "Coffee by the river."
        insights.setMoods(primary: .calm, secondary: [.grateful], editedByUser: true)
        insights.areasRaw = ["friends"]
        insights.tags = ["river"]
        insights.mentions = [Mention(name: "Maya", kindRaw: "person")]
        insights.sectionsData = Data(#"[{"topic":"coffee"}]"#.utf8)
        insights.cleanedText = "Coffee with Maya by the river."
        insights.entry = voice
        let aiLink = EntityLink(surface: "Maya", kind: .person)
        context.insert(aiLink)
        aiLink.attach(to: voice, entity: maya)
        aiLink.unsureAmong = [maya.id, sam.id]
        aiLink.originalEntityID = loser.id
        let userLink = EntityLink(surface: "the cafe", kind: .place, source: .user)
        context.insert(userLink)
        userLink.attach(to: voice, entity: cafe)
        userLink.writtenSurface = "the cafe"
        let tagLink = EntityLink(surface: "river", kind: .tag)
        context.insert(tagLink)
        tagLink.attach(to: voice, entity: river)

        let photo = Entry(createdAt: date(12), source: .photo, text: "A poem about the river.")
        context.insert(photo)
        photo.pagesConfirmed = true
        photo.kind = .creative
        photo.creativeSetByUser = true
        photo.automaticAIPassUsed = true
        for index in 0..<2 {
            let page = EntryPage(index: index, imageData: Data([UInt8(index), 9, 9]), thumbnailData: Data([7]), pixelWidth: 100, pixelHeight: 200, origin: .library, addedAt: date(12))
            context.insert(page)
            page.transcribedText = "page \(index)"
            page.writtenDate = date(11)
            page.entry = photo
        }

        let draft = Entry(createdAt: date(13), text: "Half a thou")
        draft.isDraft = true
        context.insert(draft)

        let end = LooseEnd(text: "call the landlord", sourceEntryID: voice.id, sourceEntryDate: date(9), entityIDs: [maya.id], dueDate: date(20))
        context.insert(end)
        end.status = .resolved
        end.resolvedByEntryID = photo.id
        end.statusChangedAt = date(12)
        end.lastMentionedAt = date(12)
        end.promptedAt = date(11)
        end.userTouched = true

        let conversation = AskConversation(createdAt: date(14), title: "How was Maya?")
        conversation.handleMapData = Data(#"{"E1":"x"}"#.utf8)
        context.insert(conversation)
        context.insert(AskMessage(conversationID: conversation.id, index: 0, role: .user, text: "How was Maya?"))
        context.insert(AskMessage(conversationID: conversation.id, index: 1, role: .assistant, text: "Calm.", citedEntryIDs: [voice.id], providerLabel: "openai", sentEntryIDs: [voice.id], sentCharacters: 30, matchedCount: 1))

        context.insert(ReflectSummary(kind: .week, periodStart: date(7), generatedAt: date(14), items: [], sourceFingerprint: "fp"))
        try context.saveStampingEntries(except: [voice.persistentModelID, photo.persistentModelID, draft.persistentModelID])
        return Fixture(voice: voice, photo: photo, maya: maya, sam: sam)
    }

    private func export(_ context: ModelContext, to name: String) throws -> URL {
        let parent = folder.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        return try JournalExport.write(from: context, into: parent, now: date(22), calendar: utc, diagnostics: .disabled).folder
    }

    private func records(at exported: URL) throws -> JournalRecords {
        try JournalImport.read(folder: exported).records
    }

    // MARK: - The round trip

    @Test func anExportImportedIntoAnEmptyJournalWritesTheSameRecordsBack() async throws {
        let source = try ModelContainerFactory.make(.inMemory)
        try fixture(in: source.mainContext)
        let first = try export(source.mainContext, to: "first")

        let target = try ModelContainerFactory.make(.inMemory)
        let summary = try await JournalImport.apply(try JournalImport.read(folder: first), into: target.mainContext, diagnostics: .disabled)
        let second = try export(target.mainContext, to: "second")

        #expect(summary.entries == 3 && summary.skippedEntries == 0 && summary.missingMedia == 0)
        let before = try records(at: first)
        let after = try records(at: second)
        #expect(after.entries == before.entries)
        #expect(after.entities == before.entities)
        #expect(after.looseEnds == before.looseEnds)
        #expect(after.conversations == before.conversations)
        #expect(after.messages == before.messages)
        #expect(after.reflectSummaries == before.reflectSummaries)
        // The media itself, not just its name.
        let audio = try #require(before.entries.first { $0.audioFile != nil }?.audioFile)
        #expect(try Data(contentsOf: second.appendingPathComponent(audio)) == TranscriptionHarness.m4aBytes)
    }

    // The relationships nothing reads today still have to agree with the ids, or a cascade
    // delete misses them.
    @Test func relationshipsAgreeWithTheIds() async throws {
        let source = try ModelContainerFactory.make(.inMemory)
        let fixture = try fixture(in: source.mainContext)
        let exported = try export(source.mainContext, to: "out")
        let target = try ModelContainerFactory.make(.inMemory)
        try await JournalImport.apply(try JournalImport.read(folder: exported), into: target.mainContext, diagnostics: .disabled)

        let entries = try target.mainContext.fetch(FetchDescriptor<Entry>())
        let voice = try #require(entries.first { $0.id == fixture.voice.id })
        let photo = try #require(entries.first { $0.id == fixture.photo.id })
        #expect(voice.insights?.summary == "Coffee by the river.")
        #expect(photo.sortedPages.map(\.transcribedText) == ["page 0", "page 1"])
        #expect(photo.sortedPages.first?.imageData == Data([0, 9, 9]))
        let links = try target.mainContext.fetch(FetchDescriptor<EntityLink>())
        #expect(links.count == 3)
        #expect(links.allSatisfy { $0.entry?.id == $0.entryID && $0.linkedEntity?.id == $0.entityID })
        let maya = try #require(try target.mainContext.fetch(FetchDescriptor<Entity>()).first { $0.id == fixture.maya.id })
        #expect(maya.linkCount == 1, "recount fills in what the export leaves out")
    }

    // Imported entries were analysed where they came from. Nothing may pick them up again.
    @Test func nothingIsQueuedReindexedOrDraftedAfterwards() async throws {
        let source = try ModelContainerFactory.make(.inMemory)
        let fixture = try fixture(in: source.mainContext)
        let exported = try export(source.mainContext, to: "out")
        let target = try ModelContainerFactory.make(.inMemory)
        let context = target.mainContext
        try await JournalImport.apply(try JournalImport.read(folder: exported), into: context, diagnostics: .disabled)

        // Even with automation switched on before any of these were written.
        let entries = try context.fetch(FetchDescriptor<Entry>())
        #expect(entries.allSatisfy { !AIPassTrigger.isEligible($0, automationStartedAt: .distantPast) && !$0.insightsPending && !$0.titlePending })
        #expect(GraphIndexer(diagnostics: .disabled).sweep(in: context) == 0, "the restored links stand")
        let maya = try #require(try context.fetch(FetchDescriptor<Entity>()).first { $0.id == fixture.maya.id })
        #expect(maya.bio != nil && maya.bioDraftedAt != nil, "a restored bio is not due for a draft")
    }

    // MARK: - Into a journal that already has some of it

    @Test func importingTwiceAddsNothingTheSecondTime() async throws {
        let source = try ModelContainerFactory.make(.inMemory)
        try fixture(in: source.mainContext)
        let exported = try export(source.mainContext, to: "out")
        let target = try ModelContainerFactory.make(.inMemory)
        let context = target.mainContext
        let prepared = try JournalImport.read(folder: exported)
        try await JournalImport.apply(prepared, into: context, diagnostics: .disabled)
        let counts = try (context.fetchCount(FetchDescriptor<Entry>()), context.fetchCount(FetchDescriptor<Entity>()), context.fetchCount(FetchDescriptor<EntityLink>()), context.fetchCount(FetchDescriptor<LooseEnd>()), context.fetchCount(FetchDescriptor<AskMessage>()), context.fetchCount(FetchDescriptor<ReflectSummary>()))

        let second = try await JournalImport.apply(prepared, into: context, diagnostics: .disabled)

        #expect(second.entries == 0 && second.skippedEntries == 3 && second.names == 0)
        let again = try (context.fetchCount(FetchDescriptor<Entry>()), context.fetchCount(FetchDescriptor<Entity>()), context.fetchCount(FetchDescriptor<EntityLink>()), context.fetchCount(FetchDescriptor<LooseEnd>()), context.fetchCount(FetchDescriptor<AskMessage>()), context.fetchCount(FetchDescriptor<ReflectSummary>()))
        #expect(again == counts)
    }

    // The journal's copy may be newer (it syncs). It stays whole: its text, its insights, and
    // none of the export's links grafted onto it.
    @Test func anEntryAlreadyHereKeepsItsOwnCopyAndNothingIsGraftedOn() async throws {
        let source = try ModelContainerFactory.make(.inMemory)
        let fixture = try fixture(in: source.mainContext)
        let exported = try export(source.mainContext, to: "out")

        let target = try ModelContainerFactory.make(.inMemory)
        let context = target.mainContext
        let mine = Entry(id: fixture.voice.id, createdAt: date(10), source: .voice, text: "My newer words.")
        context.insert(mine)
        try context.save()

        let summary = try await JournalImport.apply(try JournalImport.read(folder: exported), into: context, diagnostics: .disabled)

        #expect(summary.skippedEntries == 1)
        let copies = try context.fetch(FetchDescriptor<Entry>()).filter { $0.id == fixture.voice.id }
        #expect(copies.count == 1 && copies.first?.text == "My newer words.")
        #expect(copies.first?.insights == nil)
        let linked = try context.fetch(FetchDescriptor<EntityLink>()).filter { $0.entryID == fixture.voice.id }
        #expect(linked.isEmpty)
        #expect(try context.fetch(FetchDescriptor<LooseEnd>()).isEmpty, "the loose end it raised goes with it")
    }

    // A journal started fresh on a new phone already has its own Maya. The import uses her, and
    // every id that named the imported Maya names her instead.
    @Test func aNameTheJournalAlreadyHasIsReusedAndEveryReferenceFollows() async throws {
        let source = try ModelContainerFactory.make(.inMemory)
        let fixture = try fixture(in: source.mainContext)
        let exported = try export(source.mainContext, to: "out")

        let target = try ModelContainerFactory.make(.inMemory)
        let context = target.mainContext
        let local = Entity(name: "Maya", key: "maya", kind: .person)
        context.insert(local)
        try context.save()

        let summary = try await JournalImport.apply(try JournalImport.read(folder: exported), into: context, diagnostics: .disabled)

        #expect(summary.reusedNames == 1)
        let entities = try context.fetch(FetchDescriptor<Entity>())
        #expect(!entities.contains { $0.id == fixture.maya.id })
        #expect(entities.filter { $0.key == "maya" }.count == 1)
        #expect(local.bio == "A friend from work.", "filled in where the journal's own had none")
        let link = try #require(try context.fetch(FetchDescriptor<EntityLink>()).first { $0.surface == "Maya" })
        #expect(link.entityID == local.id && link.linkedEntity?.id == local.id)
        #expect(link.unsureAmong == [local.id, fixture.sam.id])
        let loser = try #require(entities.first { $0.key == "m" })
        #expect(loser.mergedIntoID == local.id)
        #expect(try context.fetch(FetchDescriptor<LooseEnd>()).first?.entityIDs == [local.id])
    }

    // MARK: - What it refuses

    @Test func anOlderExportOrSomethingElseIsRefused() throws {
        let older = folder.appendingPathComponent("older", isDirectory: true)
        try FileManager.default.createDirectory(at: older, withIntermediateDirectories: true)
        try Data(#"{"exportedAt":"2026-09-01T00:00:00Z","entries":[],"names":[],"looseEnds":[]}"#.utf8).write(to: older.appendingPathComponent("journal.json"))
        #expect(throws: JournalImport.Failure.olderExport) { try JournalImport.read(folder: older) }

        let empty = folder.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        #expect(throws: JournalImport.Failure.notAnExport) { try JournalImport.read(folder: empty) }

        try Data("not json".utf8).write(to: empty.appendingPathComponent("journal.json"))
        #expect(throws: JournalImport.Failure.notAnExport) { try JournalImport.read(folder: empty) }
    }

    // A missing recording costs that recording, not the entry.
    @Test func missingMediaSkipsOnlyTheFile() async throws {
        let source = try ModelContainerFactory.make(.inMemory)
        let fixture = try fixture(in: source.mainContext)
        let exported = try export(source.mainContext, to: "out")
        for file in try FileManager.default.contentsOfDirectory(atPath: exported.appendingPathComponent("media").path) where file.hasSuffix(".m4a") {
            try FileManager.default.removeItem(at: exported.appendingPathComponent("media").appendingPathComponent(file))
        }
        let target = try ModelContainerFactory.make(.inMemory)

        let summary = try await JournalImport.apply(try JournalImport.read(folder: exported), into: target.mainContext, diagnostics: .disabled)

        #expect(summary.missingMedia == 1 && summary.entries == 3)
        let voice = try #require(try target.mainContext.fetch(FetchDescriptor<Entry>()).first { $0.id == fixture.voice.id })
        #expect(voice.audioData == nil && voice.text == "Coffee with Maya by the river.")
    }

    // A hand-edited journal.json can't point the importer at a file outside the folder.
    @Test func aMediaPathCannotLeaveTheFolder() async throws {
        let source = try ModelContainerFactory.make(.inMemory)
        let fixture = try fixture(in: source.mainContext)
        let exported = try export(source.mainContext, to: "out")
        let secret = folder.appendingPathComponent("secret.m4a")
        try Data([1, 2, 3]).write(to: secret)
        var prepared = try JournalImport.read(folder: exported)
        var records = prepared.records
        let index = try #require(records.entries.firstIndex { $0.id == fixture.voice.id })
        records.entries[index].audioFile = "../secret.m4a"
        prepared = JournalImport.Prepared(folder: exported, records: records)
        let target = try ModelContainerFactory.make(.inMemory)

        let summary = try await JournalImport.apply(prepared, into: target.mainContext, diagnostics: .disabled)

        #expect(summary.missingMedia == 1)
        #expect(try target.mainContext.fetch(FetchDescriptor<Entry>()).first { $0.id == fixture.voice.id }?.audioData == nil)
    }

    @Test func thePreviewCountsWhatIsNewAndWhatIsAlreadyHere() throws {
        let source = try ModelContainerFactory.make(.inMemory)
        let fixture = try fixture(in: source.mainContext)
        let exported = try export(source.mainContext, to: "out")
        let target = try ModelContainerFactory.make(.inMemory)
        target.mainContext.insert(Entry(id: fixture.photo.id, text: "mine"))
        try target.mainContext.save()

        let preview = JournalImport.preview(try JournalImport.read(folder: exported), in: target.mainContext)

        #expect(preview == .init(newEntries: 2, existingEntries: 1, newNames: 3, newConversations: 1))
    }

    @Test func theLogCarriesCountsOnly() async throws {
        let file = URL.temporaryDirectory.appending(path: "import-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        let source = try ModelContainerFactory.make(.inMemory)
        try fixture(in: source.mainContext)
        let exported = try export(source.mainContext, to: "out")
        let target = try ModelContainerFactory.make(.inMemory)

        try await JournalImport.apply(try JournalImport.read(folder: exported), into: target.mainContext, diagnostics: DiagnosticsLog(fileURL: file))

        let written = try String(contentsOf: file, encoding: .utf8)
        #expect(written.contains("journal.imported"))
        for sentinel in ["Maya", "river", "landlord", "Coffee"] { #expect(!written.contains(sentinel), "\(sentinel)") }
    }
}

// Every stored property of every model is either carried by its record or listed here as left
// out on purpose. A property added to a model fails this until someone decides which.
@MainActor
struct JournalRecordsCoverageTests {
    private static let leftOut: [String: Set<String>] = [
        // Job bookkeeping the importer sets, and the graph's own staleness stamp.
        "Entry": ["contentRevision", "pageRequestCount", "textAttempts", "textFailureRaw", "textChunkPlan", "textChunkTexts",
                  "automaticAIPassUsed", "titlePending", "titleAttempts", "titleFailureRaw", "insightsPending",
                  "insightsAttempts", "insightsFailureRaw", "graphIndexedAt"],
        // Derived by GraphIndexer.recount.
        "Entity": ["linkCount", "firstLinkedAt", "lastLinkedAt"],
        // A link travels inside its entry.
        "EntityLink": ["entryID"],
    ]
    // Record fields named differently from the property they carry.
    private static let renamed = ["audioFile": "audioData", "imageFile": "imageData"]

    private func carried(_ record: Any) -> Set<String> {
        Set(Mirror(reflecting: record).children.compactMap(\.label).map { Self.renamed[$0] ?? $0 })
    }

    @Test func everyStoredPropertyIsCarriedOrLeftOutOnPurpose() throws {
        let records: [String: Any] = [
            "Entry": EntryRecord(Entry(), audioFile: nil, pages: [], links: []),
            "EntryPage": PageRecord(EntryPage(index: 0, imageData: nil, thumbnailData: nil, pixelWidth: 0, pixelHeight: 0, origin: .camera), imageFile: nil),
            "EntryInsights": InsightsRecord(EntryInsights()),
            "EntityLink": LinkRecord(EntityLink(surface: "", kind: .other)),
            "Entity": EntityRecord(Entity(name: "", key: "", kind: .other)),
            "LooseEnd": LooseEndRecord(LooseEnd(text: "", sourceEntryID: UUID(), sourceEntryDate: .now)),
            "AskConversation": ConversationRecord(AskConversation()),
            "AskMessage": MessageRecord(AskMessage(conversationID: UUID(), index: 0, role: .user, text: "")),
            "ReflectSummary": ReflectSummaryRecord(ReflectSummary(kind: .week, periodStart: .now, generatedAt: .now, items: [])),
        ]
        for entity in ModelContainerFactory.schema.entities {
            let record = try #require(records[entity.name], "\(entity.name) has no record type")
            let stored = Set(entity.attributes.map(\.name))
            let expected = stored.subtracting(Self.leftOut[entity.name] ?? [])
            let missing = expected.subtracting(carried(record))
            #expect(missing.isEmpty, "\(entity.name) doesn't carry \(missing.sorted())")
        }
    }
}
