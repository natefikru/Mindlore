import Foundation
import SwiftData
import Testing
@testable import Mindlore

// The 3D spike's layout, held to the same bars as GraphSimulationTests holds the 2D one: it
// settles inside the budget at every size, never goes non-finite, never stacks two nodes, and
// gives the same answer twice.
struct GraphSimulation3DTests {
    private func makeNodes(_ count: Int) -> [GraphSimulation3D.Node] {
        (0..<count).map { _ in GraphSimulation3D.Node(id: UUID(), kind: .person, linkCount: 1) }
    }

    private func settle(_ simulation: GraphSimulation3D, budget: Int = 2000) -> Int {
        var ticks = 0
        while !simulation.settled, ticks < budget {
            simulation.tick()
            ticks += 1
        }
        return ticks
    }

    private func allFinite(_ simulation: GraphSimulation3D, ids: [UUID]) -> Bool {
        ids.allSatisfy { id in
            guard let p = simulation.position(of: id) else { return true }
            return p.x.isFinite && p.y.isFinite && p.z.isFinite
        }
    }

    // MARK: - Settling within budget

    @Test func zeroNodesSettlesImmediately() {
        let simulation = GraphSimulation3D(nodes: [], edges: [])
        #expect(settle(simulation) <= 2000)
        #expect(simulation.settled)
    }

    @Test func oneNodeSettlesWithinBudget() {
        let nodes = makeNodes(1)
        let simulation = GraphSimulation3D(nodes: nodes, edges: [])
        #expect(settle(simulation) < 2000)
        #expect(allFinite(simulation, ids: nodes.map(\.id)))
    }

    @Test func twoNodesSettleWithinBudget() {
        let nodes = makeNodes(2)
        let simulation = GraphSimulation3D(nodes: nodes, edges: [])
        #expect(settle(simulation) < 2000)
        #expect(allFinite(simulation, ids: nodes.map(\.id)))
    }

    @Test func fiftyNodesSettleWithinBudget() {
        let nodes = makeNodes(50)
        let simulation = GraphSimulation3D(nodes: nodes, edges: [])
        var ticks = 0
        while !simulation.settled, ticks < 2000 {
            simulation.tick()
            ticks += 1
            #expect(allFinite(simulation, ids: nodes.map(\.id)))
        }
        #expect(simulation.settled)
    }

    @Test func threeHundredNodesSettleWithinBudget() {
        let nodes = makeNodes(300)
        let simulation = GraphSimulation3D(nodes: nodes, edges: [])
        #expect(settle(simulation) < 2000)
        #expect(simulation.settled)
        #expect(allFinite(simulation, ids: nodes.map(\.id)))
    }

    // MARK: - No coincident nodes

    @Test func noTwoNodesEverCoincideOnceTickingStarts() {
        let nodes = makeNodes(20)
        let simulation = GraphSimulation3D(nodes: nodes, edges: [])
        for _ in 0..<200 {
            simulation.tick()
            let positions = nodes.compactMap { simulation.position(of: $0.id) }
            for i in 0..<positions.count {
                for j in (i + 1)..<positions.count {
                    let delta = positions[i] - positions[j]
                    #expect((delta * delta).sum().squareRoot() > 0.0001)
                }
            }
        }
    }

    // MARK: - Zero-distance fallback

    // Nothing can pin a node here, so the way two nodes land on the same point is being placed
    // there: a duplicated position at tick zero has to push apart rather than produce NaN.
    @Test func nodesStartedOnTheSamePointSeparateWithoutNaN() {
        let ids = (0..<4).map { _ in UUID() }
        let nodes = ids.map { GraphSimulation3D.Node(id: $0, kind: .person, linkCount: 1) }
        let edges = [EntityGraph.Edge(ids[0], ids[1], weight: 1)]
        let simulation = GraphSimulation3D(nodes: nodes, edges: edges)
        for _ in 0..<500 {
            simulation.tick()
            #expect(allFinite(simulation, ids: ids))
        }
        let a = simulation.position(of: ids[0])!, b = simulation.position(of: ids[1])!
        let delta = a - b
        #expect((delta * delta).sum().squareRoot() > 1)
    }

    @Test func theZeroDistanceFallbackIsAUnitVector() {
        for count in [1, 2, 7, 300] {
            for index in [0, count - 1] {
                let direction = GraphSimulation3D.direction(index, count: count)
                let length = (direction * direction).sum().squareRoot()
                #expect(abs(length - 1) < 1e-9, "index \(index) of \(count)")
            }
        }
    }

    // MARK: - Determinism

