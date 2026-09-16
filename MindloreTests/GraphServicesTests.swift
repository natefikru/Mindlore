import Foundation
import SwiftData
import Testing
@testable import Mindlore

@MainActor
struct GraphServicesTests {
    let harness: GraphHarness
    let log = DiagnosticsLog(fileURL: nil)
    let services: GraphServices

    init() throws {
        harness = try GraphHarness()
        services = GraphServices(diagnostics: log)
    }

    @Test func theIndexerAndEditorShareOneLog() {
        #expect(services.indexer.diagnostics === log)
        #expect(services.editor.diagnostics === log)
    }

    @Test func insightsWrittenIndexesTheEntryAndMovesTheRevision() throws {
        let entry = try harness.entry(mentions: [("Sarah", .person)])

        services.insightsWritten(for: entry, in: harness.context)
        try harness.context.save()

        #expect(try harness.entity("Sarah").linkCount == 1)
        #expect(services.revision == 1)
    }

    @Test func deletingAnEntryPrunesWhatOnlyItMentioned() throws {
        let entry = try harness.entry(mentions: [("Sarah", .person)])
        try harness.entry(tags: ["river"])
        harness.indexer.sweep(in: harness.context)

        Entry.delete(entry, in: harness.context)
        try harness.context.save()
        services.entriesDeleted(in: harness.context)
        try harness.context.save()

        #expect(try harness.entities().map(\.name) == ["river"])
        #expect(services.revision == 1)
    }

    // MARK: - 5c.4: unsure links

    @Test func unsureLinksListsTiedCandidatesByName() throws {
        let a = Entity(name: "Lewis", key: "lewis", kind: .person)
        let b = Entity(name: "Lewis", key: "lewis", kind: .person)
        harness.context.insert(a)
        harness.context.insert(b)
        try harness.context.save()
        let entry = try harness.entry(mentions: [("Lewis", .person)])
        services.insightsWritten(for: entry, in: harness.context)
        try harness.context.save()

        let unsure = services.unsureLinks(in: harness.context)

        #expect(unsure.count == 1)
        #expect(unsure[0].mention == MentionRef(entryID: entry.id, surface: "Lewis", kind: .person))
        #expect(Set(unsure[0].candidates.map(\.id)) == [a.id, b.id])
    }

    @Test func unsureLinksDropsAStaleCandidateAndResolvesThroughTheMergeWinner() throws {
        let a = Entity(name: "Lewis", key: "lewis", kind: .person)
        let b = Entity(name: "Lewis", key: "lewis", kind: .person)
        harness.context.insert(a)
        harness.context.insert(b)
        try harness.context.save()
        let entry = try harness.entry(mentions: [("Lewis", .person)])
        services.insightsWritten(for: entry, in: harness.context)
        try harness.context.save()

        // b merges into a third entity after the tie was recorded, before anyone answers "Which one?".
        let c = Entity(name: "Louis", key: "louis", kind: .person)
        harness.context.insert(c)
        try harness.context.save()
        _ = services.merge(b.id, into: c.id, in: harness.context)

        let unsure = services.unsureLinks(in: harness.context)

        #expect(unsure.count == 1)
        #expect(Set(unsure[0].candidates.map(\.id)) == [a.id, c.id], "resolves the stale merged id through its winner")
    }

    @Test func unsureLinksClearsALinkLeftWithOneLiveCandidate() throws {
        let a = Entity(name: "Lewis", key: "lewis", kind: .person)
        let b = Entity(name: "Lewis", key: "lewis", kind: .person)
        harness.context.insert(a)
        harness.context.insert(b)
        try harness.context.save()
        let entry = try harness.entry(mentions: [("Lewis", .person)])
        services.insightsWritten(for: entry, in: harness.context)
        try harness.context.save()

        // b hides after the tie was recorded: unsureLinks(in:) should quietly resolve, not offer a choice.
        services.setHidden(true, on: b.id, in: harness.context)

        let unsure = services.unsureLinks(in: harness.context)

        #expect(unsure.isEmpty)
        let link = try #require(harness.links(of: entry).first)
        #expect(link.unsureAmong.isEmpty)
    }

    @Test func repointingAnUnsureLinkToTheOtherCandidateClearsUnsureAmong() throws {
        let a = Entity(name: "Lewis", key: "lewis", kind: .person)
        let b = Entity(name: "Lewis", key: "lewis", kind: .person)
        harness.context.insert(a)
        harness.context.insert(b)
        try harness.context.save()
        let entry = try harness.entry(mentions: [("Lewis", .person)])
        services.insightsWritten(for: entry, in: harness.context)
        try harness.context.save()

        // Whichever of the two the resolver provisionally picked, repoint to the other one.
        let picked = try #require(harness.links(of: entry).first?.entityID)
        let other = picked == a.id ? b.id : a.id
        let mention = MentionRef(entryID: entry.id, surface: "Lewis", kind: .person)
        #expect(services.repoint(mention, to: .existing(other), addingAlias: false, in: harness.context) == .applied(other))

        let link = try #require(harness.links(of: entry).first)
        #expect(link.entityID == other)
        #expect(link.unsureAmong.isEmpty)
        #expect(services.unsureLinks(in: harness.context).isEmpty)
    }

