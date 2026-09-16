import Foundation
import SwiftData
import Testing
@testable import Mindlore

@MainActor
struct EntityPageEditTests {
    let harness: BioHarness
    var services: GraphServices { harness.services }
    var context: ModelContext { harness.context }

    init() throws {
        harness = try BioHarness()
    }

    // MARK: - Kind

    @Test func kindsStayInTheirFamily() {
        #expect(GraphEditor.kinds(changeableFrom: .person) == [.person, .place, .organization, .project, .event, .other])
        #expect(GraphEditor.kinds(changeableFrom: .other) == [.person, .place, .organization, .project, .event, .other])
        #expect(GraphEditor.kinds(changeableFrom: .tag) == [.tag, .theme])
        #expect(GraphEditor.kinds(changeableFrom: .theme) == [.tag, .theme])
    }

    @Test func aPersonCannotBecomeATag() throws {
        try harness.entry("Sarah called.", mentions: [("Sarah", .person)])
        let sarah = try harness.entity("Sarah")

        #expect(services.setKind(.tag, on: sarah.id, in: context) == .applied)

        #expect(sarah.kind == .person)
        #expect(!sarah.kindEditedByUser)
    }

    @Test func aKindChangeThatLandsOnAnotherNameCollides() throws {
        try harness.entry("Went to Paris.", mentions: [("Paris", .place)])
        try harness.entry("Paris the friend called.", mentions: [("Paris", .person)])
        let place = try #require(try harness.graph.entities().first { $0.kind == .place })
        let person = try #require(try harness.graph.entities().first { $0.kind == .person })

        #expect(services.setKind(.person, on: place.id, in: context) == .collides(with: person.id))

        #expect(place.kind == .place, "nothing changes until the user decides")
        #expect(services.revision == 0)
    }

    @Test func aKindChangeSaves() throws {
        try harness.entry("Acme called.", mentions: [("Acme", .other)])
        let acme = try harness.entity("Acme")

        #expect(services.setKind(.organization, on: acme.id, in: context) == .applied)

        #expect(acme.kind == .organization)
        #expect(!context.hasChanges)
        #expect(services.revision == 1)
    }

    // MARK: - Names

    @Test func aRenameSavesAndACollisionChangesNothing() throws {
        try harness.entry("Sarah K called.", mentions: [("Sarah K", .person)])
        try harness.entry("Tom called.", mentions: [("Tom", .person)])
        let sarah = try harness.entity("Sarah K")
        let tom = try harness.entity("Tom")

        #expect(services.rename(sarah.id, to: "Sarah Kim", in: context) == .applied)
        #expect(!context.hasChanges)
        #expect(services.rename(tom.id, to: "sarah kim", in: context) == .collides(with: sarah.id))
        #expect(tom.name == "Tom")
        #expect(services.revision == 1)
    }

    @Test func aRenameThroughServicesCanKeepTheOldNameAsAnAlias() throws {
        try harness.entry("Lewis called.", mentions: [("Lewis", .person)])
        let lewis = try harness.entity("Lewis")

        #expect(services.rename(lewis.id, to: "Luis", keepingOldNameAsAlias: true, in: context) == .applied)

        #expect(lewis.name == "Luis")
        #expect(lewis.aliases == ["Lewis"])
        #expect(!context.hasChanges)
    }

    @Test func aliasesAddAndRemove() throws {
        try harness.entry("Mom called.", mentions: [("Sarah", .person)])
        let sarah = try harness.entity("Sarah")

        #expect(services.addAlias("Mom", to: sarah.id, in: context) == .applied)
        #expect(sarah.aliases == ["Mom"])
        services.removeAlias("Mom", from: sarah.id, in: context)
        #expect(sarah.aliases.isEmpty)
        #expect(!context.hasChanges)
        #expect(services.revision == 2)
    }

    @Test func hidingSaves() throws {
        try harness.entry("Sarah called.", mentions: [("Sarah", .person)])
        let sarah = try harness.entity("Sarah")

        services.setHidden(true, on: sarah.id, in: context)
        #expect(sarah.hidden)
        #expect(!context.hasChanges)
        services.setHidden(false, on: sarah.id, in: context)
        #expect(!sarah.hidden)
    }

    // MARK: - Merge

    @Test func mergingReturnsTheWinnerAndUndoRestores() throws {
        try harness.entry("Sarah K called.", mentions: [("Sarah K", .person)])
        try harness.entry("Sarah Kim called.", mentions: [("Sarah Kim", .person)])
        let loser = try harness.entity("Sarah K")
        let winner = try harness.entity("Sarah Kim")

        #expect(services.merge(loser.id, into: winner.id, in: context) == winner.id)
        #expect(winner.linkCount == 2)
        #expect(services.revision == 1)

        services.unmerge(loser.id, in: context)
        #expect(!loser.isMerged)
        #expect(winner.linkCount == 1)
        #expect(services.revision == 2)
    }

