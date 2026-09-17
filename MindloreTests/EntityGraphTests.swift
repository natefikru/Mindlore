import Foundation
import Testing
@testable import Mindlore

struct EntityGraphTests {
    private func link(_ entry: UUID, _ entity: UUID, _ date: Date) -> EntityGraph.LinkInput {
        .init(entryID: entry, entityID: entity, entryDate: date)
    }

    private let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    @Test func twoEntitiesInOneEntryEdgeAtFullWeight() {
        let entry = UUID()
        let a = UUID(), b = UUID()
        let edges = EntityGraph.build(links: [link(entry, a, now), link(entry, b, now)], asOf: now)
        #expect(edges.count == 1)
        #expect(abs(edges[0].weight - 1.0) < 0.0001)
    }

    @Test func decayAtOneHalfLifeIsHalf() {
        let entry = UUID()
        let a = UUID(), b = UUID()
        let halfLife: TimeInterval = 90 * 86400
        let entryDate = now.addingTimeInterval(-halfLife)
        let edges = EntityGraph.build(links: [link(entry, a, entryDate), link(entry, b, entryDate)], asOf: now, halfLife: halfLife)
        #expect(edges.count == 1)
        #expect(abs(edges[0].weight - 0.5) < 0.0001)
    }

    @Test func decayAtTwoHalfLivesIsQuarter() {
        let entry = UUID()
        let a = UUID(), b = UUID()
        let halfLife: TimeInterval = 90 * 86400
        let entryDate = now.addingTimeInterval(-2 * halfLife)
        let edges = EntityGraph.build(links: [link(entry, a, entryDate), link(entry, b, entryDate)], asOf: now, halfLife: halfLife)
        #expect(edges.count == 1)
        #expect(abs(edges[0].weight - 0.25) < 0.0001)
    }

    @Test func threeEntitiesProduceEveryPair() {
        let entry = UUID()
        let a = UUID(), b = UUID(), c = UUID()
        let edges = EntityGraph.build(links: [link(entry, a, now), link(entry, b, now), link(entry, c, now)], asOf: now)
        #expect(edges.count == 3)
        for edge in edges {
            #expect(abs(edge.weight - 1.0) < 0.0001)
        }
    }

    @Test func sameEntryPairAcrossTwoEntriesSumsWeight() {
        let entryOne = UUID(), entryTwo = UUID()
        let a = UUID(), b = UUID()
        let edges = EntityGraph.build(
            links: [link(entryOne, a, now), link(entryOne, b, now), link(entryTwo, a, now), link(entryTwo, b, now)],
            asOf: now
        )
        #expect(edges.count == 1)
        #expect(abs(edges[0].weight - 2.0) < 0.0001)
    }

    @Test func duplicateEntityInOneEntryDoesNotSelfPairOrInflate() {
        let entry = UUID()
        let a = UUID(), b = UUID()
        // Two mentions in one entry resolving to the same entity (post-merge), plus one other.
        let edges = EntityGraph.build(links: [link(entry, a, now), link(entry, a, now), link(entry, b, now)], asOf: now)
        #expect(edges.count == 1)
        #expect(Set([edges[0].a, edges[0].b]) == Set([a, b]))
        #expect(abs(edges[0].weight - 1.0) < 0.0001)
    }

    @Test func entryAfterAsOfContributesNothing() {
        let entry = UUID()
        let a = UUID(), b = UUID()
        let future = now.addingTimeInterval(3600)
        let edges = EntityGraph.build(links: [link(entry, a, future), link(entry, b, future)], asOf: now)
        #expect(edges.isEmpty)
    }

    @Test func singleEntityEntryContributesNothing() {
        let entry = UUID()
        let edges = EntityGraph.build(links: [link(entry, UUID(), now)], asOf: now)
        #expect(edges.isEmpty)
    }

    @Test func edgeCanonicalizesRegardlessOfInputOrder() {
        let entry1 = UUID(), entry2 = UUID()
        let a = UUID(), b = UUID()
        let forward = EntityGraph.build(links: [link(entry1, a, now), link(entry1, b, now)], asOf: now)
        let backward = EntityGraph.build(links: [link(entry2, b, now), link(entry2, a, now)], asOf: now)
        #expect(forward == backward)
    }

    // MARK: - recency

    @Test func recencyIsOneForAnEntrySharedToday() {
        let entry = UUID()
        let edges = EntityGraph.build(links: [link(entry, UUID(), now), link(entry, UUID(), now)], asOf: now)
        #expect(abs(edges[0].recency - 1.0) < 0.0001)
    }

    @Test func recencyIsHalfAtOneHalfLife() {
        let entry = UUID()
        let halfLife: TimeInterval = 90 * 86400
        let date = now.addingTimeInterval(-halfLife)
        let edges = EntityGraph.build(links: [link(entry, UUID(), date), link(entry, UUID(), date)], asOf: now, halfLife: halfLife)
        #expect(abs(edges[0].recency - 0.5) < 0.0001)
    }

