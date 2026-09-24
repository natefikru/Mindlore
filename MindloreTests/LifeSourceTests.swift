import Foundation
import SwiftData
import Testing
@testable import Mindlore

@MainActor
struct LifeSourceTests {
    // Held for the test's life: a context outlives nothing its container doesn't.
    private let container: ModelContainer

    init() throws {
        container = try ModelContainerFactory.make(.inMemory)
    }

    private func journal() throws -> ModelContext {
        container.mainContext
    }

    @discardableResult
    private func entry(_ context: ModelContext, areas: [LifeArea] = [.work], mood: Mood? = .calm, tags: [String] = [], draft: Bool = false, note: Bool = false, insights: Bool = true, daysAgo: Double = 1) -> Entry {
        let entry = Entry(createdAt: Date.now.addingTimeInterval(-daysAgo * 86_400), text: "Words")
        entry.isDraft = draft
        entry.isNote = note
        context.insert(entry)
        if insights {
            let made = EntryInsights()
            made.areasRaw = areas.map(\.rawValue)
            made.primaryMoodRaw = mood?.rawValue
            made.tags = tags
            entry.insights = made
        }
        return entry
    }

    @Test func draftsAndEntriesInsightsNeverReadAreLeftOut() throws {
        let context = try journal()
        let kept = entry(context)
        entry(context, draft: true)
        entry(context, insights: false)
        try context.save()
        #expect(LifeSource.facts(in: context).entries.map(\.id) == [kept.id])
    }

    @Test func aNoteCountsWithoutAMood() throws {
        let context = try journal()
        entry(context, mood: .anxious, note: true)
        try context.save()
        let fact = try #require(LifeSource.facts(in: context).entries.first)
        #expect(fact.areas == [.work])
        #expect(fact.valence == nil)
    }

    @Test func aHiddenTagIsDropped() throws {
        let context = try journal()
        entry(context, tags: ["running", "secret"])
        let hidden = Entity(name: "secret", key: "secret", kind: .tag)
        hidden.hidden = true
        context.insert(hidden)
        try context.save()
        #expect(LifeSource.facts(in: context).entries.first?.tags == ["running"])
    }

    @Test func aLooseEndIsDatedByItsEntryAndTakesItsAreas() throws {
        let context = try journal()
        let source = entry(context, areas: [.money], daysAgo: 10)
        let end = LooseEnd(text: "Call the bank", sourceEntryID: source.id, sourceEntryDate: source.entryDate)
        context.insert(end)
        try context.save()
        let thread = try #require(LifeSource.facts(in: context).threads.first)
        #expect(thread.raisedOn == source.entryDate)
        #expect(thread.areas == [.money])
        #expect(thread.status == .open)
    }

    @Test func peopleWalkMergesSkipHiddenAndMutedAndRankByEntries() throws {
        let context = try journal()
        let a = entry(context), b = entry(context), c = entry(context)
        let maya = Entity(name: "Maya", key: "maya", kind: .person)
        let mayaOld = Entity(name: "May", key: "may", kind: .person)
        mayaOld.mergedIntoID = maya.id
        let greg = Entity(name: "Greg", key: "greg", kind: .person)
        let ghost = Entity(name: "Ghost", key: "ghost", kind: .person)
        ghost.hidden = true
        let quiet = Entity(name: "Quiet", key: "quiet", kind: .person)
        quiet.resurfacingMuted = true
        for entity in [maya, mayaOld, greg, ghost, quiet] { context.insert(entity) }
        func link(_ entity: Entity, _ entry: Entry) {
            let made = EntityLink(surface: entity.name, kind: .person)
            made.entityID = entity.id
            made.entryID = entry.id
            context.insert(made)
        }
        link(maya, a); link(mayaOld, b); link(greg, c); link(ghost, a); link(quiet, b)
        try context.save()

        let people = LifeSource.people(in: [a.id, b.id, c.id], context: context)
        #expect(people.map(\.name) == ["Maya", "Greg"])
        #expect(people.first?.entries == 2, "the merged name's entry counts for the winner")
    }
}
