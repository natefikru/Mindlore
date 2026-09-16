import Foundation
import SwiftData
import Testing
@testable import Mindlore

@MainActor
struct GraphEditorTests {
    // Stored, so the container outlives every assertion in the test. See GraphIndexerTests.
    let harness: GraphHarness
    let editor = GraphEditor(diagnostics: .disabled)

    init() throws {
        harness = try GraphHarness()
    }

    // Two entries mentioning two different names, so merging has real links to move.
    private func twoPeople() throws -> (Entity, Entity) {
        try harness.entry(entryDate: Date(timeIntervalSince1970: 1_000), mentions: [("Sarah K", .person)])
        try harness.entry(entryDate: Date(timeIntervalSince1970: 9_000), mentions: [("Sarah Kim", .person)])
        harness.indexer.sweep(in: harness.context)
        return (try harness.entity("Sarah K"), try harness.entity("Sarah Kim"))
    }

    // MARK: - Editing one entity

    @Test func renamingChangesTheKeyEverythingMatchesOn() throws {
        let entity = Entity(name: "sarah", key: "sarah", kind: .person)
        harness.context.insert(entity)

        #expect(editor.rename(entity, to: "  Sarah Kim  ", in: harness.context) == .applied)

        #expect(entity.name == "Sarah Kim")
        #expect(entity.key == "sarah kim")
        #expect(entity.confirmedByUser)
    }

    // Two live entities answering to one name would leave the resolver guessing, so the edit
    // stops and hands back the entity that was probably meant.
    @Test func renamingOntoAnExistingNameReportsTheCollision() throws {
        let (loser, winner) = try twoPeople()

        #expect(editor.rename(loser, to: "Sarah Kim", in: harness.context) == .collides(with: winner.id))
        #expect(loser.name == "Sarah K", "nothing is applied until the user decides")
    }

    @Test func renamingOntoAnAliasCollidesToo() throws {
        let (loser, winner) = try twoPeople()
        #expect(editor.addAlias("my sister", to: winner, in: harness.context) == .applied)

        #expect(editor.rename(loser, to: "My Sister", in: harness.context) == .collides(with: winner.id))
    }

    @Test func aRenameThatOnlyChangesSpellingIsFine() throws {
        let entity = Entity(name: "sarah kim", key: "sarah kim", kind: .person)
        harness.context.insert(entity)

        #expect(editor.rename(entity, to: "Sarah Kim", in: harness.context) == .applied)
        #expect(entity.name == "Sarah Kim")
    }

    @Test func renamingCanKeepTheOldNameAsAnAlias() throws {
        let entity = Entity(name: "Lewis", key: "lewis", kind: .person)
        harness.context.insert(entity)

        #expect(editor.rename(entity, to: "Luis", keepingOldNameAsAlias: true, in: harness.context) == .applied)
        #expect(entity.name == "Luis")
        #expect(entity.aliases == ["Lewis"])

        #expect(editor.rename(entity, to: "Luis R", keepingOldNameAsAlias: true, in: harness.context) == .applied)
        #expect(entity.aliases == ["Lewis", "Luis"], "the alias from the first rename survives the second")
    }

    @Test func renamingWithoutTheFlagAddsNoAlias() throws {
        let entity = Entity(name: "Lewis", key: "lewis", kind: .person)
        harness.context.insert(entity)

        #expect(editor.rename(entity, to: "Luis", in: harness.context) == .applied)
        #expect(entity.aliases.isEmpty)
    }

    @Test func keepingTheOldNameStillReportsACollision() throws {
        let (loser, winner) = try twoPeople()

        #expect(editor.rename(loser, to: "Sarah Kim", keepingOldNameAsAlias: true, in: harness.context) == .collides(with: winner.id))
        #expect(loser.name == "Sarah K", "nothing is applied, alias included, until the user decides")
        #expect(loser.aliases.isEmpty)
    }

    @Test func keepingTheOldNameOnASpellingOnlyRenameAddsNoDuplicateAlias() throws {
        let entity = Entity(name: "sarah kim", key: "sarah kim", kind: .person)
        harness.context.insert(entity)

        #expect(editor.rename(entity, to: "Sarah Kim", keepingOldNameAsAlias: true, in: harness.context) == .applied)
        #expect(entity.aliases.isEmpty, "the old spelling and the new one are the same key")
    }