    // The resolver's own provisional pick is a real answer too: confirming it must still clear
    // unsureAmong, or "Which one?" keeps asking about a mention the user already settled.
    @Test func repointingAnUnsureLinkToItsAlreadyPointedCandidateStillClearsUnsureAmong() throws {
        let a = Entity(name: "Lewis", key: "lewis", kind: .person)
        let b = Entity(name: "Lewis", key: "lewis", kind: .person)
        harness.context.insert(a)
        harness.context.insert(b)
        try harness.context.save()
        let entry = try harness.entry(mentions: [("Lewis", .person)])
        services.insightsWritten(for: entry, in: harness.context)
        try harness.context.save()

        let picked = try #require(harness.links(of: entry).first?.entityID)
        let mention = MentionRef(entryID: entry.id, surface: "Lewis", kind: .person)
        #expect(services.repoint(mention, to: .existing(picked), addingAlias: false, in: harness.context) == .applied(picked))

        let link = try #require(harness.links(of: entry).first)
        #expect(link.entityID == picked)
        #expect(link.unsureAmong.isEmpty)
        #expect(services.unsureLinks(in: harness.context).isEmpty)
    }

    @Test func deletingInsightsDropsTheirLinksAndRecounts() throws {
        let entry = try harness.entry(mentions: [("Sarah", .person)])
        try harness.entry(mentions: [("Sarah", .person)])
        harness.indexer.sweep(in: harness.context)

        services.insightsDeleted(for: entry, in: harness.context)
        try harness.context.save()

        #expect(entry.insights == nil)
        #expect(entry.graphIndexedAt == nil)
        #expect(harness.links(of: entry).isEmpty)
        #expect(try harness.entity("Sarah").linkCount == 1)
        #expect(services.revision == 1)
    }

    @Test func movingAnEntryDateMovesTheCounters() throws {
        let entry = try harness.entry(entryDate: Date(timeIntervalSince1970: 1_000), mentions: [("Sarah", .person)])
        harness.indexer.sweep(in: harness.context)

        let moved = Date(timeIntervalSince1970: 50_000)
        entry.entryDate = moved
        services.entryDateChanged(in: harness.context)

        let sarah = try harness.entity("Sarah")
        #expect(sarah.firstLinkedAt == moved)
        #expect(sarah.lastLinkedAt == moved)
        #expect(services.revision == 1)
    }

    // MARK: - 6.2: Mentioned with

    @Test func mentionedWithFindsAnEntitySharingAnEntry() throws {
        try harness.entry(mentions: [("Sarah", .person), ("Tom", .person)])
        harness.indexer.sweep(in: harness.context)
        let sarah = try harness.entity("Sarah")
        let tom = try harness.entity("Tom")

        let found = services.mentionedWith(of: sarah.id, in: harness.context)

        #expect(found.map(\.id) == [tom.id])
    }

    @Test func mentionedWithNeverShowsAHiddenPartner() throws {
        try harness.entry(mentions: [("Sarah", .person), ("Tom", .person)])
        harness.indexer.sweep(in: harness.context)
        let sarah = try harness.entity("Sarah")
        let tom = try harness.entity("Tom")
        services.setHidden(true, on: tom.id, in: harness.context)

        let found = services.mentionedWith(of: sarah.id, in: harness.context)

        #expect(found.isEmpty)
    }

    @Test func mentionedWithResolvesAMergedPartnerToItsWinner() throws {
        try harness.entry(mentions: [("Sarah", .person), ("Tom", .person)])
        harness.indexer.sweep(in: harness.context)
        let sarah = try harness.entity("Sarah")
        let tom = try harness.entity("Tom")
        let lewis = Entity(name: "Lewis", key: "lewis", kind: .person)
        harness.context.insert(lewis)
        try harness.context.save()
        _ = services.merge(tom.id, into: lewis.id, in: harness.context)

        let found = services.mentionedWith(of: sarah.id, in: harness.context)

        #expect(found.map(\.id) == [lewis.id])
    }

    @Test func mentionedWithOrdersByWeightAndRespectsTheLimit() throws {
        // Sarah and Tom share two entries; Sarah and Ana share one, so Tom outranks Ana.
        try harness.entry(mentions: [("Sarah", .person), ("Tom", .person)])
        try harness.entry(mentions: [("Sarah", .person), ("Tom", .person)])
        try harness.entry(mentions: [("Sarah", .person), ("Ana", .person)])
        harness.indexer.sweep(in: harness.context)
        let sarah = try harness.entity("Sarah")
        let tom = try harness.entity("Tom")
        let ana = try harness.entity("Ana")

        let found = services.mentionedWith(of: sarah.id, in: harness.context)
        #expect(found.map(\.id) == [tom.id, ana.id])

        let limited = services.mentionedWith(of: sarah.id, in: harness.context, limit: 1)
        #expect(limited.map(\.id) == [tom.id])
    }

    @Test func mentionedWithIsEmptyForAnEntityWithNothingToShare() throws {
        try harness.entry(mentions: [("Sarah", .person)])
        harness.indexer.sweep(in: harness.context)
        let sarah = try harness.entity("Sarah")

        #expect(services.mentionedWith(of: sarah.id, in: harness.context).isEmpty)
    }
}

struct NameMatchingTests {
    @Test(arguments: [
        ("sarah", "Walked with Sarah today.", true),
        ("Sarah", "sarah's dog barked", true),
        ("Sarah", "Sarahs and Mosarah", false),
        ("Sarah Kim", "saw sarah  kim", false),
        ("Dr. Lee", "met Dr. Lee.", true),
        ("", "anything", false),
    ])
    func findsWholeWordsIgnoringCase(name: String, text: String, found: Bool) {
        #expect((NameMatching.range(of: name, in: text) != nil) == found)
    }

    @Test func findsEveryOccurrenceInOrder() {
        let text = "Sarah called. Later sarah came over, then SARAH left."
        let found = NameMatching.ranges(of: "Sarah", in: text).map { String(text[$0]) }
        #expect(found == ["Sarah", "sarah", "SARAH"])
    }
}
