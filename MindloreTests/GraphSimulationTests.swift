import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Mindlore

struct GraphSimulationTests {
    private func makeNodes(_ count: Int) -> [GraphSimulation.Node] {
        (0..<count).map { _ in GraphSimulation.Node(id: UUID(), kind: .person, linkCount: 1) }
    }

    private func settle(_ simulation: GraphSimulation, budget: Int = 2000) -> Int {
        var ticks = 0
        while !simulation.settled, ticks < budget {
            simulation.tick()
            ticks += 1
        }
        return ticks
    }

    private func allFinite(_ simulation: GraphSimulation, ids: [UUID]) -> Bool {
        ids.allSatisfy { id in
            guard let p = simulation.position(of: id) else { return true }
            return p.x.isFinite && p.y.isFinite
        }
    }

    // MARK: - Settling within budget

    // A tag is a pin: one size whatever its count, smaller than the smallest name.
    @Test func aTagIsASmallPinAtAnyCount() {
        for count in [1, 80] {
            let tag = GraphSimulation.Node(id: UUID(), kind: .tag, linkCount: count)
            #expect(GraphSimulation.radius(for: tag) == GraphSimulation.tagRadius)
        }
        #expect(GraphSimulation.tagRadius < GraphSimulation.radius(linkCount: 1))
        let simulation = GraphSimulation(nodes: [.init(id: UUID(), kind: .tag, linkCount: 40)], edges: [])
        #expect(simulation.radius(at: 0) == GraphSimulation.tagRadius)
    }

    @Test func zeroNodesSettlesImmediately() {
        let simulation = GraphSimulation(nodes: [], edges: [])
        #expect(settle(simulation) <= 2000)
        #expect(simulation.settled)
    }

    @Test func oneNodeSettlesWithinBudget() {
        let nodes = makeNodes(1)
        let simulation = GraphSimulation(nodes: nodes, edges: [])
        #expect(settle(simulation) < 2000)
        #expect(allFinite(simulation, ids: nodes.map(\.id)))
    }

    @Test func twoNodesSettleWithinBudget() {
        let nodes = makeNodes(2)
        let simulation = GraphSimulation(nodes: nodes, edges: [])
        #expect(settle(simulation) < 2000)
        #expect(allFinite(simulation, ids: nodes.map(\.id)))
    }

    @Test func fiftyNodesSettleWithinBudget() {
        let nodes = makeNodes(50)
        let simulation = GraphSimulation(nodes: nodes, edges: [])
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
        let simulation = GraphSimulation(nodes: nodes, edges: [])
        var ticks = 0
        while !simulation.settled, ticks < 2000 {
            simulation.tick()
            ticks += 1
        }
        #expect(simulation.settled)
        #expect(allFinite(simulation, ids: nodes.map(\.id)))
    }

    // MARK: - No coincident nodes

    @Test func noTwoNodesEverCoincideOnceTickingStarts() {
        let nodes = makeNodes(20)
        let simulation = GraphSimulation(nodes: nodes, edges: [])
        for _ in 0..<200 {
            simulation.tick()
            let positions = nodes.compactMap { simulation.position(of: $0.id) }
            for i in 0..<positions.count {
                for j in (i + 1)..<positions.count {
                    let dx = positions[i].x - positions[j].x
                    let dy = positions[i].y - positions[j].y
                    let distance = (dx * dx + dy * dy).squareRoot()
                    #expect(distance > 0.0001)
                }
            }
        }
    }

    // MARK: - Zero-distance fallback

    @Test func pinningTwoNodesToTheSamePointProducesNoNaN() {
        let nodes = makeNodes(5)
        let edges = [EntityGraph.Edge(nodes[0].id, nodes[1].id, weight: 1)]
        let simulation = GraphSimulation(nodes: nodes, edges: edges)
        let point = SIMD2<Double>(10, 10)
        simulation.pin(nodes[0].id, at: point)
        simulation.pin(nodes[1].id, at: point)
        for _ in 0..<500 {
            simulation.tick()
            #expect(allFinite(simulation, ids: nodes.map(\.id)))
        }
        #expect(simulation.position(of: nodes[0].id) == point)
        #expect(simulation.position(of: nodes[1].id) == point)
    }