    @Test func aliasesAreAddedOnceAndRemovedByTheirOwnSpelling() throws {
        let entity = Entity(name: "Sarah Kim", key: "sarah kim", kind: .person)
        harness.context.insert(entity)

        #expect(editor.addAlias("Sarah K", to: entity, in: harness.context) == .applied)
        #expect(editor.addAlias("sarah k", to: entity, in: harness.context) == .applied)
        #expect(entity.aliases == ["Sarah K"], "the same alias in different clothes is the same alias")
        #expect(editor.addAlias("Sarah Kim", to: entity, in: harness.context) == .applied)
        #expect(entity.aliases == ["Sarah K"], "its own name is not an alias")

        editor.removeAlias("Sarah K", from: entity)
        #expect(entity.aliases.isEmpty)
    }

    @Test func anAliasAnotherEntityAnswersToCollides() throws {
        let (loser, winner) = try twoPeople()

        #expect(editor.addAlias("Sarah Kim", to: loser, in: harness.context) == .collides(with: winner.id))
        #expect(loser.aliases.isEmpty)
    }

    @Test func pickingAKindStopsTheExtractionChangingIt() throws {
        let entity = Entity(name: "Acme", key: "acme", kind: .other)
        harness.context.insert(entity)

        editor.setKind(.organization, on: entity, in: harness.context)

        #expect(entity.kind == .organization)
        #expect(entity.kindEditedByUser)
        #expect(entity.confirmedByUser)
    }

    @Test func writingABioMakesItTheUsers() throws {
        let entity = Entity(name: "Sarah Kim", key: "sarah kim", kind: .person)
        entity.bio = "Drafted by AI."
        entity.bioWasGenerated = true
        harness.context.insert(entity)

        editor.setBio("  My sister.  ", on: entity)

        #expect(entity.bio == "My sister.")
        #expect(!entity.bioWasGenerated)

        editor.setBio("   ", on: entity)
        #expect(entity.bio == nil, "a bio of only spaces is no bio")
    }

    // Hiding outlives losing every link on its own account. If a hidden entity were pruned it
    // would come straight back the next time it was mentioned, which is the opposite of hiding.
    @Test func aHiddenEntitySurvivesLosingItsLastLink() throws {
        let entry = try harness.entry(tags: ["monday"])
        harness.indexer.sweep(in: harness.context)
        let monday = try harness.entity("monday")
        monday.hidden = true
        // Deliberately not confirmedByUser, so this can only pass because of `hidden`.
        monday.confirmedByUser = false
        try harness.context.save()

        entry.removeInsights(in: harness.context)
        harness.indexer.recount(in: harness.context)
        try harness.context.save()

        #expect(try harness.entities().map(\.name) == ["monday"])
        #expect(try harness.entity("monday").linkCount == 0)
    }

    @Test func dismissingASuggestionIsRecordedOnBothSides() throws {
        let (a, b) = try twoPeople()

        editor.markNotSame(a, as: b)

        #expect(a.notSameAs == [b.id])
        #expect(b.notSameAs == [a.id])
        #expect(editor.suggestions(in: harness.context).isEmpty)
    }

    // MARK: - Merging

    @Test func mergingMovesLinksAliasesAndCounters() throws {
        let (loser, winner) = try twoPeople()

        #expect(editor.merge(loser, into: winner, in: harness.context) == .merged)
        try harness.context.save()

        #expect(winner.linkCount == 2)
        #expect(winner.firstLinkedAt == Date(timeIntervalSince1970: 1_000))
        #expect(winner.lastLinkedAt == Date(timeIntervalSince1970: 9_000))
        #expect(winner.aliases == ["Sarah K"])
        #expect(loser.isMerged && loser.mergedIntoID == winner.id && loser.mergedAt != nil)
        #expect(loser.contributedAliases == ["Sarah K"])
        #expect(loser.linkCount == 0)
        #expect(!loser.isBrowsable && !loser.hidden, "merging is not hiding")
        // The loser survives the recount that merging triggers: it is the undo record.
        #expect(try harness.entities().count == 2)
    }

