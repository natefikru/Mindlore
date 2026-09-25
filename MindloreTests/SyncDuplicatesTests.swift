import Foundation
import SwiftData
import Testing
@testable import Mindlore

@MainActor
struct SyncDuplicatesTests {
    let container: ModelContainer
    let editor = GraphEditor(diagnostics: .disabled)
    let indexer = GraphIndexer(diagnostics: .disabled)
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try ModelContainerFactory.make(.inMemory)
    }

    private func date(_ day: Double) -> Date { Date(timeIntervalSince1970: 1_750_000_000 + day * 86_400) }

    private func run() throws -> SyncDuplicates.Result {
        try SyncDuplicates.run(in: context, editor: editor, indexer: indexer, diagnostics: .disabled)
    }

    private func entry(_ text: String) throws -> Entry {
        let entry = Entry(createdAt: date(0), text: text)
        context.insert(entry)
        try context.saveStampingEntries()
        return entry
    }

    // The same name written on two phones: two entities, one link each.
    private func sarahTwice(firstCreated: Date, secondCreated: Date) throws -> (a: Entity, b: Entity, entries: [Entry]) {
        let one = try entry("Lunch with Sarah")
        let two = try entry("Sarah called")
        let a = Entity(name: "Sarah", key: "sarah", kind: .person, createdAt: firstCreated)
        let b = Entity(name: "Sarah", key: "sarah", kind: .person, createdAt: secondCreated)
        context.insert(a)
        context.insert(b)
        try context.save()
        for (entry, entity) in [(one, a), (two, b)] {
            let link = EntityLink(surface: "Sarah", kind: .person)
            context.insert(link)
            link.attach(to: entry, entity: entity)
        }
        try context.save()
        indexer.recount(in: context)
        try context.save()
        return (a, b, [one, two])
    }

    // MARK: - Entities

    @Test func twoUntouchedCopiesOfANameBecomeTheOlderOne() throws {
        let (a, b, _) = try sarahTwice(firstCreated: date(2), secondCreated: date(1))

        #expect(try run().entities == 1)
        #expect(a.mergedIntoID == b.id, "the earlier createdAt wins, whichever phone runs it")
        #expect(b.linkCount == 2)
        #expect(!b.confirmedByUser && !a.confirmedByUser, "nobody chose this merge")
        #expect(try run() == SyncDuplicates.Result())
    }

    @Test func aTieOnCreatedAtFallsToTheId() throws {
        let (a, b, _) = try sarahTwice(firstCreated: date(1), secondCreated: date(1))
        let (winner, loser) = a.id.uuidString < b.id.uuidString ? (a, b) : (b, a)

        try run()
        #expect(loser.mergedIntoID == winner.id && winner.mergedIntoID == nil)
    }

    @Test func aThirdCopyArrivingLaterStillMerges() throws {
        let (_, b, _) = try sarahTwice(firstCreated: date(2), secondCreated: date(1))
        try run()

        let third = Entity(name: "Sarah", key: "sarah", kind: .person, createdAt: date(3))
        context.insert(third)
        try context.save()
        let link = EntityLink(surface: "Sarah", kind: .person)
        context.insert(link)
        link.attach(to: try entry("Sarah again"), entity: third)
        try context.save()

        #expect(try run().entities == 1)
        #expect(third.mergedIntoID == b.id)
    }

    @Test func aCopyTouchedByHandIsLeftForTheUser() throws {
        let (a, b, _) = try sarahTwice(firstCreated: date(1), secondCreated: date(2))
        b.bioEditedByUser = true
        try context.save()

        #expect(try run().entities == 0)
        #expect(!a.isMerged && !b.isMerged)
    }

    @Test func differentKindsAreDifferentNames() throws {
        let (a, b, _) = try sarahTwice(firstCreated: date(1), secondCreated: date(2))
        b.kindRaw = EntityKind.place.rawValue
        try context.save()

        #expect(try run().entities == 0)
        #expect(!a.isMerged && !b.isMerged)
    }

    // MARK: - Links and insights

    private func doubledLink() throws -> (Entry, Entity) {
        let written = try entry("Lunch with Maya")
        let maya = Entity(name: "Maya", key: "maya", kind: .person, createdAt: date(1))
        context.insert(maya)
        try context.save()
        for unsure in [[], [UUID()]] {
            let link = EntityLink(surface: "Maya", kind: .person)
            context.insert(link)
            link.attach(to: written, entity: maya)
            link.unsureAmong = unsure
        }
        try context.save()
        return (written, maya)
    }

    @Test func aDoubledLinkKeepsTheRowCarryingMore() throws {
        let (written, maya) = try doubledLink()
        let updated = written.updatedAt

        #expect(try run().links == 1)
        let left = indexer.allLinks(in: context)
        #expect(left.count == 1 && left[0].unsureAmong.count == 1)
        #expect(maya.linkCount == 1)
        #expect(written.updatedAt == updated, "removing a copy isn't an edit")
    }

    @Test func onlyThePhoneThatMadeTheEntryFoldsItsLinks() throws {
        let origin = LocalOrigin(store: FakeKeyValueStore(), diagnostics: .disabled)
        LocalOrigin.register(origin, for: container)
        _ = try doubledLink()
        // Saved through the stamping path, so it is this phone's; take that back.
        let other = LocalOrigin(store: FakeKeyValueStore(), diagnostics: .disabled)
        LocalOrigin.register(other, for: container)

        #expect(try run().links == 0)
        #expect(indexer.allLinks(in: context).count == 2)
    }

    @Test func aSecondInsightsRowForOneEntryGoesAndTheNewerStays() throws {
        let written = try entry("A walk")
        let older = EntryInsights(generatedAt: date(1), sourceTextHash: "old")
        let newer = EntryInsights(generatedAt: date(2), sourceTextHash: "new")
        context.insert(older)
        context.insert(newer)
        older.entry = written
        newer.entry = written
        try context.save()
        let rows = try context.fetch(FetchDescriptor<EntryInsights>()).filter { $0.entry?.id == written.id }
        // Core Data may already have let go of one side of a one-to-one; then there is nothing to do.
        let expected = rows.count - 1

        #expect(try run().insights == expected)
        #expect(written.insights?.sourceTextHash == "new")
        #expect(try context.fetch(FetchDescriptor<EntryInsights>()).filter { $0.entry?.id == written.id }.count == 1)
    }

    // MARK: - Summaries

    private func item(_ title: String, _ verdict: String) -> ReflectQueueItem {
        ReflectQueueItem(id: UUID().uuidString, source: .generated, title: title, body: "", prompt: verdict)
    }

    @Test func aRecapWrittenOnBothPhonesKeepsTheNewest() throws {
        let first = ReflectSummary(kind: .week, periodStart: date(0), generatedAt: date(7), items: [item("a", "")])
        let second = ReflectSummary(kind: .week, periodStart: date(0), generatedAt: date(8), items: [item("b", "")])
        let otherWeek = ReflectSummary(kind: .week, periodStart: date(7), generatedAt: date(8), items: [])
        let month = ReflectSummary(kind: .month, periodStart: date(0), generatedAt: date(8), items: [])
        [first, second, otherWeek, month].forEach(context.insert)
        try context.save()

        #expect(try run().summaries == 1)
        let left = try context.fetch(FetchDescriptor<ReflectSummary>())
        #expect(left.count == 3)
        #expect(!left.contains { $0.id == first.id })
    }

    @Test func lifeFeedbackFromBothPhonesIsCombined() throws {
        let earlier = ReflectSummary(kind: .month, periodStart: .distantPast, generatedAt: date(1), items: [item("runs lift you", "right"), item("work weighs", "right")])
        let later = ReflectSummary(kind: .month, periodStart: .distantPast, generatedAt: date(2), items: [item("work weighs", "notQuite"), item("home is quiet", "right")])
        for row in [earlier, later] {
            row.periodKindRaw = LifeWords.feedbackKind
            context.insert(row)
        }
        try context.save()

        #expect(try run().summaries == 1)
        let verdicts = Dictionary(uniqueKeysWithValues: LifeWords.feedback(in: context).map { ($0.line, $0.right) })
        #expect(verdicts == ["runs lift you": true, "work weighs": false, "home is quiet": true])
        #expect(try run() == SyncDuplicates.Result())
    }

    // MARK: - Ask

    @Test func aConversationContinuedOnTwoPhonesKeepsEveryMessageInOneOrder() throws {
        let conversation = AskConversation(createdAt: date(0), title: "Deadline")
        context.insert(conversation)
        let first = AskMessage(conversationID: conversation.id, index: 0, role: .user, text: "q")
        let here = AskMessage(conversationID: conversation.id, index: 1, role: .user, text: "here")
        let there = AskMessage(conversationID: conversation.id, index: 1, role: .user, text: "there")
        [first, here, there].forEach(context.insert)
        try context.save()

        let read = AskMessage.all(forConversation: conversation.id, in: context)
        #expect(read.count == 3 && read[0] === first)
        #expect(read.map(\.id) == AskMessage.all(forConversation: conversation.id, in: context).map(\.id))
        #expect(AskMessage.renumberIfRepeated(read) == 3)
        #expect(read.map(\.index) == [0, 1, 2])
        #expect(AskMessage.renumberIfRepeated(read) == 3)
    }
}

