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

    @Test func recentMentionsCoverThirtyDaysInclusive() {
        let map = snapshot([
            (UUID(), 70, [sarah], [], nil),
            (UUID(), 69, [tom], [], nil),
            (UUID(), 101, [ana], [], nil),
        ])
        let recent = MindMap.recentMentions(map, asOf: at(100))
        #expect(recent[sarah] == 1, "exactly 30 days back is in")
        #expect(recent[tom] == nil, "31 days back is out")
        #expect(recent[ana] == nil, "after asOf is out")
    }

    @Test func entryNodesKeepTheNewestEntriesTiedToEntitiesOnTheMap() {
        let e1 = UUID(), e2 = UUID(), e3 = UUID(), e4 = UUID()
        let map = snapshot([
            (e1, 1, [sarah, tom], [], nil),
            (e2, 2, [ana], [], nil),
            (e3, 3, [sarah], [], nil),
            (e4, 9, [sarah], [], nil),
        ])
        let result = MindMap.entryNodes(map, onMap: [sarah, tom], asOf: at(5), cap: 2)
        let ids = result.nodes.map { $0.id }
        #expect(ids == [e3, e1], "e2 has nothing on the map, e4 is after asOf")
        #expect(result.nodes.allSatisfy { $0.isEntry })
        #expect(result.nodes.last?.linkCount == 2)
        #expect(Set(result.edges.map(\.key)) == [
            EntityGraph.Edge(e3, sarah, weight: 1).key,
            EntityGraph.Edge(e1, sarah, weight: 1).key,
            EntityGraph.Edge(e1, tom, weight: 1).key,
        ])
        #expect(result.edges.allSatisfy { $0.recency > 0 && $0.recency <= 1 })
    }

    @Test func areasAndMoodsFollowAsOf() {
        let map = snapshot([
            (UUID(), 1, [sarah], [.work], .anxious),
            (UUID(), 5, [sarah], [.play], .joyful),
            (UUID(), 6, [sarah], [.play], .joyful),
        ])
        #expect(MindMap.primaryAreas(map, asOf: at(2))[sarah] == .work)
        #expect(MindMap.primaryAreas(map, asOf: at(9))[sarah] == .play)
        #expect(MindMap.moodAround(map, asOf: at(2))[sarah] == .anxious)
        #expect(MindMap.moodAround(map, asOf: at(9))[sarah] == .joyful)
    }

    @Test func earliestLinkIgnoresTheFuture() {
        let map = snapshot([(UUID(), 50, [sarah], [], nil), (UUID(), 3, [tom], [], nil)])
        #expect(map.earliestLinkDate(onOrBefore: at(10)) == at(3))
        #expect(map.earliestLinkDate(onOrBefore: at(1)) == nil)
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
        #expect(MindMap.mentionCounts(snapshot, asOf: at(2))[sarah.id] == 1, "the merged pair's links count one entry once")

        let builds = graph.snapshotBuildCount
        _ = graph.mapSnapshot(in: context)
        #expect(graph.snapshotBuildCount == builds)

        entry.insights?.setMoods(primary: .joyful, secondary: [])
        try context.save()
        graph.moodsEdited()
        #expect(graph.mapSnapshot(in: context).entries[entry.id]?.mood == .joyful)
        #expect(graph.snapshotBuildCount == builds + 1)
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
