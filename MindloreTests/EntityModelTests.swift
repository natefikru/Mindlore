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
    }

    // A raw value written by a newer build, or corrupted, reads as a fallback rather than crashing.
    @Test func unknownRawValuesReadAsFallbacks() {
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

    // A merge loser leaves every list without the user having hidden it, so unmerge can tell
    // a hidden entity from a merged one.
    @Test func mergedAndHiddenAreSeparateReasonsToLeaveTheLists() {
        let entity = Entity(name: "Sarah K", key: "sarah k", kind: .person)
        #expect(entity.isBrowsable)

        entity.mergedIntoID = UUID()
        #expect(entity.isMerged && !entity.isBrowsable && !entity.hidden)

        let hiddenOnly = Entity(name: "Monday", key: "monday", kind: .event)
        hiddenOnly.hidden = true
        #expect(!hiddenOnly.isBrowsable && !hiddenOnly.isMerged)
    }
}

// The three ways a link changes hands. Merge and unmerge have to round-trip exactly, and a
// user re-point must never be mistaken for either.
struct EntityLinkOwnershipTests {
    private func link(on entity: Entity) -> EntityLink {
        let link = EntityLink(surface: "Sarah", kind: .person)
        link.entity = entity
        return link
    }

    @Test func mergeRecordsWhereTheLinkCameFrom() {
        let loser = Entity(name: "Sarah K", key: "sarah k", kind: .person)
        let winner = Entity(name: "Sarah Kim", key: "sarah kim", kind: .person)
        let link = link(on: loser)

        link.moveForMerge(to: winner)

        #expect(link.entity === winner)
        #expect(link.originalEntityID == loser.id)
    }

    // B into A, then A into C. The link sits on C, but it was born on B, so unmerging B is
    // what should claim it back.
    @Test func aSecondMergeLeavesTheFirstBirthplaceAlone() {
        let b = Entity(name: "Sarah K", key: "sarah k", kind: .person)
        let a = Entity(name: "Sarah Kim", key: "sarah kim", kind: .person)
        let c = Entity(name: "Sarah Kim-Jones", key: "sarah kim-jones", kind: .person)
        let link = link(on: b)

        link.moveForMerge(to: a)
        link.moveForMerge(to: c)

        #expect(link.entity === c)
        #expect(link.originalEntityID == b.id)
    }

    // A link whose entity was deleted is garbage waiting for recount. Giving it a birthplace
    // would invent history it never had.
    @Test func mergeSkipsALinkWhoseEntityIsGone() {
        let winner = Entity(name: "Sarah Kim", key: "sarah kim", kind: .person)
        let link = EntityLink(surface: "Sarah", kind: .person)

        link.moveForMerge(to: winner)

        #expect(link.entity == nil)
        #expect(link.originalEntityID == nil)
    }

    @Test func unmergeRestoresTheLinkAndClearsTheUndo() {
        let loser = Entity(name: "Sarah K", key: "sarah k", kind: .person)
        let winner = Entity(name: "Sarah Kim", key: "sarah kim", kind: .person)
        let link = link(on: loser)
        link.moveForMerge(to: winner)

        link.restore(to: loser)

        #expect(link.entity === loser)
        #expect(link.originalEntityID == nil)
    }

    // The user pointing one mention somewhere else is a new birth. If it kept an
    // originalEntityID, a later unmerge would drag the link back to an entity the user had
    // already moved it off.
    @Test func repointingMakesTheLinkTheUsersAndForgetsAnyMerge() {
        let loser = Entity(name: "Sarah K", key: "sarah k", kind: .person)
        let winner = Entity(name: "Sarah Kim", key: "sarah kim", kind: .person)
        let someoneElse = Entity(name: "Sarah Lee", key: "sarah lee", kind: .person)
        let link = link(on: loser)
        link.moveForMerge(to: winner)

        link.repoint(to: someoneElse)

        #expect(link.entity === someoneElse)
        #expect(link.originalEntityID == nil)
        #expect(link.source == .user)
    }
}

@MainActor
struct EntityPersistenceTests {
    // The container has to outlive the context: mainContext does not hold it, and a dropped
    // container deallocates the context out from under the test.
    private func linked(_ entry: Entry, _ entity: Entity, surface: String, in context: ModelContext) -> EntityLink {
        let link = EntityLink(surface: surface, kind: entity.kind)
        context.insert(link)
        link.entry = entry
        link.entity = entity
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

    @Test func movingALinkMovesItOnBothEntities() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let entry = Entry(text: "Lunch with Sarah")
        context.insert(entry)
        let loser = Entity(name: "Sarah K", key: "sarah k", kind: .person)
        let winner = Entity(name: "Sarah Kim", key: "sarah kim", kind: .person)
        context.insert(loser)
        context.insert(winner)
        let link = linked(entry, loser, surface: "Sarah", in: context)
        try context.save()

        link.moveForMerge(to: winner)
        try context.save()

        #expect(loser.links?.isEmpty ?? true)
        #expect(winner.links?.count == 1)
        #expect(entry.entityLinks?.count == 1)
        #expect(link.originalEntityID == loser.id)
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

    // Nullify the other way: deleting an entity must never reach into an entry and delete its
    // links. Reopened from disk, so this is the stored state and not a stale object in memory.
    @Test func deletingAnEntityNullifiesItsLinksAndKeepsTheEntry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("entries.store")

        do {
            let container = try ModelContainerFactory.make(.file(url))
            let context = container.mainContext
            let entry = Entry(text: "Lunch with Sarah")
            context.insert(entry)
            let entity = Entity(name: "Sarah Kim", key: "sarah kim", kind: .person)
            context.insert(entity)
            _ = linked(entry, entity, surface: "Sarah", in: context)
            try context.save()

            context.delete(entity)
            try context.save()
        }

        let reopened = try ModelContainerFactory.make(.file(url))
        let context = reopened.mainContext
        #expect(try context.fetchCount(FetchDescriptor<Entry>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Entity>()) == 0)
        let links = try context.fetch(FetchDescriptor<EntityLink>())
        try #require(links.count == 1)
        #expect(links[0].entity == nil)
        #expect(links[0].entry != nil)
    }