// Every launch sweep, run a second time over the store the first run left, changes nothing. That
// proves only idempotence: two phones sweeping stale copies seconds apart is a device step.
@MainActor
struct LaunchSweepIdempotenceTests {
    @Test func everySweepRunTwiceChangesNothingTheSecondTime() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        try DemoJournal.seedIfEmpty(count: 40, in: context, now: now)
        // A name two phones made apart, for the merge to find on the first pass.
        let copy = Entity(name: "Sarah", key: "sarah", kind: .person, createdAt: now)
        context.insert(copy)
        try context.save()

        let editor = GraphEditor(diagnostics: .disabled)
        let indexer = GraphIndexer(diagnostics: .disabled)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SweepTwice-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        func sweep() throws {
            _ = try EntryDateRepair.run(in: context)
            _ = try EntityLinkRepair.run(in: context)
            _ = indexer.sweep(in: context)
            if LooseEnd.fade(in: context, now: now, diagnostics: .disabled) > 0 { try context.saveStampingEntries(at: now) }
            _ = try EntryDuplicates.merge(in: context)
            try SyncDuplicates.run(in: context, editor: editor, indexer: indexer, diagnostics: .disabled)
        }

        func records(_ name: String) throws -> JournalRecords {
            let parent = folder.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            let exported = try JournalExport.write(from: context, into: parent, now: now, diagnostics: .disabled).folder
            return try JournalImport.read(folder: exported).records
        }

        try sweep()
        let once = try records("once")
        try sweep()
        let twice = try records("twice")

        #expect(!once.entries.isEmpty && !once.entities.isEmpty)
        #expect(once == twice)
    }
}
