import Foundation
import SwiftData
import Testing
@testable import Mindlore

// What Settings' About section counts. Each exclusion is a rule the rest of the app already follows,
// so a total that disagreed with Mind or the journal list would be the confusing one.
@MainActor
struct JournalTotalsTests {
    @Test func anEmptyJournalCountsNothing() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        #expect(JournalTotals.count(in: container.mainContext) == JournalTotals())
    }

    @Test func draftsAreNotEntriesYet() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        context.insert(Entry(source: .typed, text: "Finished."))
        context.insert(Entry(source: .voice, text: "Spoken."))
        let draft = Entry(source: .typed, text: "Half a thou")
        draft.isDraft = true
        context.insert(draft)
        try context.save()

        #expect(JournalTotals.count(in: context).entries == 2)
    }

    @Test func namesLeaveOutMergedHiddenAndTags() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let maya = Entity(name: "Maya", key: "maya", kind: .person)
        let cafe = Entity(name: "The Corner Cafe", key: "the corner cafe", kind: .place)
        // Merged into Maya: an alias now, not a second person.
        let alsoMaya = Entity(name: "M", key: "m", kind: .person)
        alsoMaya.mergedIntoID = maya.id
        // Asked to go away.
        let hidden = Entity(name: "Ex", key: "ex", kind: .person)
        hidden.hidden = true
        // A label, not a name.
        let running = Entity(name: "running", key: "running", kind: .tag)
        for entity in [maya, cafe, alsoMaya, hidden, running] { context.insert(entity) }
        try context.save()

        #expect(JournalTotals.count(in: context).names == 2)
    }

    @Test func daysAreCountedByTheDayAnEntryBelongsTo() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let march3 = Date(timeIntervalSince1970: 1_772_524_800) // 2026-03-03 08:00 UTC
        let morning = Entry(source: .typed, text: "one")
        morning.entryDate = march3
        let evening = Entry(source: .typed, text: "two")
        evening.entryDate = march3.addingTimeInterval(10 * 3600)
        // Reached the app today, but belongs to a day in January: January is the day that counts.
        let backdated = Entry(source: .typed, text: "three")
        backdated.entryDate = march3.addingTimeInterval(-50 * 86_400)
        for entry in [morning, evening, backdated] { context.insert(entry) }
        try context.save()

        let totals = JournalTotals.count(in: context, calendar: utc)
        #expect(totals.days == 2)
        #expect(totals.firstDay == backdated.entryDate)
    }

    @Test func wordsSourcesAndKindsLeaveOutDrafts() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        context.insert(Entry(source: .typed, text: "A walk by the river,  then home.\n"))
        context.insert(Entry(source: .voice, text: "Spoke to Maya"))
        let note = Entry(source: .typed, text: "milk eggs")
        note.kind = .note
        context.insert(note)
        let poem = Entry(source: .photo, text: "")
        poem.kind = .creative
        context.insert(poem)
        let draft = Entry(source: .voice, text: "not yet counted at all")
        draft.isDraft = true
        context.insert(draft)
        try context.save()

        let totals = JournalTotals.count(in: context)
        #expect(totals.words == 7 + 3 + 2)
        #expect(totals.bySource == [.typed: 2, .voice: 1, .photo: 1])
        #expect(totals.byKind == [.journal: 2, .note: 1, .creative: 1])
    }

    @Test func namesByKindThreadsAndConversations() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let maya = Entity(name: "Maya", key: "maya", kind: .person)
        let sam = Entity(name: "Sam", key: "sam", kind: .person)
        let cafe = Entity(name: "The Corner Cafe", key: "the corner cafe", kind: .place)
        let hidden = Entity(name: "Ex", key: "ex", kind: .person)
        hidden.hidden = true
        for entity in [maya, sam, cafe, hidden] { context.insert(entity) }

        let closed = LooseEnd(text: "Call the landlord", sourceEntryID: UUID(), sourceEntryDate: .now)
        closed.status = .resolved
        let open = LooseEnd(text: "Book the dentist", sourceEntryID: UUID(), sourceEntryDate: .now)
        let letGo = LooseEnd(text: "Fix the bike", sourceEntryID: UUID(), sourceEntryDate: .now)
        letGo.status = .dismissed
        for end in [closed, open, letGo] { context.insert(end) }
        context.insert(AskConversation(title: "How was March?"))
        try context.save()

        let totals = JournalTotals.count(in: context)
        #expect(totals.namesByKind == [.person: 2, .place: 1])
        #expect(totals.threadsClosed == 1)
        #expect(totals.conversations == 1)
    }

    @Test func wordCountSplitsOnAnyWhitespace() {
        #expect(JournalTotals.wordCount("") == 0)
        #expect(JournalTotals.wordCount("  \n\t ") == 0)
        #expect(JournalTotals.wordCount("one\ntwo\tthree  four") == 4)
    }
}