    // MARK: - Actual convergence

    @Test func fiftyNodesActuallyConverge() {
        let nodes = makeNodes(50)
        let simulation = GraphSimulation(nodes: nodes, edges: [])
        var previous = nodes.compactMap { simulation.position(of: $0.id) }
        var lastDelta: Double = .infinity
        var ticks = 0
        while !simulation.settled, ticks < 2000 {
            simulation.tick()
            ticks += 1
            let current = nodes.compactMap { simulation.position(of: $0.id) }
            lastDelta = zip(previous, current).map { a, b in
                let dx = a.x - b.x, dy = a.y - b.y
                return (dx * dx + dy * dy).squareRoot()
            }.max() ?? 0
            previous = current
        }
        #expect(simulation.settled)
        #expect(lastDelta < 1.0)
    }

    @Test func threeHundredNodesActuallyConverge() {
        let nodes = makeNodes(300)
        let simulation = GraphSimulation(nodes: nodes, edges: [])
        var previous = nodes.compactMap { simulation.position(of: $0.id) }
        var lastDelta: Double = .infinity
        var ticks = 0
        while !simulation.settled, ticks < 2000 {
            simulation.tick()
            ticks += 1
            let current = nodes.compactMap { simulation.position(of: $0.id) }
            lastDelta = zip(previous, current).map { a, b in
                let dx = a.x - b.x, dy = a.y - b.y
                return (dx * dx + dy * dy).squareRoot()
            }.max() ?? 0
            previous = current
        }
        #expect(simulation.settled)
        #expect(lastDelta < 1.0)
    }

    // MARK: - Pinning

    @Test func pinnedNodeStaysExactlyAtPinPoint() {
        let nodes = makeNodes(3)
        let edges = [EntityGraph.Edge(nodes[0].id, nodes[1].id, weight: 1), EntityGraph.Edge(nodes[0].id, nodes[2].id, weight: 1)]
        let simulation = GraphSimulation(nodes: nodes, edges: edges)
        let point = SIMD2<Double>(5, -5)
        simulation.pin(nodes[0].id, at: point)
        for _ in 0..<100 {
            simulation.tick()
            #expect(simulation.position(of: nodes[0].id) == point)
        }
    }

    @Test func newWeightsOnTheSameNodesOnlyNudge() {
        let nodes = makeNodes(3)
        let simulation = GraphSimulation(nodes: nodes, edges: [EntityGraph.Edge(nodes[0].id, nodes[1].id, weight: 1, recency: 1)])
        _ = settle(simulation)
        simulation.update(nodes: nodes, edges: [EntityGraph.Edge(nodes[0].id, nodes[1].id, weight: 0.8, recency: 0.8)])
        #expect(simulation.alpha < GraphSimulation.updateReheat, "a replay step that only reweights edges doesn't jolt the map")
    }