    @Test func mergingIntoSelfIsRefused() throws {
        try harness.entry("Sarah called.", mentions: [("Sarah", .person)])
        let sarah = try harness.entity("Sarah")

        #expect(services.merge(sarah.id, into: sarah.id, in: context) == nil)
        #expect(services.revision == 0)
    }

    // The user picked it, so it comes back into view.
    @Test func mergingIntoAHiddenEntityUnhidesIt() throws {
        try harness.entry("Sarah K called.", mentions: [("Sarah K", .person)])
        try harness.entry("Sarah Kim called.", mentions: [("Sarah Kim", .person)])
        let winner = try harness.entity("Sarah Kim")
        services.setHidden(true, on: winner.id, in: context)

        services.merge(try harness.entity("Sarah K").id, into: winner.id, in: context)

        #expect(!winner.hidden)
    }

    // The Review list's "Not the same": the pair stops showing up as a suggestion.
    @Test func markNotSameRemovesThePairFromSuggestions() throws {
        try harness.entry("Sarah K called.", mentions: [("Sarah K", .person)])
        try harness.entry("Sarah Kim called.", mentions: [("Sarah Kim", .person)])
        let a = try harness.entity("Sarah K")
        let b = try harness.entity("Sarah Kim")
        #expect(services.editor.suggestions(in: context).contains { Set([$0.a, $0.b]) == Set([a.id, b.id]) })

        services.markNotSame(a.id, b.id, in: context)

        #expect(a.notSameAs == [b.id])
        #expect(b.notSameAs == [a.id])
        #expect(!context.hasChanges)
        #expect(services.revision == 1)
        #expect(!services.editor.suggestions(in: context).contains { Set([$0.a, $0.b]) == Set([a.id, b.id]) })
    }

    @Test func likelySameScoresOneEntityAgainstTheRest() {
        func candidate(_ key: String, _ kind: EntityKind = .person, notSame: [UUID] = []) -> EntityMatcher.Candidate {
            .init(id: UUID(), key: key, kind: kind, linkCount: 1, notSameAs: notSame)
        }
        let kim = candidate("sarah kim")
        let me = candidate("sarah", notSame: [kim.id])
        let lee = candidate("sarah lee")
        let tom = candidate("tom")
        let tag = candidate("sarah", .tag)

        #expect(EntityMatcher.likelySame(as: me, among: [me, kim, lee, tom, tag]) == [lee.id])
    }

    @Test func mergeCandidatesPutLikelyDuplicatesAndTheSameKindFirst() {
        let me = UUID()
        func candidate(_ name: String, _ kind: EntityKind, links: Int = 1, suggested: Bool = false) -> MergeCandidates.Candidate {
            .init(id: UUID(), name: name, kind: kind, linkCount: links, suggested: suggested)
        }
        let self_ = MergeCandidates.Candidate(id: me, name: "Sarah", kind: .person, linkCount: 3, suggested: false)
        let river = candidate("river", .tag, links: 9)
        let tom = candidate("Tom", .person, links: 2)
        let amy = candidate("Amy", .person, links: 2)
        let kim = candidate("Sarah Kim", .person, suggested: true)

        let ordered = MergeCandidates.order([river, self_, tom, amy, kim], excluding: me, kind: .person, search: "")
        #expect(ordered.map(\.name) == ["Sarah Kim", "Amy", "Tom", "river"])

        let searched = MergeCandidates.order([river, tom, kim], excluding: me, kind: .person, search: " sar ")
        #expect(searched.map(\.name) == ["Sarah Kim"])
    }

    // MARK: - Repoint

    private func guessedSarah() throws -> (Entry, MentionRef) {
        let entry = try harness.entry("sarah came by.", mentions: [("sarah", .person)])
        return (entry, MentionRef(entryID: entry.id, surface: "sarah", kind: .person))
    }

    @Test func repointingToAnExistingEntityMovesOnlyThatMention() throws {
        let (entry, mention) = try guessedSarah()
        try harness.entry("Tom called.", mentions: [("Tom", .person)])
        let tom = try harness.entity("Tom")

        #expect(services.repoint(mention, to: .existing(tom.id), addingAlias: false, in: context) == .applied(tom.id))

        let link = try #require(harness.graph.links(of: entry).first)
        #expect(link.entityID == tom.id)
        #expect(link.source == .user)
        #expect(tom.linkCount == 2)
        #expect(tom.aliases.isEmpty)
        #expect(services.revision == 1)
    }

