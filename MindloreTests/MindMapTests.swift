import Foundation
import SwiftData
import Testing
@testable import Mindlore

struct MindMapTests {
    private let sarah = UUID(), tom = UUID(), ana = UUID()
    private func at(_ day: Double) -> Date { Date(timeIntervalSince1970: day * 86_400) }

    private func snapshot(_ entries: [(id: UUID, day: Double, mentions: [UUID], areas: [LifeArea], mood: MoodCategory?)]) -> MindMapSnapshot {
        let entities: [UUID: MindMapSnapshot.EntityInfo] = [
            sarah: .init(id: sarah, name: "Sarah", kind: .person),
            tom: .init(id: tom, name: "Tom", kind: .person),
            ana: .init(id: ana, name: "Lisbon", kind: .place),
        ]
        var links: [EntityGraph.LinkInput] = []
        var infos: [UUID: MindMapSnapshot.EntryInfo] = [:]
        for entry in entries {
            infos[entry.id] = .init(id: entry.id, date: at(entry.day), areas: entry.areas, mood: entry.mood)
            links += entry.mentions.map { .init(entryID: entry.id, entityID: $0, entryDate: at(entry.day)) }
        }
        return MindMapSnapshot(entities: entities, links: links, entries: infos)
    }

    @Test func graphCountsAndSizesByMentionsUpToAsOf() {
        let map = snapshot([
            (UUID(), 1, [sarah, tom], [], nil),
            (UUID(), 5, [sarah], [], nil),
            (UUID(), 9, [ana], [], nil),
        ])
        let early = MindMap.graph(map, kinds: nil, minimumLinkCount: 1, asOf: at(2))
        #expect(Set(early.nodes.map(\.id)) == [sarah, tom])
        #expect(early.nodes.allSatisfy { $0.linkCount == 1 })
        #expect(early.edges.count == 1)

        let late = MindMap.graph(map, kinds: nil, minimumLinkCount: 1, asOf: at(10))
        #expect(late.nodes.first { $0.id == sarah }?.linkCount == 2)
        #expect(late.nodes.first?.id == sarah, "biggest first, in layout order")
        #expect(late.names[ana] == "Lisbon")

        let places = MindMap.graph(map, kinds: [.place], minimumLinkCount: 1, asOf: at(10))
        #expect(places.nodes.map(\.id) == [ana])
    }

    // A window draws only what the stretch holds: sizes are its counts, and an edge needs an entry
    // inside it, so an old shared entry doesn't tie two names the window has apart.
    @Test func aWindowDrawsOnlyItsOwnEntries() {
        let map = snapshot([
            (UUID(), 10, [sarah, tom], [], nil),
            (UUID(), 90, [sarah], [], nil),
            (UUID(), 95, [sarah, ana], [], nil),
            (UUID(), 96, [tom], [], nil),
        ])
        let month = MindMap.graph(map, window: .month, kinds: nil, minimumLinkCount: 1, asOf: at(100))
        #expect(Set(month.nodes.map(\.id)) == [sarah, tom, ana])
        #expect(month.nodes.first { $0.id == sarah }?.linkCount == 2)
        #expect(month.edges.map(\.key) == [EntityGraph.Edge(sarah, ana, weight: 1).key], "Sarah and Tom last shared an entry ninety days ago")

        let all = MindMap.graph(map, window: .all, kinds: nil, minimumLinkCount: 1, asOf: at(100))
        #expect(all.nodes.first { $0.id == sarah }?.linkCount == 3)
        #expect(all.edges.count == 2)
    }

    @Test func aLargeJournalNeedsTwoMentionsToDraw() {
        #expect(MindMap.minimumMentions(browsableCount: MindMap.largeJournal - 1) == 1)
        #expect(MindMap.minimumMentions(browsableCount: MindMap.largeJournal) == 2)
    }

    @Test func areasFollowAsOf() {
        let map = snapshot([
            (UUID(), 1, [sarah], [.work], .anxious),
            (UUID(), 5, [sarah], [.play], .joyful),
            (UUID(), 6, [sarah], [.play], .joyful),
        ])
        #expect(MindMap.primaryAreas(map, asOf: at(2))[sarah] == .work)
        #expect(MindMap.primaryAreas(map, asOf: at(9))[sarah] == .play)
    }
}

@MainActor
struct MindMapSnapshotTests {
    private func at(_ day: Double) -> Date { Date(timeIntervalSince1970: day * 86_400) }

    @Test func snapshotResolvesMergesSkipsHiddenAndIsCachedPerRevision() throws {
        let harness = try GraphHarness()
        let graph = GraphServices(diagnostics: .disabled)
        let context = harness.context
        let entry = try harness.entry("Sarah, Tom, and Ana.", entryDate: at(1), mentions: [("Sarah", .person), ("Tom", .person), ("Ana", .person)])
        entry.insights?.setMoods(primary: .stressed, secondary: [], editedByUser: false)
        entry.insights?.areas = [.work]
        try context.save()
        graph.indexer.sweep(in: context)
        let sarah = try harness.entity("Sarah"), tom = try harness.entity("Tom"), ana = try harness.entity("Ana")
        _ = graph.merge(tom.id, into: sarah.id, in: context)
        graph.setHidden(true, on: ana.id, in: context)

        let snapshot = graph.mapSnapshot(in: context)
        #expect(Set(snapshot.entities.keys) == [sarah.id])
        #expect(snapshot.links.allSatisfy { $0.entityID == sarah.id })
        #expect(snapshot.entries[entry.id]?.mood == .anxious)
        #expect(snapshot.entries[entry.id]?.areas == [.work])
        #expect(MindStats.counts(snapshot, window: .all, asOf: at(2))[sarah.id] == 1, "the merged pair's links count one entry once")

        let builds = graph.snapshotBuildCount
        _ = graph.mapSnapshot(in: context)
        #expect(graph.snapshotBuildCount == builds)

        entry.insights?.setMoods(primary: .joyful, secondary: [])
        try context.save()
        graph.moodsEdited()
        #expect(graph.mapSnapshot(in: context).entries[entry.id]?.mood == .joyful)
        #expect(graph.snapshotBuildCount == builds + 1)
    }

    // The launch sweep writes links behind GraphServices' back; its end bumps the revision so a
    // snapshot cached before it is rebuilt.
    @Test func theLaunchSweepRefreshesACachedSnapshot() async throws {
        let harness = try GraphHarness()
        let graph = GraphServices(diagnostics: .disabled)
        try harness.entry(mentions: [("Sarah", .person)])
        #expect(graph.mapSnapshot(in: harness.context).links.isEmpty)
        _ = await graph.indexer.sweep(in: harness.context) { _, _ in }
        graph.sweepFinished()
        #expect(graph.mapSnapshot(in: harness.context).links.count == 1)
    }

    @Test func aFutureDatedMentionDoesNotCountOnTheLiveMapYet() throws {
        let harness = try GraphHarness()
        let graph = GraphServices(diagnostics: .disabled)
        try harness.entry(entryDate: .now.addingTimeInterval(-86_400), mentions: [("Sarah", .person)])
        try harness.entry(entryDate: .now.addingTimeInterval(5 * 86_400), mentions: [("Sarah", .person)])
        graph.indexer.sweep(in: harness.context)

        let data = graph.globalGraph(kinds: nil, minimumLinkCount: 1, in: harness.context)
        #expect(data.nodes.first?.linkCount == 1)
    }
}