    @Test func everyFieldSurvivesAFileStore() throws {
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
            let winner = Entity(id: winnerID, name: "Sarah Kim", key: "sarah kim", kind: .person)
            winner.aliases = ["Sarah", "my sister"]
            winner.bio = "Sister. Lives in Seattle."
            winner.bioWasGenerated = true
            winner.confirmedByUser = true
            winner.kindEditedByUser = true
            winner.linkCount = 7
            winner.firstLinkedAt = first
            winner.lastLinkedAt = last
            winner.notSameAs = [dismissed]
            context.insert(winner)

            // A merge loser: pointed at the winner, never hidden by the user.
            let loser = Entity(name: "Sarah K", key: "sarah k", kind: .person)
            loser.mergedIntoID = winnerID
            loser.mergedAt = last
            loser.contributedAliases = ["Sarah K"]
            context.insert(loser)
            try context.save()
        }

        let reopened = try ModelContainerFactory.make(.file(url))
        let context = reopened.mainContext
        let live = try context.fetch(FetchDescriptor<Entity>(predicate: #Predicate { $0.mergedIntoID == nil }))
        try #require(live.count == 1)
        // key and kind are what the resolver matches on, so they matter most of all.
        #expect(live[0].key == "sarah kim")
        #expect(live[0].kind == .person)
        #expect(live[0].id == winnerID)
        #expect(live[0].name == "Sarah Kim")
        #expect(live[0].aliases == ["Sarah", "my sister"])
        #expect(live[0].bio == "Sister. Lives in Seattle." && live[0].bioWasGenerated)
        #expect(live[0].confirmedByUser && live[0].kindEditedByUser)
        #expect(live[0].linkCount == 7)
        #expect(live[0].firstLinkedAt == first && live[0].lastLinkedAt == last)
        #expect(live[0].notSameAs == [dismissed])

        let merged = try context.fetch(FetchDescriptor<Entity>(predicate: #Predicate { $0.mergedIntoID != nil }))
        try #require(merged.count == 1)
        #expect(merged[0].mergedIntoID == winnerID)
        #expect(merged[0].contributedAliases == ["Sarah K"])
        #expect(!merged[0].hidden && !merged[0].isBrowsable)
    }

    // What Connections sorts on. An entity that has never been linked has no lastLinkedAt and
    // must not sort as if it were the most recent thing in the journal.
    @Test func entitiesSortByCountAndRecencyWithNeverLinkedOnesLast() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        for (name, count, last) in [("a", 3, 100.0), ("b", 9, 50.0), ("c", 1, 900.0)] {
            let entity = Entity(name: name, key: name, kind: .tag)
            entity.linkCount = count
            entity.lastLinkedAt = Date(timeIntervalSince1970: last)
            context.insert(entity)
        }
        let neverLinked = Entity(name: "d", key: "d", kind: .tag)
        context.insert(neverLinked)
        try context.save()

        let byCount = try context.fetch(FetchDescriptor<Entity>(sortBy: [
            SortDescriptor(\.linkCount, order: .reverse), SortDescriptor(\.createdAt),
        ]))
        #expect(byCount.map(\.name) == ["b", "a", "c", "d"])

        let byRecency = try context.fetch(FetchDescriptor<Entity>(sortBy: [SortDescriptor(\.lastLinkedAt, order: .reverse)]))
        #expect(byRecency.map(\.name) == ["c", "a", "b", "d"], "a nil date sorts last, not first")
    }

    // The resolver's own lookup: live entities of one kind, in one predicate.
    @Test func liveEntitiesOfOneKindFetchInOnePredicate() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let wanted = Entity(name: "Sarah Kim", key: "sarah kim", kind: .person)
        let hidden = Entity(name: "Bob", key: "bob", kind: .person)
        hidden.hidden = true
        let merged = Entity(name: "Sarah K", key: "sarah k", kind: .person)
        merged.mergedIntoID = wanted.id
        let otherKind = Entity(name: "sarah kim", key: "sarah kim", kind: .tag)
        for entity in [wanted, hidden, merged, otherKind] { context.insert(entity) }
        try context.save()

        let person = EntityKind.person.rawValue
        let browsable = try context.fetch(FetchDescriptor<Entity>(predicate: #Predicate {
            $0.kindRaw == person && !$0.hidden && $0.mergedIntoID == nil
        }))
        #expect(browsable.map(\.name) == ["Sarah Kim"])

        // Hiding takes something out of the lists, not out of resolution, so the resolver's
        // exact-match lookup still has to find it.
        let resolvable = try context.fetch(FetchDescriptor<Entity>(predicate: #Predicate {
            $0.kindRaw == person && $0.mergedIntoID == nil
        }))
        #expect(Set(resolvable.map(\.name)) == ["Sarah Kim", "Bob"])
    }

    // Every graph query filters on the model's own UUID through the relationship.
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

        // Reindexing an entry removes its AI links and keeps the user's, so source has to filter.
        let aiLinks = EntityLinkSource.ai.rawValue
        #expect(try context.fetchCount(FetchDescriptor<EntityLink>(predicate: #Predicate { $0.sourceRaw == aiLinks })) == 3)
    }
}
