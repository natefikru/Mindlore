import Foundation

// The parts of the graph canvas that aren't SwiftUI: the camera, what to draw for a given focus,
// hit-testing, when to stop redrawing, and frame timing. The canvas holds the classes in @State,
// which keeps the references alive across parent re-renders; their fields are written from
// gestures and the draw closure without invalidating any view.

// MARK: - Camera

nonisolated final class GraphCamera {
    static let readableZoom: Double = 1.6
    static let zoomRange: ClosedRange<Double> = 0.2...4
    static let flightDuration: TimeInterval = 0.35

    // Screen offset of the world origin from the view's centre, in points.
    var pan: SIMD2<Double> = .zero
    var zoom: Double = 1

    private struct Flight {
        let fromPan: SIMD2<Double>
        let toPan: SIMD2<Double>
        let fromZoom: Double
        let toZoom: Double
        let start: TimeInterval
    }

    private var flight: Flight?

    var isFlying: Bool { flight != nil }

    func screen(_ world: SIMD2<Double>, center: SIMD2<Double>) -> SIMD2<Double> {
        center + world * zoom + pan
    }

    func world(_ screen: SIMD2<Double>, center: SIMD2<Double>) -> SIMD2<Double> {
        (screen - center - pan) / zoom
    }

    // Centres a world point, zooming in to a readable level if the camera is further out.
    func fly(to point: SIMD2<Double>, now: TimeInterval) {
        let targetZoom = Self.clamped(max(zoom, Self.readableZoom))
        flight = Flight(fromPan: pan, toPan: -point * targetZoom, fromZoom: zoom, toZoom: targetZoom, start: now)
    }

    func cancelFlight() {
        flight = nil
    }

    // Moves the camera along a running flight. Past the duration it lands exactly on the target
    // rather than trusting the easing curve to reach 1. Returns whether a flight is still running.
    @discardableResult
    func advance(now: TimeInterval) -> Bool {
        guard let flight else { return false }
        let t = (now - flight.start) / Self.flightDuration
        guard t < 1 else {
            pan = flight.toPan
            zoom = flight.toZoom
            self.flight = nil
            return false
        }
        let clampedT = max(0, t)
        let eased = clampedT * clampedT * (3 - 2 * clampedT)
        zoom = flight.fromZoom + (flight.toZoom - flight.fromZoom) * eased
        pan = flight.fromPan + (flight.toPan - flight.fromPan) * eased
        return true
    }

    // Zooms so the world point under `anchor` (a screen point, the pinch's centre) stays put.
    func setZoom(_ newZoom: Double, keeping anchor: SIMD2<Double>, center: SIMD2<Double>) {
        let pinned = world(anchor, center: center)
        zoom = Self.clamped(newZoom)
        pan = anchor - center - pinned * zoom
    }

    private static func clamped(_ value: Double) -> Double {
        min(zoomRange.upperBound, max(zoomRange.lowerBound, value))
    }
}

// MARK: - What to draw

nonisolated struct GraphEdgeStyle: Hashable, Sendable {
    // 0...3 each, so a frame strokes at most 16 paths however many edges there are.
    let widthBucket: Int
    let opacityBucket: Int

    static let bucketCount = 4

    init(widthBucket: Int, opacityBucket: Int) {
        self.widthBucket = widthBucket
        self.opacityBucket = opacityBucket
    }

    // Width from how much a pair shares, opacity from how lately.
    init(weight: Double, recency: Double) {
        widthBucket = [0.5, 1.5, 3].filter { weight >= $0 }.count
        opacityBucket = [0.125, 0.25, 0.5].filter { recency >= $0 }.count
    }

    var lineWidth: Double { 0.75 + Double(widthBucket) * 0.75 }
    var opacity: Double { [0.15, 0.25, 0.4, 0.6][opacityBucket] }
}

