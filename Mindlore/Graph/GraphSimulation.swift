import Foundation

// A force layout over EntityGraph's edges. Plain, non-Observable class: the canvas ticks it from
// inside its own draw closure every frame, and an @Observable write there would trip "modifying
// state during view update" the way a plain class reference never does. Positions are parallel
// arrays over SIMD2<Double>, one entry per node, indexed by the node's position in the `nodes`
// array passed to init; `indexByID` resolves ids into that index once, the same "resolve into an
// in-memory map once" shape GraphServices.mentionedWith already uses for entities.
nonisolated final class GraphSimulation {
    struct Node: Sendable {
        let id: UUID
        let kind: EntityKind
        let linkCount: Int

        init(id: UUID, kind: EntityKind, linkCount: Int) {
            self.id = id
            self.kind = kind
            self.linkCount = linkCount
        }
    }

    // d3's own default phyllotaxis constant, reused for the zero-distance fallback direction too.
    static let goldenAngle: Double = Double.pi * (3 - sqrt(5))

    let alphaMin: Double = 0.001
    let alphaDecay: Double = 1 - pow(0.001, 1.0 / 300.0)
    let velocityDecay: Double = 0.6
    private(set) var alpha: Double = 1.0

    private let nodes: [Node]
    private let edges: [EntityGraph.Edge]
    private let indexByID: [UUID: Int]

    private var positions: [SIMD2<Double>]
    private var velocities: [SIMD2<Double>]
    private var pinned: [Bool]
    private var anchored: [Bool]
    private var pinPoints: [SIMD2<Double>]

    init(nodes: [Node], edges: [EntityGraph.Edge]) {
        self.nodes = nodes
        self.edges = edges

        var map: [UUID: Int] = [:]
        map.reserveCapacity(nodes.count)
        for (index, node) in nodes.enumerated() { map[node.id] = index }
        indexByID = map

        positions = (0..<nodes.count).map { index in
            let angle = Double(index) * Self.goldenAngle
            let radius = sqrt(Double(index) + 0.5) * 12
            return SIMD2(radius * cos(angle), radius * sin(angle))
        }
        velocities = Array(repeating: .zero, count: nodes.count)
        pinned = Array(repeating: false, count: nodes.count)
        anchored = Array(repeating: false, count: nodes.count)
        pinPoints = Array(repeating: .zero, count: nodes.count)
    }

    var settled: Bool { alpha <= alphaMin }

    func position(of id: UUID) -> SIMD2<Double>? {
        indexByID[id].map { positions[$0] }
    }

    func radius(of id: UUID) -> Double? {
        indexByID[id].map { Self.radius(linkCount: nodes[$0].linkCount) }
    }

    func kind(of id: UUID) -> EntityKind? {
        indexByID[id].map { nodes[$0].kind }
    }

    func linkCount(of id: UUID) -> Int? {
        indexByID[id].map { nodes[$0].linkCount }
    }

    // For the canvas, which draws every node and edge itself rather than re-deriving the topology
    // from GraphData a second time; array order matches init's, so it stays stable across ticks.
    func allNodeIDs() -> [UUID] {
        nodes.map(\.id)
    }

    func allEdges() -> [EntityGraph.Edge] {
        edges
    }

    // Sticky: stays pinned until unpin.
    func pin(_ id: UUID, at point: SIMD2<Double>) {
        guard let index = indexByID[id] else { return }
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

    static func radius(linkCount: Int) -> Double {
        min(28, 6 + sqrt(Double(max(linkCount, 1))) * 4)
    }

    static func targetDistance(weight: Double) -> Double {
        max(24, 70 - 30 * min(weight, 1))
    }

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

        alpha += (0 - alpha) * alphaDecay
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

    // Every unpinned pair pushes apart. Applied as a positive push-apart magnitude directly
    // (rather than d3's own negative-charge convention, which encodes the same repulsion through
    // its own force-application sign) scaled by alpha so it fades with everything else.
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
                let magnitude = strength / pow(max(distance, 1), 2)
                if !pinned[i] { velocities[i] += dir * magnitude }
                if !pinned[j] { velocities[j] -= dir * magnitude }
            }
        }
    }

    // Every edge pulls its two ends toward targetDistance(weight:). Both ends take half the
    // correction unless one is pinned or anchored, in which case the unpinned end takes it whole.
    private func applySprings() {
        for edge in edges {
            guard let i = indexByID[edge.a], let j = indexByID[edge.b] else { continue }
            let dx = positions[j].x - positions[i].x
            let dy = positions[j].y - positions[i].y
            let distance = (dx * dx + dy * dy).squareRoot()
            let dir = direction(i, j, dx: dx, dy: dy, distance: distance)
            let magnitude = alpha * (distance - Self.targetDistance(weight: edge.weight)) * 0.3
            let correction = dir * magnitude

            let iFixed = pinned[i], jFixed = pinned[j]
            if iFixed && jFixed { continue }
            if iFixed {
                velocities[j] -= correction
            } else if jFixed {
                velocities[i] += correction
            } else {
                velocities[i] += correction * 0.5
                velocities[j] -= correction * 0.5
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
                let sumRadii = Self.radius(linkCount: nodes[i].linkCount) + Self.radius(linkCount: nodes[j].linkCount)
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