    @Test func sameNodesAndEdgesProduceIdenticalPositions() {
        let ids = (0..<30).map { _ in UUID() }
        let nodes = ids.map { GraphSimulation.Node(id: $0, kind: .person, linkCount: 1) }
        let edges = [EntityGraph.Edge(ids[0], ids[1], weight: 0.5), EntityGraph.Edge(ids[1], ids[2], weight: 1)]

        let a = GraphSimulation(nodes: nodes, edges: edges)
        let b = GraphSimulation(nodes: nodes, edges: edges)
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
            let simulation = GraphSimulation(nodes: nodes, edges: edges)
            _ = settle(simulation)
            guard let a = simulation.position(of: nodes[0].id), let b = simulation.position(of: nodes[1].id) else {
                Issue.record("missing positions")
                continue
            }
            let dx = a.x - b.x, dy = a.y - b.y
            let distance = (dx * dx + dy * dy).squareRoot()
            let target = GraphSimulation.targetDistance(weight: weight)
            #expect(abs(distance - target) < target * 0.1)
        }
    }

    // MARK: - Staying warm

    private func distance(_ a: SIMD2<Double>?, _ b: SIMD2<Double>?) -> Double {
        guard let a, let b else { return .infinity }
        let d = a - b
        return (d.x * d.x + d.y * d.y).squareRoot()
    }

    @Test func dragReheatKeepsAlphaUpWhilePinnedAndSettlesAfterRelease() {
        let nodes = makeNodes(10)
        let edges = [EntityGraph.Edge(nodes[0].id, nodes[1].id, weight: 1), EntityGraph.Edge(nodes[0].id, nodes[2].id, weight: 1)]
        let simulation = GraphSimulation(nodes: nodes, edges: edges)
        _ = settle(simulation)
        #expect(simulation.settled)

        let point = SIMD2<Double>(80, -40)
        simulation.pin(nodes[0].id, at: point)
        simulation.alphaTarget = GraphSimulation.dragAlphaTarget
        #expect(!simulation.settled)
        for _ in 0..<500 {
            simulation.tick()
        }
        #expect(!simulation.settled)
        #expect(simulation.alpha > 0.2)
        #expect(simulation.position(of: nodes[0].id) == point)
        // Its neighbours were pulled toward the dragged node.
        #expect(distance(simulation.position(of: nodes[1].id), point) < 120)

        simulation.alphaTarget = 0
        simulation.unpin(nodes[0].id)
        #expect(settle(simulation) < 2000)
        #expect(simulation.settled)
    }

    @Test func settledSimulationWakesWhenTargetIsRaised() {
        let nodes = makeNodes(3)
        let simulation = GraphSimulation(nodes: nodes, edges: [])
        _ = settle(simulation)
        let before = simulation.alpha
        simulation.alphaTarget = 0.3
        simulation.tick()
        #expect(simulation.alpha > before)
    }

    @Test func reheatNeverLowersAlpha() {
        let simulation = GraphSimulation(nodes: makeNodes(3), edges: [])
        simulation.reheat(to: 0.3)
        #expect(simulation.alpha == 1)
        _ = settle(simulation)
        simulation.reheat(to: 0.3)
        #expect(simulation.alpha == 0.3)
        #expect(!simulation.settled)
    }

    // MARK: - Updating in place

    @Test func updateKeepsSurvivingPositionsExactly() {
        let nodes = makeNodes(6)
        let simulation = GraphSimulation(nodes: nodes, edges: [])
        for _ in 0..<50 { simulation.tick() }
        let before = nodes.prefix(4).map { simulation.position(of: $0.id) }

        let extra = makeNodes(2)
        simulation.update(nodes: Array(nodes.prefix(4).reversed()) + extra, edges: [])
        #expect(nodes.prefix(4).map { simulation.position(of: $0.id) } == before)
        #expect(simulation.position(of: nodes[5].id) == nil)
    }

    @Test func updatePlacesANewNodeNearItsStrongestNeighbour() {
        let nodes = makeNodes(2)
        let simulation = GraphSimulation(nodes: nodes, edges: [])
        let strong = SIMD2<Double>(-200, 0), weak = SIMD2<Double>(200, 0)
        simulation.pin(nodes[0].id, at: strong)
        simulation.pin(nodes[1].id, at: weak)
        simulation.tick()

        let newcomer = GraphSimulation.Node(id: UUID(), kind: .place, linkCount: 1)
        simulation.update(nodes: nodes + [newcomer], edges: [
            EntityGraph.Edge(newcomer.id, nodes[0].id, weight: 0.9),
            EntityGraph.Edge(newcomer.id, nodes[1].id, weight: 0.2),
        ])
        let placed = simulation.position(of: newcomer.id)
        #expect(distance(placed, strong) < GraphSimulation.targetDistance(weight: 0.9) * 2)
        #expect(distance(placed, strong) < distance(placed, weak))
    }

    @Test func updatePlacesAChainOfNewNodesOffTheFirstPlacedOne() {
        let nodes = makeNodes(1)
        let simulation = GraphSimulation(nodes: nodes, edges: [])
        simulation.pin(nodes[0].id, at: SIMD2(500, 500))
        simulation.tick()
        let first = GraphSimulation.Node(id: UUID(), kind: .person, linkCount: 1)
        let second = GraphSimulation.Node(id: UUID(), kind: .person, linkCount: 1)
        simulation.update(nodes: nodes + [first, second], edges: [
            EntityGraph.Edge(first.id, nodes[0].id, weight: 1),
            EntityGraph.Edge(second.id, first.id, weight: 1),
        ])
        #expect(distance(simulation.position(of: second.id), SIMD2(500, 500)) < 150)
    }

    @Test func updatePlacesAnUnlinkedNewNodeWithoutNaN() {
        let nodes = makeNodes(5)
        let simulation = GraphSimulation(nodes: nodes, edges: [])
        _ = settle(simulation)
        let newcomers = makeNodes(3)
        simulation.update(nodes: nodes + newcomers, edges: [])
        for _ in 0..<300 {
            simulation.tick()
            #expect(allFinite(simulation, ids: (nodes + newcomers).map(\.id)))
        }
    }

    @Test func updateDropsRemovedNodesAndTheirPins() {
        let nodes = makeNodes(3)
        let simulation = GraphSimulation(nodes: nodes, edges: [EntityGraph.Edge(nodes[0].id, nodes[1].id, weight: 1)])
        simulation.pin(nodes[0].id, at: SIMD2(1, 1))
        simulation.update(nodes: Array(nodes.dropFirst()), edges: [EntityGraph.Edge(nodes[0].id, nodes[1].id, weight: 1)])
        #expect(simulation.nodeCount == 2)
        #expect(!simulation.isPinned(nodes[0].id))
        #expect(simulation.allEdges().isEmpty)
        #expect(simulation.edgeIndices.isEmpty)

        // Coming back, it is a new node with no pin.
        simulation.update(nodes: nodes, edges: [])
        #expect(!simulation.isPinned(nodes[0].id))
    }

    @Test func updateReheatsToPointThreeAndBumpsTheVersion() {
        let nodes = makeNodes(4)
        let simulation = GraphSimulation(nodes: nodes, edges: [])
        _ = settle(simulation)
        let version = simulation.topologyVersion
        simulation.update(nodes: nodes + makeNodes(1), edges: [])
        #expect(simulation.alpha == GraphSimulation.updateReheat)
        #expect(simulation.topologyVersion == version + 1)
        #expect(!simulation.settled)
    }

    @Test func updateWithTheSameSetsDoesNothing() {
        let nodes = makeNodes(4)
        let edges = [EntityGraph.Edge(nodes[0].id, nodes[1].id, weight: 1)]
        let simulation = GraphSimulation(nodes: nodes, edges: edges)
        _ = settle(simulation)
        let version = simulation.topologyVersion
        simulation.update(nodes: nodes.reversed(), edges: edges)
        #expect(simulation.settled)
        #expect(simulation.topologyVersion == version)
    }

    @Test func updateTakesNewLinkCountsForSurvivors() {
        let nodes = makeNodes(2)
        let simulation = GraphSimulation(nodes: nodes, edges: [])
        _ = settle(simulation)
        let version = simulation.topologyVersion
        let grown = GraphSimulation.Node(id: nodes[0].id, kind: .project, linkCount: 25)
        simulation.update(nodes: [grown, nodes[1]], edges: [])
        #expect(simulation.linkCount(of: nodes[0].id) == 25)
        #expect(simulation.kind(of: nodes[0].id) == .project)
        #expect(simulation.radius(of: nodes[0].id) == GraphSimulation.radius(linkCount: 25))
        #expect(simulation.topologyVersion == version + 1)
        // A grown node gets a small nudge to make room, not the full update reheat.
        #expect(simulation.alpha == GraphSimulation.resizeReheat)
    }

    @Test func updateWithOnlyAKindChangeStaysSettled() {
        let nodes = makeNodes(2)
        let simulation = GraphSimulation(nodes: nodes, edges: [])
        _ = settle(simulation)
        let renamedKind = GraphSimulation.Node(id: nodes[0].id, kind: .place, linkCount: nodes[0].linkCount)
        simulation.update(nodes: [renamedKind, nodes[1]], edges: [])
        #expect(simulation.kind(of: nodes[0].id) == .place)
        #expect(simulation.settled)
    }

    @Test func duplicateIdsAreDedupedFirstWins() {
        let id = UUID()
        let nodes = [
            GraphSimulation.Node(id: id, kind: .person, linkCount: 1),
            GraphSimulation.Node(id: id, kind: .place, linkCount: 9),
        ]
        let simulation = GraphSimulation(nodes: nodes, edges: [])
        #expect(simulation.nodeCount == 1)
        #expect(simulation.kind(of: id) == .person)
        simulation.update(nodes: nodes.reversed(), edges: [])
        #expect(simulation.nodeCount == 1)
        #expect(simulation.kind(of: id) == .place)
    }

    @Test func edgesToUnknownIdsAreDropped() {
        let nodes = makeNodes(2)
        let edges = [EntityGraph.Edge(nodes[0].id, nodes[1].id, weight: 1), EntityGraph.Edge(nodes[0].id, UUID(), weight: 1)]
        let simulation = GraphSimulation(nodes: nodes, edges: edges)
        #expect(simulation.allEdges() == [edges[0]])
        let a = simulation.index(of: edges[0].a)!, b = simulation.index(of: edges[0].b)!
        #expect(simulation.edgeIndices == [GraphSimulation.EdgeIndex(a: a, b: b)])
    }

    @Test func updateIsDeterministic() {
        let ids = (0..<20).map { _ in UUID() }
        let nodes = ids.map { GraphSimulation.Node(id: $0, kind: .person, linkCount: 1) }
        let firstEdges = [EntityGraph.Edge(ids[0], ids[1], weight: 1)]
        let secondEdges = firstEdges + [EntityGraph.Edge(ids[10], ids[0], weight: 0.5), EntityGraph.Edge(ids[11], ids[10], weight: 1)]

        let a = GraphSimulation(nodes: Array(nodes.prefix(10)), edges: firstEdges)
        let b = GraphSimulation(nodes: Array(nodes.prefix(10)), edges: firstEdges)
        for simulation in [a, b] {
            for _ in 0..<40 { simulation.tick() }
            simulation.update(nodes: nodes, edges: secondEdges)
            for _ in 0..<40 { simulation.tick() }
        }
        for id in ids {
            #expect(a.position(of: id) == b.position(of: id))
        }
    }

    // MARK: - Color

    @Test func entityKindColorsAreDistinct() {
        let colors = Set(EntityKind.allCases.map { $0.color.description })
        #expect(colors.count == EntityKind.allCases.count)
    }
}

// The simulation over the real 300-entry demo graph, the one the device gate measures.
@MainActor
struct DemoGraphSimulationTests {
    @Test func theDemoGraphSettlesWithFinitePositions() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        try DemoJournal.seedIfEmpty(count: 300, in: context, now: Date(timeIntervalSince1970: 1_800_000_000))
        let data = GraphServices().globalGraph(kinds: nil, minimumLinkCount: 2, in: context)
        let simulation = GraphSimulation(nodes: GraphSimulation.Node.layoutOrdered(data.nodes), edges: data.edges)
        var ticks = 0
        while !simulation.settled, ticks < 2000 {
            simulation.tick()
            ticks += 1
        }
        let positions = (0..<simulation.nodeCount).map { simulation.position(at: $0) }
        let extent = positions.map { max(abs($0.x), abs($0.y)) }.max() ?? 0
        #expect(simulation.nodeCount > 50)
        #expect(simulation.settled)
        #expect(positions.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        #expect(extent < 1000)
    }
}