nonisolated struct GraphDrawPlan: Sendable {
    // Nil when nothing is focused or the focused id is no longer in the simulation.
    let focusedIndex: Int?
    // The focused node and its direct neighbours, as node indices. Empty without a focus.
    let litNodes: Set<Int>
    // Edge positions (into GraphSimulation.edges) touching the focused node.
    let litEdges: Set<Int>
    // Node indices in label priority order: focus, its neighbours, then everything by size.
    let rankedLabels: [Int]
    // The focus and its biggest neighbours (at most 1 + focusLabelCap), the only nodes that glow,
    // so focusing a hub doesn't cost a gradient fill per neighbour every frame.
    let glowNodes: [Int]
    let edgeStyles: [GraphEdgeStyle]

    static let empty = GraphDrawPlan(focusedIndex: nil, litNodes: [], litEdges: [], rankedLabels: [], glowNodes: [], edgeStyles: [])

    var hasFocus: Bool { focusedIndex != nil }
}

// Recomputes the plan only when the simulation's topology or the focus changes, so a frame pays
// for a key comparison, never for sorting or neighbour walks. Zoom never enters the key: it only
// picks how much of `rankedLabels` to show.
nonisolated final class GraphDrawCache {
    static let labelCap = 60
    static let focusLabelCap = 24

    private struct Key: Equatable {
        let simulation: ObjectIdentifier
        let version: Int
        let focusedID: UUID?
    }

    private var key: Key?
    private var cached = GraphDrawPlan.empty
    private(set) var recomputeCount = 0

    func plan(for simulation: GraphSimulation, focusedID: UUID?) -> GraphDrawPlan {
        let current = Key(simulation: ObjectIdentifier(simulation), version: simulation.topologyVersion, focusedID: focusedID)
        if current == key { return cached }
        key = current
        cached = Self.makePlan(simulation, focusedID: focusedID)
        recomputeCount += 1
        return cached
    }

    private static func makePlan(_ simulation: GraphSimulation, focusedID: UUID?) -> GraphDrawPlan {
        let nodes = simulation.nodes
        let sortKeys = nodes.map(\.id.uuidString)
        func ranksBefore(_ lhs: Int, _ rhs: Int) -> Bool {
            if nodes[lhs].linkCount != nodes[rhs].linkCount { return nodes[lhs].linkCount > nodes[rhs].linkCount }
            return sortKeys[lhs] < sortKeys[rhs]
        }

        let styles = simulation.edges.map { GraphEdgeStyle(weight: $0.weight, recency: $0.recency) }
        let focusedIndex = focusedID.flatMap { simulation.index(of: $0) }

        var litNodes: Set<Int> = []
        var litEdges: Set<Int> = []
        var head: [Int] = []
        if let focusedIndex {
            litNodes.insert(focusedIndex)
            for (position, pair) in simulation.edgeIndices.enumerated() {
                if pair.a == focusedIndex {
                    litNodes.insert(pair.b)
                } else if pair.b == focusedIndex {
                    litNodes.insert(pair.a)
                } else {
                    continue
                }
                litEdges.insert(position)
            }
            let neighbours = litNodes.subtracting([focusedIndex]).sorted(by: ranksBefore)
            head = [focusedIndex] + neighbours.prefix(focusLabelCap)
        }

        let headSet = Set(head)
        let rest = nodes.indices.filter { !headSet.contains($0) }.sorted(by: ranksBefore)
        let ranked = head + rest.prefix(max(0, labelCap - head.count))

        return GraphDrawPlan(
            focusedIndex: focusedIndex,
            litNodes: litNodes,
            litEdges: litEdges,
            rankedLabels: ranked,
            glowNodes: head,
            edgeStyles: styles
        )
    }
}

nonisolated enum GraphLabels {
    // 12 labels at 1x, more as the user zooms in.
    static func budget(zoom: Double) -> Int {
        min(GraphDrawCache.labelCap, max(6, Int((12 * zoom * zoom).rounded())))
    }

    // Full strength for the first 70% of the budget, then fading to 0.25 at the last label.
    static func opacity(rank: Int, budget: Int) -> Double {
        guard rank < budget else { return 0 }
        let full = Int((Double(budget) * 0.7).rounded(.up))
        guard rank >= full else { return 1 }
        let fadeSteps = Double(budget - full)
        return 1 - 0.75 * Double(rank - full + 1) / fadeSteps
    }
}

// MARK: - Hit-testing