    @Test func unmergingPutsBackExactlyWhatWasMoved() throws {
        let (loser, winner) = try twoPeople()
        editor.merge(loser, into: winner, in: harness.context)
        try harness.context.save()

        #expect(editor.unmerge(loser, in: harness.context))
        try harness.context.save()

        #expect(loser.linkCount == 1 && winner.linkCount == 1)
        #expect(loser.firstLinkedAt == Date(timeIntervalSince1970: 1_000))
        #expect(winner.aliases.isEmpty)
        #expect(!loser.isMerged && loser.mergedAt == nil && loser.contributedAliases.isEmpty)
        #expect(loser.isBrowsable)
    }

    // The winner already answered to the name the loser brought, so unmerging must not take
    // it away from them.
    @Test func unmergingLeavesAliasesTheWinnerAlreadyHad() throws {
        let (loser, winner) = try twoPeople()
        #expect(editor.addAlias("Sarah K", to: winner, in: harness.context) == .collides(with: loser.id))
        // Force the same spelling onto the winner the way a merge of a third entity would.
        winner.aliases = ["Sarah K"]
        try harness.context.save()

        editor.merge(loser, into: winner, in: harness.context)
        #expect(loser.contributedAliases.isEmpty, "it brought nothing new")
        editor.unmerge(loser, in: harness.context)

        #expect(winner.aliases == ["Sarah K"])
    }

    // B into A, then A into C. Nothing is ever more than one hop from a live entity.
    @Test func mergingAWinnerFlattensWhatPointedAtIt() throws {
        let (b, a) = try twoPeople()
        try harness.entry(mentions: [("Sarah Kim-Jones", .person)])
        harness.indexer.sweep(in: harness.context)
        let c = try harness.entity("Sarah Kim-Jones")

        editor.merge(b, into: a, in: harness.context)
        editor.merge(a, into: c, in: harness.context)
        try harness.context.save()

        #expect(b.mergedIntoID == c.id, "B skips the middle and points at C")
        #expect(a.mergedIntoID == c.id)
        #expect(c.linkCount == 3)
        #expect(editor.root(of: b, in: harness.context).id == c.id)
    }

    // The link B brought is on C now, but it was born on B, so unmerging B claims it back.
    @Test func unmergingAfterAChainReturnsOnlyItsOwnLinks() throws {
        let (b, a) = try twoPeople()
        try harness.entry(mentions: [("Sarah Kim-Jones", .person)])
        harness.indexer.sweep(in: harness.context)
        let c = try harness.entity("Sarah Kim-Jones")
        editor.merge(b, into: a, in: harness.context)
        editor.merge(a, into: c, in: harness.context)
        try harness.context.save()

        #expect(editor.unmerge(b, in: harness.context))
        try harness.context.save()

        #expect(b.linkCount == 1)
        #expect(c.linkCount == 2, "A's own link and C's stay on C")
        #expect(a.isMerged && a.mergedIntoID == c.id)

        // And unmerging the middle afterwards still returns its own.
        #expect(editor.unmerge(a, in: harness.context))
        try harness.context.save()
        #expect(a.linkCount == 1 && c.linkCount == 1)
    }

    @Test func mergingIntoAMergedEntityGoesToWhatItStandsForNow() throws {
        let (b, a) = try twoPeople()
        try harness.entry(mentions: [("Sarah Kim-Jones", .person)])
        harness.indexer.sweep(in: harness.context)
        let c = try harness.entity("Sarah Kim-Jones")
        editor.merge(a, into: c, in: harness.context)

        // The user picks A, which is already merged into C. The links belong on C.
        #expect(editor.merge(b, into: a, in: harness.context) == .merged)
        try harness.context.save()

        #expect(b.mergedIntoID == c.id)
        #expect(c.linkCount == 3)
    }

    @Test func mergingRefusesLoops() throws {
        let (b, a) = try twoPeople()

        #expect(editor.merge(a, into: a, in: harness.context) == .refused)
        editor.merge(b, into: a, in: harness.context)
        // A into B would point A at something that already points at A.
        #expect(editor.merge(a, into: b, in: harness.context) == .refused)
        #expect(!a.isMerged)
    }

    @Test func unmergingSomethingThatWasNeverMergedDoesNothing() throws {
        let (_, winner) = try twoPeople()
        #expect(!editor.unmerge(winner, in: harness.context))
    }

