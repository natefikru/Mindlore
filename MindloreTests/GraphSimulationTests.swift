import Foundation
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

    // MARK: - Pinning and anchoring

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

    @Test func anchoredNodeStaysAtAnchorPointAndIgnoresUnpin() {
        let nodes = makeNodes(3)
        let edges = [EntityGraph.Edge(nodes[0].id, nodes[1].id, weight: 1)]
        let simulation = GraphSimulation(nodes: nodes, edges: edges)
        let point = SIMD2<Double>.zero
        simulation.anchor(nodes[0].id, at: point)
        for _ in 0..<100 {
            simulation.tick()
            #expect(simulation.position(of: nodes[0].id) == point)
        }
        simulation.unpin(nodes[0].id)
        simulation.tick()
        #expect(simulation.position(of: nodes[0].id) == point)
        #expect(simulation.isPinned(nodes[0].id))
    }

    // MARK: - Determinism

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

    // MARK: - Color

    @Test func entityKindColorsAreDistinct() {
        let colors = Set(EntityKind.allCases.map { $0.color.description })
        #expect(colors.count == EntityKind.allCases.count)
    }
}
