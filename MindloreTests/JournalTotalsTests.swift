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
}