nonisolated enum GraphHitTest {
    static let edgeTolerance: Double = 10
    static let minimumNodeRadius: Double = 12

    static func distance(from point: SIMD2<Double>, toSegment a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
        let ab = b - a
        let lengthSquared = (ab * ab).sum()
        let t = lengthSquared > 0 ? min(1, max(0, ((point - a) * ab).sum() / lengthSquared)) : 0
        let d = point - (a + ab * t)
        return (d * d).sum().squareRoot()
    }

    // The closest segment within tolerance, all in screen points.
    static func edge(at point: SIMD2<Double>, segments: [(SIMD2<Double>, SIMD2<Double>)], tolerance: Double = edgeTolerance) -> Int? {
        var best: (index: Int, distance: Double)?
        for (index, segment) in segments.enumerated() {
            let d = distance(from: point, toSegment: segment.0, segment.1)
            guard d <= tolerance, d < (best?.distance ?? .infinity) else { continue }
            best = (index, d)
        }
        return best?.index
    }

    // The topmost (last drawn) node whose circle, at least 12pt, contains the point.
    static func node(at point: SIMD2<Double>, count: Int, circle: (Int) -> (center: SIMD2<Double>, radius: Double)) -> Int? {
        for index in stride(from: count - 1, through: 0, by: -1) {
            let (center, radius) = circle(index)
            let d = point - center
            if (d * d).sum().squareRoot() <= max(radius, minimumNodeRadius) { return index }
        }
        return nil
    }
}

// MARK: - Redraw

nonisolated enum GraphRedraw {
    static let idleDelay: TimeInterval = 2

    static func isActive(settled: Bool, gestureActive: Bool, flying: Bool) -> Bool {
        !settled || gestureActive || flying
    }

    // Keeps drawing while anything moves and for two seconds after the last of it.
    static func shouldPause(settled: Bool, gestureActive: Bool, flying: Bool, lastActive: TimeInterval, now: TimeInterval) -> Bool {
        !isActive(settled: settled, gestureActive: gestureActive, flying: flying) && now - lastActive >= idleDelay
    }
}

// MARK: - Frame timing

// Samples frames drawn while the user interacts. The interval between draw calls is the number
// the device gate reads (a dropped frame shows up as a long interval); the closure's own work time
// says whether a slow interval was this code or the renderer. A gap over 0.25 s is a resume after
// a pause or a stalled touch, not a frame, and is skipped.
nonisolated final class FrameTimeSampler {
    static let targetSeconds: Double = 5
    static let maximumGap: Double = 0.25

    private var lastFrame: TimeInterval?
    private(set) var intervals: [Double] = []
    private(set) var workTimes: [Double] = []

    func record(frameStart: TimeInterval, workSeconds: Double, interacting: Bool) {
        defer { lastFrame = interacting ? frameStart : nil }
        guard interacting else { return }
        workTimes.append(workSeconds)
        if let lastFrame, frameStart - lastFrame < Self.maximumGap, frameStart > lastFrame {
            intervals.append(frameStart - lastFrame)
        }
    }

    var sampledSeconds: Double { intervals.reduce(0, +) }
    var isComplete: Bool { sampledSeconds >= Self.targetSeconds }

    // Nearest-rank percentile, nil for no samples.
    static func percentile(_ values: [Double], _ fraction: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let rank = Int((fraction * Double(sorted.count)).rounded(.up))
        return sorted[min(sorted.count, max(1, rank)) - 1]
    }
}

// MARK: - Render report

// What graph.rendered logs once per appearance: counts and durations only.
nonisolated struct GraphRenderStats: Equatable, Sendable {
    let nodes: Int
    let edges: Int
    // Nil when the layout never settled while the graph was on screen.
    let settleMilliseconds: Double?
    let frameSamples: Int
    let frameP50Milliseconds: Double?
    let frameP95Milliseconds: Double?
    let workP95Milliseconds: Double?
}

nonisolated extension GraphSimulation.Node {
    // Biggest first, so the phyllotaxis start puts the hubs in the middle, and a stable order
    // however the caller's set happened to iterate.
    static func layoutOrdered(_ nodes: [GraphSimulation.Node]) -> [GraphSimulation.Node] {
        nodes.sorted { lhs, rhs in
            lhs.linkCount != rhs.linkCount ? lhs.linkCount > rhs.linkCount : lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