    @Test func sameNodesAndEdgesProduceIdenticalPositions() {
        let ids = (0..<30).map { _ in UUID() }
        let nodes = ids.map { GraphSimulation3D.Node(id: $0, kind: .person, linkCount: 1) }
        let edges = [EntityGraph.Edge(ids[0], ids[1], weight: 0.5), EntityGraph.Edge(ids[1], ids[2], weight: 1)]

        let a = GraphSimulation3D(nodes: nodes, edges: edges)
        let b = GraphSimulation3D(nodes: nodes, edges: edges)
        for _ in 0..<100 {
            a.tick()
            b.tick()
        }
        for id in ids {
            #expect(a.position(of: id) == b.position(of: id))
        }
    }

    // MARK: - Spring target distance

    @Test func singleEdgeSettlesNearTargetDistance() {
        for weight in [0.0, 0.5, 1.0] {
            let nodes = makeNodes(2)
            let edges = [EntityGraph.Edge(nodes[0].id, nodes[1].id, weight: weight)]
            let simulation = GraphSimulation3D(nodes: nodes, edges: edges)
            _ = settle(simulation)
            guard let a = simulation.position(of: nodes[0].id), let b = simulation.position(of: nodes[1].id) else {
                Issue.record("missing positions")
                continue
            }
            let delta = a - b
            let distance = (delta * delta).sum().squareRoot()
            let target = GraphSimulation.targetDistance(weight: weight)
            #expect(abs(distance - target) < target * 0.1)
        }
    }

    // MARK: - Shape

    @Test func edgesToUnknownIdsAreDropped() {
        let nodes = makeNodes(2)
        let edges = [EntityGraph.Edge(nodes[0].id, nodes[1].id, weight: 1), EntityGraph.Edge(nodes[0].id, UUID(), weight: 1)]
        let simulation = GraphSimulation3D(nodes: nodes, edges: edges)
        #expect(simulation.allEdges() == [edges[0]])
        let a = simulation.index(of: edges[0].a)!, b = simulation.index(of: edges[0].b)!
        #expect(simulation.edgeIndices == [GraphSimulation3D.EdgeIndex(a: a, b: b)])
    }

    @Test func duplicateIdsAreDedupedFirstWins() {
        let id = UUID()
        let nodes = [
            GraphSimulation3D.Node(id: id, kind: .person, linkCount: 1),
            GraphSimulation3D.Node(id: id, kind: .place, linkCount: 9),
        ]
        let simulation = GraphSimulation3D(nodes: nodes, edges: [])
        #expect(simulation.nodeCount == 1)
        #expect(simulation.radius(of: id) == GraphSimulation.radius(linkCount: 1))
    }

    // The spike shares 2D's radii, so a node is the same size in both pictures.
    @Test func radiiComeFromTheTwoDimensionalRules() {
        let entry = GraphSimulation3D.Node(id: UUID(), kind: .other, linkCount: 40, isEntry: true)
        let hub = GraphSimulation3D.Node(id: UUID(), kind: .person, linkCount: 40)
        let simulation = GraphSimulation3D(nodes: [entry, hub], edges: [])
        #expect(simulation.radius(of: entry.id) == GraphSimulation.entryRadius)
        #expect(simulation.radius(of: hub.id) == GraphSimulation.radius(linkCount: 40))
    }

    // MARK: - The settled layout

    @Test func settledHandsBackEveryNodesPositionAndATime() async {
        let nodes = makeNodes(20)
        let edges = [EntityGraph.Edge(nodes[0].id, nodes[1].id, weight: 1)]
        let layout = await GraphSimulation3D.settled(nodes: nodes, edges: edges)
        #expect(layout.nodes.count == 20)
        #expect(layout.positions.count == 20)
        #expect(layout.radii.count == 20)
        #expect(layout.edgeIndices.count == 1)
        #expect(layout.settleMilliseconds != nil)
        #expect(layout.index(of: nodes[5].id) == 5)
    }

    @Test func aBudgetTooSmallToSettleReportsNoSettleTime() async {
        let layout = await GraphSimulation3D.settled(nodes: makeNodes(10), edges: [], budget: 5)
        #expect(layout.settleMilliseconds == nil)
    }
}

// The spike over the real 300-entry demo graph, which is what the device comparison is run on.
@MainActor
struct DemoGraph3DSimulationTests {
    @Test func theDemoGraphSettlesWithFinitePositions() async throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        try DemoJournal.seedIfEmpty(count: 300, in: context, now: Date(timeIntervalSince1970: 1_800_000_000))
        let data = GraphServices().globalGraph(kinds: nil, minimumLinkCount: 2, in: context)
        let layout = await GraphSimulation3D.settled(nodes: GraphSimulation.Node.layoutOrdered(data.nodes), edges: data.edges)
        let extent = layout.positions.map { max(abs($0.x), abs($0.y), abs($0.z)) }.max() ?? 0
        #expect(layout.nodes.count > 50)
        #expect(layout.settleMilliseconds != nil)
        #expect(layout.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
        #expect(extent < 1000)
    }
}