    // Two shared entries sum into weight, but recency is the most recent one alone.
    @Test func recencyIsTheLatestSharedEntryNotTheSum() {
        let old = UUID(), recent = UUID()
        let a = UUID(), b = UUID()
        let halfLife: TimeInterval = 90 * 86400
        let oldDate = now.addingTimeInterval(-2 * halfLife)
        let recentDate = now.addingTimeInterval(-halfLife)
        let edges = EntityGraph.build(
            links: [link(old, a, oldDate), link(old, b, oldDate), link(recent, a, recentDate), link(recent, b, recentDate)],
            asOf: now,
            halfLife: halfLife
        )
        #expect(abs(edges[0].weight - 0.75) < 0.0001)
        #expect(abs(edges[0].recency - 0.5) < 0.0001)
    }

    // MARK: - neighbourhood

    @Test func neighbourhoodDepthZeroIsEmpty() {
        let a = UUID(), b = UUID()
        let edges = [EntityGraph.Edge(a, b, weight: 1)]
        #expect(EntityGraph.neighbourhood(of: a, in: edges, depth: 0).isEmpty)
    }

    @Test func neighbourhoodDepthOneIsDirectOnly() {
        let a = UUID(), b = UUID(), c = UUID()
        let edges = [EntityGraph.Edge(a, b, weight: 1), EntityGraph.Edge(b, c, weight: 1)]
        let found = EntityGraph.neighbourhood(of: a, in: edges, depth: 1)
        #expect(found == [b])
    }

    @Test func neighbourhoodDepthTwoIncludesNeighboursNeighbour() {
        let a = UUID(), b = UUID(), c = UUID()
        let edges = [EntityGraph.Edge(a, b, weight: 1), EntityGraph.Edge(b, c, weight: 1)]
        let found = EntityGraph.neighbourhood(of: a, in: edges, depth: 2)
        #expect(found == [b, c])
    }

    @Test func neighbourhoodStopsAtGivenDepth() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let edges = [EntityGraph.Edge(a, b, weight: 1), EntityGraph.Edge(b, c, weight: 1), EntityGraph.Edge(c, d, weight: 1)]
        let found = EntityGraph.neighbourhood(of: a, in: edges, depth: 2)
        #expect(found == [b, c])
        #expect(!found.contains(d))
    }

    @Test func neighbourhoodExcludesTheNodeItself() {
        let a = UUID(), b = UUID()
        let edges = [EntityGraph.Edge(a, b, weight: 1)]
        #expect(!EntityGraph.neighbourhood(of: a, in: edges, depth: 5).contains(a))
    }

    @Test func neighbourhoodWithNoEdgesIsEmpty() {
        #expect(EntityGraph.neighbourhood(of: UUID(), in: [], depth: 2).isEmpty)
    }

    // MARK: - filtered

    @Test func filteredDropsWrongKind() {
        let a = UUID(), b = UUID()
        let edges = [EntityGraph.Edge(a, b, weight: 1)]
        let nodes = [a: EntityGraph.Node(kind: .person, linkCount: 5), b: EntityGraph.Node(kind: .tag, linkCount: 5)]
        #expect(EntityGraph.filtered(edges: edges, nodes: nodes, kinds: [.person], minimumLinkCount: 0).isEmpty)
    }

    @Test func filteredKeepsAllWhenKindsIsNil() {
        let a = UUID(), b = UUID()
        let edges = [EntityGraph.Edge(a, b, weight: 1)]
        let nodes = [a: EntityGraph.Node(kind: .person, linkCount: 5), b: EntityGraph.Node(kind: .tag, linkCount: 5)]
        #expect(EntityGraph.filtered(edges: edges, nodes: nodes, kinds: nil, minimumLinkCount: 0).count == 1)
    }

    @Test func filteredDropsBelowMinimumLinkCount() {
        let a = UUID(), b = UUID()
        let edges = [EntityGraph.Edge(a, b, weight: 1)]
        let nodes = [a: EntityGraph.Node(kind: .person, linkCount: 1), b: EntityGraph.Node(kind: .person, linkCount: 5)]
        #expect(EntityGraph.filtered(edges: edges, nodes: nodes, kinds: nil, minimumLinkCount: 2).isEmpty)
    }

    @Test func filteredDropsEdgeWithMissingEndpoint() {
        let a = UUID(), b = UUID()
        let edges = [EntityGraph.Edge(a, b, weight: 1)]
        let nodes = [a: EntityGraph.Node(kind: .person, linkCount: 5)]
        #expect(EntityGraph.filtered(edges: edges, nodes: nodes, kinds: nil, minimumLinkCount: 0).isEmpty)
    }
}
