import Foundation
import SwiftData
import Testing
@testable import Mindlore

// The first launch after the graph ships, on a journal written by the build before it:
// Fixtures/v2-store.bundle is 300 entries with insights from main at 0678525, with the name
// variants a real journal has ("Sarah", "sarah", "Sarah's", "Dr. Patel", "Work").
@MainActor
struct GraphUpgradeTests {
    private final class BundleToken {}

    private func copyOfFixture() throws -> (store: URL, cleanup: () -> Void) {
        let source = try #require(Bundle(for: BundleToken.self).url(forResource: "v2-store", withExtension: "bundle"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.copyItem(at: source, to: directory)
        return (directory.appendingPathComponent("entries.store"), { try? FileManager.default.removeItem(at: directory) })
    }

    private func milliseconds(_ work: () -> Void) -> Int {
        let start = Date.now
        work()
        return Int(Date.now.timeIntervalSince(start) * 1000)
    }

    @Test func anExistingJournalIsIndexedOnFirstLaunch() throws {
        let fixture = try copyOfFixture()
        defer { fixture.cleanup() }
        let container = try ModelContainerFactory.make(.file(fixture.store))
        let context = container.mainContext
        let indexer = GraphIndexer(diagnostics: .disabled)

        // The upgrade itself: everything from before is there, and nothing is indexed yet.
        let entries = try context.fetch(FetchDescriptor<Entry>())
        try #require(entries.count == 300)
        #expect(entries.allSatisfy { $0.insights != nil && $0.graphIndexedAt == nil })
        #expect(try context.fetchCount(FetchDescriptor<Entity>()) == 0)
        let editedAt = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.updatedAt) })

        var indexed = 0
        let sweepMS = milliseconds { indexed = indexer.sweep(in: context) }
        #expect(indexed == 300)

        // Nobody's journal looks edited today because of it.
        for entry in try context.fetch(FetchDescriptor<Entry>()) {
            #expect(entry.updatedAt == editedAt[entry.id])
            #expect(entry.graphIndexedAt == entry.insights?.generatedAt)
        }

        // Spelling variants collapse; different names do not.
        let entities = try context.fetch(FetchDescriptor<Entity>())
        func count(_ key: String, _ kind: EntityKind) -> Int { entities.filter { $0.key == key && $0.kind == kind }.count }
        #expect(count("sarah", .person) <= 1, "Sarah, sarah and Sarah's are one person")
        #expect(count("mom", .person) == 1)
        #expect(count("patel", .person) == 1, "Dr. Patel and Dr Patel are one person")
        #expect(count("work", .tag) == 1)
        #expect(count("career anxiety", .theme) == 1)
        #expect(count("harbor coffee", .place) == 1)
        #expect(entities.filter { $0.key == "denver" }.count == 1, "Denver typed as place or other is one thing")
        let people = entities.filter { $0.kind == .person }
        #expect((10...12).contains(people.count), "twelve name forms, some of which the first-name rule joins")

        // Every link counted, and a second launch has nothing to do.
        let links = indexer.allLinks(in: context)
        #expect(entities.reduce(0) { $0 + $1.linkCount } == links.count)
        var again = -1
        let secondMS = milliseconds { again = indexer.sweep(in: context) }
        #expect(again == 0)

        let recountMS = milliseconds { indexer.recount(in: context) }
        var vocabulary: InsightsPromptBuilder.JournalVocabulary?
        let vocabularyMS = milliseconds { vocabulary = indexer.vocabulary(in: context) }
        #expect(vocabulary?.tags.isEmpty == false)
        let suggestions = GraphEditor(diagnostics: .disabled).suggestions(in: context)

        print("""
        UPGRADE 300 entries: first sweep \(sweepMS) ms, second \(secondMS) ms, recount \(recountMS) ms, vocabulary \(vocabularyMS) ms
        UPGRADE \(links.count) links, \(entities.count) entities: \(Dictionary(grouping: entities, by: \.kindRaw).mapValues(\.count).sorted { $0.key < $1.key })
        UPGRADE people: \(people.map(\.name).sorted())
        UPGRADE \(suggestions.count) duplicate suggestions
        """)
    }

    // The first launch for a journal ten times the size. Printed rather than tightly bounded:
    // the simulator's speed says little about a phone's, and the number is what matters.
    @Test func aLargeJournalIsIndexedInReasonableTime() throws {
        let harness = try GraphHarness()
        let tags = (0..<60).map { "tag \($0)" }
        let names = (0..<200).map { "Person Number \($0)" }
        for index in 0..<3_000 {
            try harness.entry(
                entryDate: Date(timeIntervalSince1970: Double(index) * 3_600),
                tags: [tags[index % 60], tags[(index * 7) % 60]],
                themes: ["theme \(index % 25)"],
                mentions: [(names[index % 200], .person), (names[(index * 13) % 200], .person)]
            )
        }

        var indexed = 0
        let sweepMS = milliseconds { indexed = harness.indexer.sweep(in: harness.context) }
        let recountMS = milliseconds { harness.indexer.recount(in: harness.context) }
        print("UPGRADE 3000 entries: first sweep \(sweepMS) ms, recount \(recountMS) ms")

        #expect(indexed == 3_000)
        // About 7 s on the simulator once the sweep shares one fetch; it was 119 s when every
        // entry fetched every link. The bound catches a slide back to that, not jitter.
        #expect(sweepMS < 30_000, "a first launch this slow is a hang to the user")
    }
}
