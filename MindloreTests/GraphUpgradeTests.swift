import Foundation
import SwiftData
import Testing
@testable import Mindlore

// Indexing a whole journal at once, the way the launch sweep does.
@MainActor
struct GraphUpgradeTests {
    private func milliseconds(_ work: () -> Void) -> Int {
        let start = Date.now
        work()
        return Int(Date.now.timeIntervalSince(start) * 1000)
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

@MainActor
struct ChunkedSweepTests {
    let harness: GraphHarness

    init() throws {
        harness = try GraphHarness()
    }

    private func journal(_ count: Int) throws {
        for index in 0..<count {
            try harness.entry(tags: ["tag \(index % 7)"], mentions: [("Person \(index % 11)", .person)])
        }
    }

    // The launch path has to build exactly the graph the one-pass sweep does.
    @Test func chunkedAndOnePassSweepsBuildTheSameGraph() async throws {
        try journal(250)
        let other = try GraphHarness()
        for index in 0..<250 {
            try other.entry(tags: ["tag \(index % 7)"], mentions: [("Person \(index % 11)", .person)])
        }

        let chunked = await harness.indexer.sweep(in: harness.context, chunkSize: 40) { _, _ in }
        let onePass = other.indexer.sweep(in: other.context)

        #expect(chunked == 250 && onePass == 250)
        func shape(_ h: GraphHarness) throws -> [String] {
            try h.entities().map { "\($0.kindRaw) \($0.key) \($0.linkCount)" }.sorted()
        }
        #expect(try shape(harness) == shape(other))
        #expect(harness.indexer.allLinks(in: harness.context).count == other.indexer.allLinks(in: other.context).count)
    }

    @Test func progressOnlyMovesForwardAndEndsAtTheTotal() async throws {
        try journal(250)
        var reports: [(Int, Int)] = []

        await harness.indexer.sweep(in: harness.context, chunkSize: 100) { reports.append(($0, $1)) }

        #expect(reports.map(\.0) == [0, 100, 200, 250])
        #expect(reports.allSatisfy { $0.1 == 250 })
    }

    @Test func nothingStaleReportsNothingToDo() async throws {
        try journal(3)
        harness.indexer.sweep(in: harness.context)
        var reports: [(Int, Int)] = []

        let indexed = await harness.indexer.sweep(in: harness.context) { reports.append(($0, $1)) }

        #expect(indexed == 0)
        #expect(reports.map(\.1) == [0])
    }

    // Other work can run in the pause between chunks. An entry deleted there is skipped, and
    // one indexed there by an insights run is simply indexed again, to the same result.
    @Test func workBetweenChunksIsHandled() async throws {
        try journal(30)
        let entries = try harness.context.fetch(FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.createdAt)]))
        let doomed = entries[25]
        let early = entries[20]
        var interfered = false

        let indexed = await harness.indexer.sweep(in: harness.context, chunkSize: 10) { done, _ in
            guard done == 10, !interfered else { return }
            interfered = true
            Entry.delete(doomed, in: harness.context)
            harness.indexer.index(early, in: harness.context)
            try? harness.context.save()
        }

        #expect(indexed == 30)
        #expect(try harness.context.fetchCount(FetchDescriptor<Entry>()) == 29)
        #expect(harness.links(of: early).count == 2, "indexed twice, linked once per value")
        let links = harness.indexer.allLinks(in: harness.context)
        #expect(!links.contains { $0.entryID == doomed.id })
        #expect(try harness.entities().reduce(0) { $0 + $1.linkCount } == links.count)
    }

    // Clearing a stranded link marks its entry as changed, which is not an edit either.
    @Test func repairingAStrandedLinkNeverStampsItsEntry() async throws {
        let entry = try harness.entry(tags: ["nature"])
        harness.indexer.sweep(in: harness.context)
        entry.updatedAt = Date(timeIntervalSince1970: 100)
        let stranded = EntityLink(surface: "ghost", kind: .tag)
        harness.context.insert(stranded)
        stranded.entryID = entry.id
        try harness.context.save()

        await harness.indexer.sweep(in: harness.context) { _, _ in }

        #expect(harness.indexer.allLinks(in: harness.context).count == 1)
        #expect(entry.updatedAt == Date(timeIntervalSince1970: 100))
    }

    @Test func aLargeJournalStaysResponsiveWhileIndexed() async throws {
        for index in 0..<3_000 {
            try harness.entry(tags: ["tag \(index % 60)"], mentions: [("Person Number \(index % 200)", .person)])
        }
        var reports = 0
        let start = Date.now

        let indexed = await harness.indexer.sweep(in: harness.context) { _, _ in reports += 1 }

        let ms = Int(Date.now.timeIntervalSince(start) * 1000)
        print("UPGRADE 3000 entries chunked: \(ms) ms over \(reports - 1) chunks")
        #expect(indexed == 3_000)
        #expect(reports == 31, "one report before the first chunk and one after each of 30")
        #expect(ms < 30_000)
    }
}

struct GraphIndexingProgressTests {
    @Test func onlyALargeBacklogIsShown() {
        #expect(GraphIndexingProgress.visible(done: 0, total: 199) == nil, "over too fast to be worth a screen")
        #expect(GraphIndexingProgress.visible(done: 0, total: 200) == .init(done: 0, total: 200))
        #expect(GraphIndexingProgress.visible(done: 150, total: 3_000)?.fraction == 0.05)
        #expect(GraphIndexingProgress.visible(done: 3_000, total: 3_000) == nil, "gone once finished")
        #expect(GraphIndexingProgress.visible(done: 0, total: 0) == nil)
    }
}
