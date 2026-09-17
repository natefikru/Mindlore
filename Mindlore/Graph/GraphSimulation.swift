import Foundation

// A force layout over EntityGraph's edges. Plain, non-Observable class: the canvas ticks it from
// inside its own draw closure every frame, and an @Observable write there would trip "modifying
// state during view update" the way a plain class reference never does. Positions are parallel
// arrays over SIMD2<Double>, one entry per node, indexed by the node's position in `nodes`;
// `indexByID` resolves ids into that index once, the same "resolve into an in-memory map once"
// shape GraphServices.mentionedWith already uses for entities.
//
// It stays warm on demand: a drag raises `alphaTarget` so alpha holds instead of decaying (d3's
// pattern), and `update` swaps the node and edge sets in place so a filter change moves the
// picture rather than restarting it.
nonisolated final class GraphSimulation {
    struct Node: Hashable, Sendable {
        let id: UUID
        let kind: EntityKind
        let linkCount: Int

        init(id: UUID, kind: EntityKind, linkCount: Int) {
            self.id = id
            self.kind = kind
            self.linkCount = linkCount
        }
    }

    // One edge resolved to node indices, parallel to `edges`.
    struct EdgeIndex: Equatable, Sendable {
        let a: Int
        let b: Int
    }

    // d3's link defaults, per edge: strength 1 / min(degree) so a hub's many springs don't add up
    // to an overshoot, and a bias that moves the lower-degree end more.
    private struct SpringShape {
        let strength: Double
        let biasTowardB: Double
    }

    // d3's own default phyllotaxis constant, reused for the zero-distance fallback direction too.
    static let goldenAngle: Double = Double.pi * (3 - sqrt(5))
    static let dragAlphaTarget: Double = 0.3
    static let updateReheat: Double = 0.3
    static let resizeReheat: Double = 0.05

    let alphaMin: Double = 0.001
    let alphaDecay: Double = 1 - pow(0.001, 1.0 / 300.0)
    let velocityDecay: Double = 0.6
    private(set) var alpha: Double = 1.0
    // What alpha eases toward each tick. Zero lets the layout cool and stop; a drag holds it up.
    var alphaTarget: Double = 0

    // Bumped by every update that changes anything a drawing depends on, so a cache can key on it.
    private(set) var topologyVersion = 0

    private(set) var nodes: [Node]
    // Only edges whose ends are both nodes, in the same order as `edgeIndices`.
    private(set) var edges: [EntityGraph.Edge]
    private(set) var edgeIndices: [EdgeIndex]
    private var springShapes: [SpringShape]
    private var indexByID: [UUID: Int]

    private var positions: [SIMD2<Double>]
    private var velocities: [SIMD2<Double>]
    private var radii: [Double]
    private var pinned: [Bool]
    private var anchored: [Bool]
    private var pinPoints: [SIMD2<Double>]

    init(nodes: [Node], edges: [EntityGraph.Edge]) {
        let unique = Self.deduplicated(nodes)
        let map = Self.indexMap(unique)
        let resolved = Self.resolve(edges, in: map)
        self.nodes = unique
        indexByID = map
        self.edges = resolved.edges
        edgeIndices = resolved.indices
        springShapes = Self.springShapes(resolved.indices, nodeCount: unique.count)
        positions = unique.indices.map(Self.phyllotaxis)
        velocities = Array(repeating: .zero, count: unique.count)
        radii = unique.map { Self.radius(linkCount: $0.linkCount) }
        pinned = Array(repeating: false, count: unique.count)
        anchored = Array(repeating: false, count: unique.count)
        pinPoints = Array(repeating: .zero, count: unique.count)
    }

    var settled: Bool { alpha <= alphaMin && alphaTarget <= alphaMin }

    // MARK: - Reading

    var nodeCount: Int { nodes.count }

    func position(at index: Int) -> SIMD2<Double> { positions[index] }

    func radius(at index: Int) -> Double { radii[index] }

    func index(of id: UUID) -> Int? { indexByID[id] }

    func position(of id: UUID) -> SIMD2<Double>? {
        indexByID[id].map { positions[$0] }
    }

    func radius(of id: UUID) -> Double? {
        indexByID[id].map { radii[$0] }
    }

    func kind(of id: UUID) -> EntityKind? {
        indexByID[id].map { nodes[$0].kind }
    }

    func linkCount(of id: UUID) -> Int? {
        indexByID[id].map { nodes[$0].linkCount }
    }

    func allNodeIDs() -> [UUID] {
        nodes.map(\.id)
    }

    func allEdges() -> [EntityGraph.Edge] {
        edges
    }

    // MARK: - Pinning

    // Sticky: stays pinned until unpin. An anchored node ignores this too, the same as unpin: its
    // point is permanent, and a caller (a drag gesture that hit-tested the wrong node) must not be
    // able to move it through this API either.
    func pin(_ id: UUID, at point: SIMD2<Double>) {
        guard let index = indexByID[id], !anchored[index] else { return }
        pinned[index] = true
        pinPoints[index] = point
    }

    func unpin(_ id: UUID) {
        guard let index = indexByID[id], !anchored[index] else { return }
        pinned[index] = false
    }

    func isPinned(_ id: UUID) -> Bool {
        indexByID[id].map { pinned[$0] } ?? false
    }

    // A permanent pin with no unpin, for the local graph's centred subject.
    func anchor(_ id: UUID, at point: SIMD2<Double>) {
        guard let index = indexByID[id] else { return }
        anchored[index] = true
        pinned[index] = true
        pinPoints[index] = point
    }

    // MARK: - Warming

    // Never cools: a reheat during a drag or a larger reheat already running keeps its alpha.
    func reheat(to value: Double) {
        alpha = max(alpha, value)
    }

    // Replaces the node and edge sets in place. Surviving ids keep their position, velocity, and
    // pins and take the new kind and link count. A new node starts beside its strongest neighbour
    // that already has a place, so it grows out of the cluster it belongs to; one with no such
    // neighbour gets its phyllotaxis point. Reheats only when the id or edge sets changed, so a
    // rename (which bumps graph.revision and lands here with the same sets) doesn't jolt anything.
    func update(nodes newNodes: [Node], edges newEdges: [EntityGraph.Edge]) {
        let unique = Self.deduplicated(newNodes)
        let map = Self.indexMap(unique)
        let resolved = Self.resolve(newEdges, in: map)

        let sameNodes = Set(unique) == Set(nodes)
        let sameEdges = Set(resolved.edges) == Set(edges)
        if sameNodes && sameEdges { return }
        let shapeChanged = Set(unique.map(\.id)) != Set(nodes.map(\.id))
            || Set(resolved.edges.map(\.key)) != Set(edges.map(\.key))

        var newPositions = [SIMD2<Double>](repeating: .zero, count: unique.count)
        var newVelocities = [SIMD2<Double>](repeating: .zero, count: unique.count)
        var newPinned = [Bool](repeating: false, count: unique.count)
        var newAnchored = [Bool](repeating: false, count: unique.count)
        var newPinPoints = [SIMD2<Double>](repeating: .zero, count: unique.count)
        let newRadii = unique.map { Self.radius(linkCount: $0.linkCount) }
        var placed = [Bool](repeating: false, count: unique.count)

        for (index, node) in unique.enumerated() {
            guard let old = indexByID[node.id] else { continue }
            newPositions[index] = positions[old]
            newVelocities[index] = velocities[old]
            newPinned[index] = pinned[old]
            newAnchored[index] = anchored[old]
            newPinPoints[index] = pinPoints[old]
            placed[index] = true
        }

        var neighbours: [[(index: Int, weight: Double)]] = Array(repeating: [], count: unique.count)
        for (edge, pair) in zip(resolved.edges, resolved.indices) {
            neighbours[pair.a].append((pair.b, edge.weight))
            neighbours[pair.b].append((pair.a, edge.weight))
        }

        for index in unique.indices where !placed[index] {
            let best = neighbours[index]
                .filter { placed[$0.index] }
                .min { lhs, rhs in
                    if lhs.weight != rhs.weight { return lhs.weight > rhs.weight }
                    return unique[lhs.index].id.uuidString < unique[rhs.index].id.uuidString
                }
            if let best {
                let angle = Double(index) * Self.goldenAngle
                let gap = newRadii[best.index] + newRadii[index] + 8
                newPositions[index] = newPositions[best.index] + SIMD2(cos(angle), sin(angle)) * gap
            } else {
                newPositions[index] = Self.phyllotaxis(index)
            }
            placed[index] = true
        }

        let indexByIDBefore = indexByID
        let radiiBefore = radii
        nodes = unique
        indexByID = map
        edges = resolved.edges
        edgeIndices = resolved.indices
        springShapes = Self.springShapes(resolved.indices, nodeCount: unique.count)
        positions = newPositions
        velocities = newVelocities
        radii = newRadii
        pinned = newPinned
        anchored = newAnchored
        pinPoints = newPinPoints
        let radiiChanged = newRadii != unique.map { node in indexByIDBefore[node.id].map { radiiBefore[$0] } ?? -1 }
        topologyVersion += 1
        if shapeChanged {
            reheat(to: Self.updateReheat)
        } else if radiiChanged {
            // A node that grew needs room, but not a jolt.
            reheat(to: Self.resizeReheat)
        }
    }

    // MARK: - Geometry

    // Kept small so a 200-node graph reads as a map rather than a wall of discs: 5pt for a
    // single mention, 16pt at about 80.
    static func radius(linkCount: Int) -> Double {
        min(16, 3.5 + sqrt(Double(max(linkCount, 1))) * 1.4)
    }

    static func targetDistance(weight: Double) -> Double {
        max(24, 70 - 30 * min(weight, 1))
    }

    private static func phyllotaxis(_ index: Int) -> SIMD2<Double> {
        let angle = Double(index) * goldenAngle
        let radius = sqrt(Double(index) + 0.5) * 12
        return SIMD2(radius * cos(angle), radius * sin(angle))
    }

    // First occurrence wins, so the arrays and the id map can never disagree.
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
            // Clamp pinned/anchored positions before forces run, so a force computed against a
            // pin's old position in this same tick can't move it after the clamp.
            for index in 0..<nodes.count where pinned[index] {
                positions[index] = pinPoints[index]
                velocities[index] = .zero
            }

            applyRepulsion()
            applySprings()
            applyGravity()
            applyCollision()

            for index in 0..<nodes.count where !pinned[index] {
                velocities[index] *= (1 - velocityDecay)
                positions[index] += velocities[index]
            }
        }

        alpha += (alphaTarget - alpha) * alphaDecay
    }

    // Two nodes closer than 1 unit are 1 unit apart for the force magnitude; the direction is a
    // separate unit vector that a literally-zero distance turns into 0/0. A user can drag one
    // pinned node onto another pinned node's exact point, so this fallback has to hold at any
    // alpha, not just at tick zero.
    private func direction(_ i: Int, _ j: Int, dx: Double, dy: Double, distance: Double) -> SIMD2<Double> {
        guard distance > 0 else {
            let angle = Double(min(i, j)) * Self.goldenAngle
            return SIMD2(cos(angle), sin(angle))
        }
        return SIMD2(dx / distance, dy / distance)
    }

    // Every unpinned pair pushes apart with strength / distance, d3's forceManyBody falloff. An
    // inverse-square falloff was too weak at range: the 300-entry demo graph packed into one
    // blob held apart only by collision. Applied as a positive push-apart magnitude directly
    // (rather than d3's negative-charge convention) and scaled by alpha so it fades with
    // everything else.
    private func applyRepulsion() {
        guard nodes.count > 1 else { return }
        let strength = 30.0 * alpha
        for i in 0..<nodes.count {
            for j in (i + 1)..<nodes.count {
                if pinned[i] && pinned[j] { continue }
                let dx = positions[i].x - positions[j].x
                let dy = positions[i].y - positions[j].y
                let distance = (dx * dx + dy * dy).squareRoot()
                let dir = direction(i, j, dx: dx, dy: dy, distance: distance)
                let magnitude = strength / max(distance, 1)
                if !pinned[i] { velocities[i] += dir * magnitude }
                if !pinned[j] { velocities[j] -= dir * magnitude }
            }
        }
    }

    // Every edge pulls its two ends toward targetDistance(weight:), scaled by 1 / min(degree) the
    // way d3's forceLink is; without that, a node with dozens of edges takes dozens of full-size
    // corrections a tick and the 300-entry demo graph flew apart. The ends share the correction
    // by degree (the busier end moves less) unless one is pinned or anchored, in which case the
    // unpinned end takes it whole.
    private func applySprings() {
        for ((edge, pair), shape) in zip(zip(edges, edgeIndices), springShapes) {
            let i = pair.a, j = pair.b
            let dx = positions[j].x - positions[i].x
            let dy = positions[j].y - positions[i].y
            let distance = (dx * dx + dy * dy).squareRoot()
            let dir = direction(i, j, dx: dx, dy: dy, distance: distance)
            let magnitude = alpha * (distance - Self.targetDistance(weight: edge.weight)) * shape.strength
            let correction = dir * magnitude

            let iFixed = pinned[i], jFixed = pinned[j]
            if iFixed && jFixed { continue }
            if iFixed {
                velocities[j] -= correction
            } else if jFixed {
                velocities[i] += correction
            } else {
                velocities[i] += correction * (1 - shape.biasTowardB)
                velocities[j] -= correction * shape.biasTowardB
            }
        }
    }

    // A weak per-node pull toward the canvas origin, rather than d3's default forceCenter (which
    // recentres by translating every node, pinned or not): a local graph anchors its subject at
    // the origin for the whole simulation, and translating that anchor would drag the one point
    // the view promises stays still.
    private func applyGravity() {
        for index in 0..<nodes.count where !pinned[index] {
            velocities[index] += -positions[index] * 0.01 * alpha
        }
    }

    // Any unpinned pair closer than the sum of their radii is pushed apart along their separating
    // vector by half the overlap each. A loose bounding check runs first so this stays cheap once
    // most pairs have separated at low alpha.
    private func applyCollision() {
        for i in 0..<nodes.count {
            for j in (i + 1)..<nodes.count {
                if pinned[i] && pinned[j] { continue }
                let sumRadii = radii[i] + radii[j]
                let dx = positions[j].x - positions[i].x
                let dy = positions[j].y - positions[i].y
                guard abs(dx) < sumRadii, abs(dy) < sumRadii else { continue }
                let distance = (dx * dx + dy * dy).squareRoot()
                guard distance < sumRadii else { continue }
                let overlap = (sumRadii - distance) * 0.5
                let dir = direction(i, j, dx: dx, dy: dy, distance: distance)
                if !pinned[i] { velocities[i] -= dir * overlap }
                if !pinned[j] { velocities[j] += dir * overlap }
            }
        }
    }
}