    // A merged name still resolves: the next entry mentioning it lands on the winner.
    @Test func aLaterMentionOfAMergedNameGoesToTheWinner() throws {
        let (loser, winner) = try twoPeople()
        editor.merge(loser, into: winner, in: harness.context)
        try harness.context.save()

        try harness.entry(mentions: [("Sarah K", .person)])
        harness.indexer.sweep(in: harness.context)

        #expect(try harness.entities().count == 2, "no third entity appeared")
        #expect(winner.linkCount == 3)
    }

    // MARK: - One mention at a time

    @Test func repointingMovesOneLinkAndLeavesTheRest() throws {
        try harness.entry(mentions: [("Sarah", .person)])
        let second = try harness.entry(mentions: [("Sarah", .person)])
        harness.indexer.sweep(in: harness.context)
        let sarah = try harness.entity("Sarah")
        #expect(sarah.linkCount == 2)

        let someoneElse = Entity(name: "Sarah Lee", key: "sarah lee", kind: .person)
        let link = try #require(harness.links(of: second).first)
        editor.repoint(link, to: someoneElse, addingAlias: false, in: harness.context)
        try harness.context.save()

        #expect(link.entityID == someoneElse.id)
        #expect(link.source == .user)
        #expect(sarah.linkCount == 1)
        #expect(someoneElse.linkCount == 1)
        #expect(someoneElse.confirmedByUser)
    }

    // Adding the alias is what fixes it for good: the next entry saying the same name lands
    // where the user put this one.
    @Test func repointingWithAnAliasFixesEveryLaterMention() throws {
        let first = try harness.entry(mentions: [("Sarah", .person)])
        harness.indexer.sweep(in: harness.context)

        let someoneElse = Entity(name: "Sarah Lee", key: "sarah lee", kind: .person)
        let link = try #require(harness.links(of: first).first)
        #expect(editor.repoint(link, to: someoneElse, addingAlias: true, in: harness.context) == .applied)
        try harness.context.save()
        #expect(someoneElse.aliases == ["Sarah"])

        try harness.entry(mentions: [("Sarah", .person)])
        harness.indexer.sweep(in: harness.context)

        #expect(someoneElse.linkCount == 2)
        #expect(try harness.entities().map(\.name) == ["Sarah Lee"], "the entity it was taken off is gone")
    }

    // MARK: - Suggestions from the store

    @Test func suggestionsSkipMergedAndHiddenEntities() throws {
        let (loser, winner) = try twoPeople()
        #expect(editor.suggestions(in: harness.context).count == 1)

        editor.merge(loser, into: winner, in: harness.context)
        #expect(editor.suggestions(in: harness.context).isEmpty, "a merged entity is not a duplicate")

        editor.unmerge(loser, in: harness.context)
        editor.setHidden(true, on: loser)
        #expect(editor.suggestions(in: harness.context).isEmpty, "nor is a hidden one")
    }
}

// The cases the first review of this code found, none of which the suite caught.
@MainActor
struct GraphRepairTests {
    let harness: GraphHarness
    let editor = GraphEditor(diagnostics: .disabled)

    init() throws {
        harness = try GraphHarness()
    }

    private func twoPeople() throws -> (Entity, Entity) {
        try harness.entry(entryDate: Date(timeIntervalSince1970: 1_000), mentions: [("Sarah K", .person)])
        try harness.entry(entryDate: Date(timeIntervalSince1970: 9_000), mentions: [("Sarah Kim", .person)])
        harness.indexer.sweep(in: harness.context)
        return (try harness.entity("Sarah K"), try harness.entity("Sarah Kim"))
    }

    // Running AI again on a merged entry used to rebuild its links without any record of
    // where they came from, which made the merge quietly permanent.
    @Test func aMergeSurvivesTheEntryBeingReindexed() throws {
        let (loser, winner) = try twoPeople()
        editor.merge(loser, into: winner, in: harness.context)
        try harness.context.save()
        #expect(winner.linkCount == 2)

        for entry in try harness.context.fetch(FetchDescriptor<Entry>()) {
            entry.insights?.generatedAt = Date(timeIntervalSince1970: 2_000)
        }
        harness.indexer.sweep(in: harness.context)
        #expect(winner.linkCount == 2, "the merged name still resolves to the winner")

        #expect(editor.unmerge(loser, in: harness.context))
        try harness.context.save()

        #expect(loser.linkCount == 1, "and the merge can still be undone")
        #expect(winner.linkCount == 1)
    }

