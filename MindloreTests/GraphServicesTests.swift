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