    @Test func repointingToANewNameCreatesIt() throws {
        let (entry, mention) = try guessedSarah()

        let outcome = services.repoint(mention, to: .new(name: " Sarah Lee "), addingAlias: true, in: context)

        let lee = try harness.entity("Sarah Lee")
        #expect(outcome == .applied(lee.id))
        #expect(lee.kind == .person)
        #expect(lee.aliases == ["sarah"])
        #expect(harness.graph.links(of: entry).first?.entityID == lee.id)
    }

    // A typed name that already exists goes to that entity instead of a twin.
    @Test func aTypedNameThatExistsIsUsed() throws {
        let (_, mention) = try guessedSarah()
        try harness.entry("Tom called.", mentions: [("Tom", .person)])
        let tom = try harness.entity("Tom")

        #expect(services.repoint(mention, to: .new(name: "tom"), addingAlias: false, in: context) == .applied(tom.id))
        #expect(try harness.graph.entities().filter { $0.key == "tom" }.count == 1)
    }

    @Test func aMentionRegeneratedAwayReportsTheChange() throws {
        let (entry, mention) = try guessedSarah()
        try harness.entry("Tom called.", mentions: [("Tom", .person)])
        let tom = try harness.entity("Tom")
        // Generate again: the old links go, and the new insights name someone else.
        entry.insights?.mentions = [Mention(name: "Sara", kindRaw: MentionKind.person.rawValue)]
        entry.insights?.generatedAt = Date(timeIntervalSince1970: 2_000)
        services.insightsWritten(for: entry, in: context)
        try context.save()

        #expect(services.repoint(mention, to: .existing(tom.id), addingAlias: true, in: context) == .mentionChanged)
        #expect(tom.aliases.isEmpty)
        #expect(tom.linkCount == 1)
    }

    // The user just said this is not the entity it came from, so the name staying there is
    // reported, never offered as a merge.
    @Test func theNameStayingWithWhereItCameFromIsNotAMergeOffer() throws {
        let (entry, mention) = try guessedSarah()
        let sarah = try harness.entity("sarah")
        try harness.entry("Tom called.", mentions: [("Tom", .person)])
        let tom = try harness.entity("Tom")
        try harness.entry("Sarah again.", mentions: [("Sarah", .person)])

        let outcome = services.repoint(mention, to: .existing(tom.id), addingAlias: true, in: context)

        #expect(outcome == .aliasStaysWith(entityID: tom.id, owner: sarah.id))
        #expect(harness.graph.links(of: entry).first?.entityID == tom.id)
    }

    @Test func aNameAThirdEntityAnswersToIsReportedAsACollision() throws {
        let (_, mention) = try guessedSarah()
        try harness.entry("Tom called.", mentions: [("Tom", .person)])
        try harness.entry("Amy called.", mentions: [("Amy", .person)])
        let tom = try harness.entity("Tom")
        let amy = try harness.entity("Amy")
        // Amy answers to "sarah" too, and the entity the mention came from is pruned.
        #expect(services.addAlias("Sarah", to: amy.id, in: context) == .collides(with: try harness.entity("sarah").id))
        amy.aliases.append("sarah")
        try context.save()

        let outcome = services.repoint(mention, to: .existing(tom.id), addingAlias: true, in: context)

        #expect(outcome == .aliasCollides(entityID: tom.id, with: amy.id))
    }

    // Labels never meet named kinds, in the collision check as in the resolver.
    @Test func becomingOtherBesideATagIsNotACollision() throws {
        try harness.entry("Work was long.", mentions: [("Work", .project)], tags: ["work"])
        let project = try #require(try harness.graph.entities().first { $0.kind == .project })

        #expect(services.setKind(.other, on: project.id, in: context) == .applied)
        #expect(project.kind == .other)
        #expect(services.editor.entity(answering: "work", kind: .other, in: context)?.id == project.id)
    }

    @Test func repointChoicesFollowTheResolversKindRule() {
        #expect(RepointChoices.accepts(.person, for: .person))
        #expect(RepointChoices.accepts(.other, for: .person))
        #expect(!RepointChoices.accepts(.place, for: .person))
        #expect(RepointChoices.accepts(.place, for: .other))
        #expect(!RepointChoices.accepts(.tag, for: .other))
        #expect(RepointChoices.accepts(.tag, for: .tag))
        #expect(!RepointChoices.accepts(.theme, for: .tag))
    }
}
