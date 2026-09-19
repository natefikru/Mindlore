import Foundation

#if DEBUG

// The SIMD3 twin of GraphSimulation, for the Phase A 3D spike. Same constants, same tick order,
// same alpha schedule: the point of the spike is to compare the picture and the frame times, not
// two different layouts, so every number here comes from GraphSimulation's own statics rather
// than being copied.
//
// What it leaves out is what the spike doesn't need: no regions, no pins, no in-place `update`.
// It builds once from a snapshot, settles, and the scene is made from where the nodes landed.
//
// Placement is the 3D analogue of the 2D phyllotaxis: a Fibonacci sphere for the direction and a
// cube-root radius, which fills a ball as evenly as sqrt fills a disc. Like phyllotaxis it is a
// function of the index alone (plus the count), so the same nodes in the same order always give
// the same layout.
nonisolated final class GraphSimulation3D {
    typealias Node = GraphSimulation.Node

    // One edge resolved to node indices, parallel to `edges`.
    struct EdgeIndex: Equatable, Sendable {
        let a: Int
        let b: Int
    }

    // d3's link defaults, per edge: strength 1 / min(degree), bias toward the busier end.
    private struct SpringShape {
        let strength: Double
        let biasTowardB: Double
    }

    let alphaMin: Double = 0.001
    let alphaDecay: Double = 1 - pow(0.001, 1.0 / 300.0)
    let velocityDecay: Double = 0.6
    private(set) var alpha: Double = 1.0
    var alphaTarget: Double = 0

    private(set) var nodes: [Node]
    private(set) var edges: [EntityGraph.Edge]
    private(set) var edgeIndices: [EdgeIndex]
    private var springShapes: [SpringShape]
    private var indexByID: [UUID: Int]
    private var entryFlags: [Bool]

    private var positions: [SIMD3<Double>]
    private var velocities: [SIMD3<Double>]
    private var radii: [Double]

    init(nodes: [Node], edges: [EntityGraph.Edge]) {
        let unique = Self.deduplicated(nodes)
        let map = Self.indexMap(unique)
        let resolved = Self.resolve(edges, in: map)
        self.nodes = unique
        indexByID = map
        entryFlags = unique.map(\.isEntry)
        self.edges = resolved.edges
        edgeIndices = resolved.indices
        springShapes = Self.springShapes(resolved.indices, nodeCount: unique.count)
        positions = unique.indices.map { Self.placement($0, count: unique.count) }
        velocities = Array(repeating: .zero, count: unique.count)
        radii = unique.map(GraphSimulation.radius(for:))
    }

    var settled: Bool { alpha <= alphaMin && alphaTarget <= alphaMin }

    // MARK: - Reading

    var nodeCount: Int { nodes.count }

    func position(at index: Int) -> SIMD3<Double> { positions[index] }

    func radius(at index: Int) -> Double { radii[index] }

    func index(of id: UUID) -> Int? { indexByID[id] }

    func position(of id: UUID) -> SIMD3<Double>? {
        indexByID[id].map { positions[$0] }
    }

    func radius(of id: UUID) -> Double? {
        indexByID[id].map { radii[$0] }
    }

    func allEdges() -> [EntityGraph.Edge] { edges }

    // MARK: - Geometry

    // An even direction over the sphere: the golden angle around the axis, equal slices along it.
    static func direction(_ index: Int, count: Int) -> SIMD3<Double> {
        guard count > 0 else { return SIMD3(1, 0, 0) }
        let i = Double(index) + 0.5
        let z = 1 - 2 * i / Double(count)
        let ring = (max(0, 1 - z * z)).squareRoot()
        let angle = Double(index) * GraphSimulation.goldenAngle
        return SIMD3(ring * cos(angle), ring * sin(angle), z)
    }

    // Direction times a cube-root radius, so the starting ball has an even density rather than a
    // dense shell. 12 is the 2D spacing constant, unchanged.
    static func placement(_ index: Int, count: Int) -> SIMD3<Double> {
        direction(index, count: count) * (cbrt(Double(index) + 0.5) * 12)
    }

    private static func deduplicated(_ nodes: [Node]) -> [Node] {
        var seen: Set<UUID> = []
        return nodes.filter { seen.insert($0.id).inserted }
    }

    private static func indexMap(_ nodes: [Node]) -> [UUID: Int] {
        var map: [UUID: Int] = [:]
        map.reserveCapacity(nodes.count)
        for (index, node) in nodes.enumerated() { map[node.id] = index }
        return map
    }

    private static func resolve(_ edges: [EntityGraph.Edge], in map: [UUID: Int]) -> (edges: [EntityGraph.Edge], indices: [EdgeIndex]) {
        var kept: [EntityGraph.Edge] = []
        var indices: [EdgeIndex] = []
        for edge in edges {
            guard let a = map[edge.a], let b = map[edge.b] else { continue }
            kept.append(edge)
            indices.append(EdgeIndex(a: a, b: b))
        }
        return (kept, indices)
    }

    private static func springShapes(_ indices: [EdgeIndex], nodeCount: Int) -> [SpringShape] {
        var degree = [Int](repeating: 0, count: nodeCount)
        for pair in indices {
            degree[pair.a] += 1
            degree[pair.b] += 1
        }
        return indices.map { pair in
            let a = Double(degree[pair.a]), b = Double(degree[pair.b])
            return SpringShape(strength: 1 / min(a, b), biasTowardB: a / (a + b))
        }
    }

    // MARK: - Ticking

    func tick() {
        guard !settled else { return }

        if !nodes.isEmpty {
            applyRepulsion()
            applySprings()
            applyGravity()
            applyCollision()

            for index in 0..<nodes.count {
                velocities[index] *= (1 - velocityDecay)
                positions[index] += velocities[index]
            }
        }

        alpha += (alphaTarget - alpha) * alphaDecay
    }

    // A literally-zero distance turns the unit vector into 0/0. The fallback is the lower index's
    // own placement direction, which is deterministic and never the zero vector.
    private func direction(_ i: Int, _ j: Int, delta: SIMD3<Double>, distance: Double) -> SIMD3<Double> {
        guard distance > 0 else { return Self.direction(min(i, j), count: nodes.count) }
        return delta / distance
    }

    // d3's forceManyBody falloff, all pairs, strength / distance and scaled by alpha, exactly as
    // in 2D. Two entry dots are left to collision.
    private func applyRepulsion() {
        guard nodes.count > 1 else { return }
        let strength = 30.0 * alpha
        for i in 0..<nodes.count {
            for j in (i + 1)..<nodes.count {
                if entryFlags[i] && entryFlags[j] { continue }
                let delta = positions[i] - positions[j]
                let distance = (delta * delta).sum().squareRoot()
                let dir = direction(i, j, delta: delta, distance: distance)
                let magnitude = strength / max(distance, 1)
                velocities[i] += dir * magnitude
                velocities[j] -= dir * magnitude
            }
        }
    }

    private func applySprings() {
        for ((edge, pair), shape) in zip(zip(edges, edgeIndices), springShapes) {
            let i = pair.a, j = pair.b
            let delta = positions[j] - positions[i]
            let distance = (delta * delta).sum().squareRoot()
            let dir = direction(i, j, delta: delta, distance: distance)
            let magnitude = alpha * (distance - GraphSimulation.targetDistance(weight: edge.weight)) * shape.strength
            let correction = dir * magnitude
            velocities[i] += correction * (1 - shape.biasTowardB)
            velocities[j] -= correction * shape.biasTowardB
        }
    }

    private func applyGravity() {
        for index in 0..<nodes.count {
            velocities[index] += -positions[index] * 0.01 * alpha
        }
    }

    // Half the overlap each, with the same loose bounding check before the square root.
    private func applyCollision() {
        for i in 0..<nodes.count {
            for j in (i + 1)..<nodes.count {
                let sumRadii = radii[i] + radii[j]
                let delta = positions[j] - positions[i]
                guard abs(delta.x) < sumRadii, abs(delta.y) < sumRadii, abs(delta.z) < sumRadii else { continue }
                let distance = (delta * delta).sum().squareRoot()
                guard distance < sumRadii else { continue }
                let overlap = (sumRadii - distance) * 0.5
                let dir = direction(i, j, delta: delta, distance: distance)
                velocities[i] -= dir * overlap
                velocities[j] += dir * overlap
            }
        }
    }
}

