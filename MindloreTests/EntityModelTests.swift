import Foundation
import SwiftData
import Testing
@testable import Mindlore

struct EntityKindTests {
    // Renaming or removing a stored raw value orphans every entity and link that used it.
    // Add new kinds at the end of this list.
    @Test func rawValuesArePinned() {
        #expect(EntityKind.allCases.map(\.rawValue) == [
            "person", "place", "organization", "project", "event", "other", "tag", "theme",
        ])
        #expect(EntityLinkSource.allCases.map(\.rawValue) == ["ai", "user"])
    }

    // Every MentionKind has to survive the trip into the graph unchanged, or an existing
    // mention would land under the wrong kind.
    @Test func everyMentionKindMapsToItsOwnEntityKind() {
        for mention in MentionKind.allCases {
            #expect(EntityKind(mention).rawValue == mention.rawValue)
        }
        #expect(EntityKind.mentionKinds.count == MentionKind.allCases.count)
        #expect(!EntityKind.mentionKinds.contains(.tag))
        #expect(!EntityKind.mentionKinds.contains(.theme))
    }

    @Test func unknownRawValueFallsBackToOther() {
        #expect(EntityKind(rawValue: "spaceship") == nil)
        let entity = Entity(name: "x", key: "x", kind: .person)
        entity.kindRaw = "spaceship"
        #expect(entity.kind == .other)

        let link = EntityLink(surface: "x", kind: .person)
        link.kindRaw = "spaceship"
        link.sourceRaw = "telepathy"
        #expect(link.kind == .other)
        #expect(link.source == .ai)
    }

    @Test func everyKindHasPresentationText() {
        for kind in EntityKind.allCases {
            #expect(!kind.symbol.isEmpty)
            #expect(!kind.heading.isEmpty)
            #expect(!kind.label.isEmpty)
        }
        // The insights cards keep the headings they already showed.
        #expect(MentionKind.person.heading == "People")
        #expect(MentionKind.other.symbol == "tag")
    }

    @Test func accessorsWriteThroughToRawValues() {
        let entity = Entity(name: "Sarah Kim", key: "sarah kim", kind: .person)
        #expect(entity.kindRaw == "person")
        entity.kind = .organization
        #expect(entity.kindRaw == "organization")

        let link = EntityLink(surface: "Sarah", kind: .person)
        #expect(link.sourceRaw == "ai")
        link.source = .user
        link.kind = .theme
        #expect(link.sourceRaw == "user" && link.kindRaw == "theme")
    }

    @Test func newEntitiesStartUnmergedAndUntouched() {
        let entity = Entity(name: "Sarah Kim", key: "sarah kim", kind: .person)
        #expect(!entity.isMerged)
        #expect(!entity.confirmedByUser && !entity.hidden && !entity.bioWasGenerated)
        #expect(entity.bio == nil && entity.mergedAt == nil)
        #expect(entity.aliases.isEmpty && entity.contributedAliases.isEmpty && entity.notSameAs.isEmpty)
        #expect(entity.linkCount == 0 && entity.firstLinkedAt == nil && entity.lastLinkedAt == nil)

        entity.mergedIntoID = UUID()
        #expect(entity.isMerged)
    }
}

@MainActor
struct EntityPersistenceTests {
    // The container has to outlive the context: mainContext does not hold it, and a dropped
    // container deallocates the context out from under the test.
    private func linked(_ entry: Entry, _ entity: Entity, surface: String, in context: ModelContext) -> EntityLink {
        let link = EntityLink(surface: surface, kind: entity.kind)
        context.insert(link)
        link.attach(to: entry, entity: entity)
        return link
    }

    @Test func linksAreReachableFromBothSides() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let entry = Entry(text: "Lunch with Sarah")
        context.insert(entry)
        let entity = Entity(name: "Sarah Kim", key: "sarah kim", kind: .person)
        context.insert(entity)
        let link = linked(entry, entity, surface: "Sarah", in: context)
        try context.save()