    // A link stranded by an interrupted edit is only ever cleared at launch, and in steady
    // state nothing is stale, so the sweep has to do its cleanup regardless.
    @Test func theSweepRepairsCountersAndClearsStrandedLinksWithNothingStale() throws {
        let entry = try harness.entry(tags: ["nature"])
        harness.indexer.sweep(in: harness.context)
        let nature = try harness.entity("nature")
        #expect(harness.indexer.sweep(in: harness.context) == 0, "nothing is stale any more")

        // Something the app would never write, standing in for an interrupted edit.
        nature.linkCount = 99
        let stranded = EntityLink(surface: "ghost", kind: .tag)
        harness.context.insert(stranded)
        stranded.entryID = entry.id
        try harness.context.save()

        harness.indexer.sweep(in: harness.context)

        #expect(try harness.entity("nature").linkCount == 1, "the counter was repaired")
        #expect(try harness.context.fetchCount(FetchDescriptor<EntityLink>()) == 1, "the stranded link is gone")
    }

    // B into A, then A into C. Unmerging both must not leave two live entities answering to
    // the same name, which the resolver could then only guess between.
    @Test func unmergingAWholeChainLeavesNoTwoEntitiesSharingAName() throws {
        let (b, a) = try twoPeople()
        try harness.entry(mentions: [("Sarah Kim-Jones", .person)])
        harness.indexer.sweep(in: harness.context)
        let c = try harness.entity("Sarah Kim-Jones")

        editor.merge(b, into: a, in: harness.context)
        editor.merge(a, into: c, in: harness.context)
        editor.unmerge(a, in: harness.context)
        editor.unmerge(b, in: harness.context)
        try harness.context.save()

        #expect(b.isBrowsable && a.isBrowsable && c.isBrowsable)
        #expect(!a.aliases.contains("Sarah K"), "B took its own name back")
        #expect(c.aliases.isEmpty)
        let keys = [b, a, c].map(\.key)
        #expect(Set(keys).count == 3, "no two live entities answer to the same name")
    }

    // Changing the kind changes how the name is keyed, so the key has to move with it.
    @Test func changingTheKindRekeysTheName() throws {
        try harness.entry(mentions: [("Dr Kim", .other)])
        harness.indexer.sweep(in: harness.context)
        let entity = try harness.entity("Dr Kim")
        #expect(entity.key == "dr kim")

        editor.setKind(.person, on: entity, in: harness.context)
        try harness.context.save()

        #expect(entity.key == "kim", "an honorific only comes off a person's name")

        // And the next mention of them lands on the same entity rather than a duplicate.
        try harness.entry(mentions: [("Dr. Kim", .person)])
        harness.indexer.sweep(in: harness.context)
        #expect(try harness.entities().map(\.name) == ["Dr Kim"])
        #expect(entity.linkCount == 2)
    }

    // Merging moves links between entities, which marks their entries as changed. That is
    // not an edit to the entry, so it must not move updatedAt.
    @Test func mergingNeverStampsTheEntriesWhoseLinksMoved() throws {
        let (loser, winner) = try twoPeople()
        var before: [UUID: Date] = [:]
        for entry in try harness.context.fetch(FetchDescriptor<Entry>()) {
            entry.updatedAt = Date(timeIntervalSince1970: 100)
            before[entry.id] = entry.updatedAt
        }
        try harness.context.save()

        editor.merge(loser, into: winner, in: harness.context)
        editor.unmerge(loser, in: harness.context)

        for entry in try harness.context.fetch(FetchDescriptor<Entry>()) {
            #expect(entry.updatedAt == before[entry.id])
        }
    }

    @Test func repointingClearsTheGuessMarker() throws {
        try harness.entry(mentions: [("Sarah Kim", .person)])
        let second = try harness.entry(mentions: [("Sarah", .person)])
        harness.indexer.sweep(in: harness.context)
        let link = try #require(harness.links(of: second).first)
        #expect(link.inferred, "a bare first name was a guess")

        let someoneElse = Entity(name: "Sarah Lee", key: "sarah lee", kind: .person)
        editor.repoint(link, to: someoneElse, addingAlias: false, in: harness.context)

        #expect(!link.inferred, "the user said so, so it is no longer a guess")
    }
}