// MARK: - Layout

// Where a settled simulation left everything, as plain values. The scene is built from this
// rather than from the simulation itself, so the settle can run off the main actor and hand back
// something Sendable, and so the scene builder can be tested without a simulation at all.
nonisolated struct Graph3DLayout: Sendable {
    let nodes: [GraphSimulation3D.Node]
    let edgeIndices: [GraphSimulation3D.EdgeIndex]
    let positions: [SIMD3<Double>]
    let radii: [Double]
    // Nil when the tick budget ran out first.
    let settleMilliseconds: Double?
    let indexByID: [UUID: Int]

    func index(of id: UUID) -> Int? { indexByID[id] }
}

extension GraphSimulation3D {
    // The whole spike in one call: build, settle, hand back the positions. 2000 ticks is the same
    // budget the 2D suite holds the layout to.
    static let settleBudget = 2000

    @concurrent nonisolated static func settled(
        nodes: [Node],
        edges: [EntityGraph.Edge],
        budget: Int = settleBudget
    ) async -> Graph3DLayout {
        let simulation = GraphSimulation3D(nodes: nodes, edges: edges)
        let started = ContinuousClock.now
        var ticks = 0
        while !simulation.settled, ticks < budget {
            simulation.tick()
            ticks += 1
        }
        let taken = started.duration(to: .now)
        let elapsed = Double(taken.components.seconds) * 1000 + Double(taken.components.attoseconds) / 1e15
        return Graph3DLayout(
            nodes: simulation.nodes,
            edgeIndices: simulation.edgeIndices,
            positions: (0..<simulation.nodeCount).map { simulation.position(at: $0) },
            radii: (0..<simulation.nodeCount).map { simulation.radius(at: $0) },
            settleMilliseconds: simulation.settled ? elapsed : nil,
            indexByID: Dictionary(uniqueKeysWithValues: simulation.nodes.enumerated().map { ($0.element.id, $0.offset) })
        )
    }
}
#endif