        #expect(entry.entityLinks?.count == 1)
        #expect(entity.links?.count == 1)
        #expect(link.entry === entry && link.entity === entity)
        #expect(link.surface == "Sarah")
        #expect(link.source == .ai && !link.inferred && link.originalEntityID == nil)
    }

    // Cascade one way only: an entry owns its links.
    @Test func deletingAnEntryDeletesItsLinksAndLeavesTheEntity() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let entry = Entry(text: "Lunch with Sarah")
        context.insert(entry)
        let entity = Entity(name: "Sarah Kim", key: "sarah kim", kind: .person)
        context.insert(entity)
        _ = linked(entry, entity, surface: "Sarah", in: context)
        try context.save()

        Entry.delete(entry, in: context)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<EntityLink>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Entity>()) == 1)
    }

    // Nullify the other way: deleting an entity must never reach into an entry and delete
    // its links. Recount cleans up what is left behind.
    @Test func deletingAnEntityNullifiesItsLinksAndKeepsTheEntry() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let entry = Entry(text: "Lunch with Sarah")
        context.insert(entry)
        let entity = Entity(name: "Sarah Kim", key: "sarah kim", kind: .person)
        context.insert(entity)
        let link = linked(entry, entity, surface: "Sarah", in: context)
        try context.save()

        context.delete(entity)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<Entry>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<EntityLink>()) == 1)
        #expect(link.entity == nil)
        #expect(link.entry === entry)
    }

    // The Connections list sorts on these, so they have to be storable and sortable.
    @Test func countersAndMergePointersSurviveAFileStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("entries.store")
        let winnerID = UUID()
        let dismissed = UUID()
        let first = Date(timeIntervalSince1970: 1_000)
        let last = Date(timeIntervalSince1970: 9_000)

        do {
            let container = try ModelContainerFactory.make(.file(url))
            let context = container.mainContext
            let winner = Entity(name: "Sarah Kim", key: "sarah kim", kind: .person)
            winner.id = winnerID
            winner.aliases = ["Sarah", "my sister"]
            winner.bio = "Sister. Lives in Seattle."
            winner.bioWasGenerated = true
            winner.confirmedByUser = true
            winner.linkCount = 7
            winner.firstLinkedAt = first
            winner.lastLinkedAt = last
            winner.notSameAs = [dismissed]
            context.insert(winner)

            let loser = Entity(name: "Sarah K", key: "sarah k", kind: .person)
            loser.mergedIntoID = winnerID
            loser.mergedAt = last
            loser.contributedAliases = ["Sarah K"]
            loser.hidden = true
            context.insert(loser)
            try context.save()
        }

        let reopened = try ModelContainerFactory.make(.file(url))
        let context = reopened.mainContext
        let live = try context.fetch(FetchDescriptor<Entity>(predicate: #Predicate { $0.mergedIntoID == nil }))
        try #require(live.count == 1)
        #expect(live[0].id == winnerID)
        #expect(live[0].aliases == ["Sarah", "my sister"])
        #expect(live[0].bio == "Sister. Lives in Seattle." && live[0].bioWasGenerated)
        #expect(live[0].linkCount == 7)
        #expect(live[0].firstLinkedAt == first && live[0].lastLinkedAt == last)
        #expect(live[0].notSameAs == [dismissed])

        let merged = try context.fetch(FetchDescriptor<Entity>(predicate: #Predicate { $0.mergedIntoID != nil }))
        try #require(merged.count == 1)
        #expect(merged[0].mergedIntoID == winnerID)
        #expect(merged[0].contributedAliases == ["Sarah K"])
        #expect(merged[0].hidden)
    }

    @Test func entitiesSortByCountAndRecency() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        for (name, count, last) in [("a", 3, 100.0), ("b", 9, 50.0), ("c", 1, 900.0)] {
            let entity = Entity(name: name, key: name, kind: .tag)
            entity.linkCount = count
            entity.lastLinkedAt = Date(timeIntervalSince1970: last)
            context.insert(entity)
        }
        try context.save()

        let byCount = try context.fetch(FetchDescriptor<Entity>(sortBy: [SortDescriptor(\.linkCount, order: .reverse)]))
        #expect(byCount.map(\.name) == ["b", "a", "c"])
        let byRecency = try context.fetch(FetchDescriptor<Entity>(sortBy: [SortDescriptor(\.lastLinkedAt, order: .reverse)]))
        #expect(byRecency.map(\.name) == ["c", "a", "b"])
    }

    // Every graph query runs from the link side, because a predicate on an optional
    // to-many relationship is where SwiftData falls over.
    @Test func linksAreQueryableByEntityAndEntry() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let sarah = Entity(name: "Sarah Kim", key: "sarah kim", kind: .person)
        let river = Entity(name: "river", key: "river", kind: .tag)
        context.insert(sarah)
        context.insert(river)
        let monday = Entry(text: "Lunch with Sarah by the river")
        let tuesday = Entry(text: "Walked the river")
        context.insert(monday)
        context.insert(tuesday)
        _ = linked(monday, sarah, surface: "Sarah", in: context)
        _ = linked(monday, river, surface: "river", in: context)
        _ = linked(tuesday, river, surface: "river", in: context)
        try context.save()

        // Every graph query filters on the model's own UUID through the relationship.
        let sarahID = sarah.id
        let ofSarah = try context.fetch(FetchDescriptor<EntityLink>(predicate: #Predicate { link in
            if let entity = link.entity { entity.id == sarahID } else { false }
        }))
        #expect(ofSarah.count == 1)
        #expect(ofSarah.first?.surface == "Sarah")

        let mondayID = monday.id
        let ofMonday = try context.fetch(FetchDescriptor<EntityLink>(predicate: #Predicate { link in
            if let entry = link.entry { entry.id == mondayID } else { false }
        }))
        #expect(ofMonday.count == 2)
        #expect(Set(ofMonday.map(\.surface)) == ["Sarah", "river"])

        let aiLinks = EntityLinkSource.ai.rawValue
        #expect(try context.fetchCount(FetchDescriptor<EntityLink>(predicate: #Predicate { $0.sourceRaw == aiLinks })) == 3)
    }

}
