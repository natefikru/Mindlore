import Foundation
import SwiftUI
import Testing
@testable import Mindlore

struct GraphCanvasModelTests {
    private func node(_ linkCount: Int, id: UUID = UUID()) -> GraphSimulation.Node {
        GraphSimulation.Node(id: id, kind: .person, linkCount: linkCount)
    }

    private func close(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Bool {
        abs(a.x - b.x) < 1e-9 && abs(a.y - b.y) < 1e-9
    }

    // A hub with three spokes plus two loose nodes.
    private func hub() -> (simulation: GraphSimulation, nodes: [GraphSimulation.Node]) {
        let nodes = [node(9), node(3), node(2), node(1), node(7), node(5)]
        let edges = (1...3).map { EntityGraph.Edge(nodes[0].id, nodes[$0].id, weight: 1) }
            + [EntityGraph.Edge(nodes[4].id, nodes[5].id, weight: 1)]
        return (GraphSimulation(nodes: nodes, edges: edges), nodes)
    }

    // MARK: - Draw cache

    @Test func repeatedPlansComputeOnce() {
        let (simulation, nodes) = hub()
        let cache = GraphDrawCache()
        for _ in 0..<10 {
            _ = cache.plan(for: simulation, focusedID: nil)
        }
        #expect(cache.recomputeCount == 1)
        for _ in 0..<10 {
            _ = cache.plan(for: simulation, focusedID: nodes[0].id)
        }
        #expect(cache.recomputeCount == 2)
    }

    @Test func planRecomputesOnTopologyChangeButNotOnTicks() {
        let (simulation, nodes) = hub()
        let cache = GraphDrawCache()
        _ = cache.plan(for: simulation, focusedID: nil)
        for _ in 0..<20 { simulation.tick() }
        _ = cache.plan(for: simulation, focusedID: nil)
        #expect(cache.recomputeCount == 1)
        simulation.update(nodes: nodes + [node(1)], edges: simulation.allEdges())
        let plan = cache.plan(for: simulation, focusedID: nil)
        #expect(cache.recomputeCount == 2)
        #expect(plan.rankedLabels.count == 7)
    }

    // The draw closure indexes edgeStyles by edge position, so they must line up after any update.
    @Test func edgeStylesLineUpWithEdgesAfterAnUpdate() {
        let (simulation, nodes) = hub()
        let cache = GraphDrawCache()
        #expect(cache.plan(for: simulation, focusedID: nil).edgeStyles.count == simulation.edgeIndices.count)
        let extra = node(2)
        simulation.update(nodes: nodes + [extra], edges: simulation.allEdges() + [
            EntityGraph.Edge(extra.id, nodes[5].id, weight: 3, recency: 0.1),
            EntityGraph.Edge(extra.id, UUID(), weight: 1),
        ])
        let plan = cache.plan(for: simulation, focusedID: nil)
        #expect(plan.edgeStyles.count == simulation.edgeIndices.count)
        for (style, edge) in zip(plan.edgeStyles, simulation.allEdges()) {
            #expect(style == GraphEdgeStyle(weight: edge.weight, recency: edge.recency))
        }
    }

    @Test func zoomNeverRecomputesThePlan() {
        let (simulation, _) = hub()
        let cache = GraphDrawCache()
        let camera = GraphCamera()
        for zoom in stride(from: 0.5, through: 4, by: 0.25) {
            camera.setZoom(zoom, keeping: .zero, center: .zero)
            let plan = cache.plan(for: simulation, focusedID: nil)
            _ = plan.rankedLabels.prefix(GraphLabels.budget(zoom: camera.zoom))
        }
        #expect(cache.recomputeCount == 1)
    }

    @Test func focusLightsTheNodeItsNeighboursAndTheirEdges() {
        let (simulation, nodes) = hub()
        let plan = GraphDrawCache().plan(for: simulation, focusedID: nodes[1].id)
        let lit = Set(plan.litNodes.map { simulation.nodes[$0].id })
        #expect(lit == [nodes[1].id, nodes[0].id])
        #expect(plan.litEdges.count == 1)
        let edge = simulation.allEdges()[plan.litEdges.first!]
        #expect(Set([edge.a, edge.b]) == [nodes[0].id, nodes[1].id])
        #expect(plan.focusedIndex == simulation.index(of: nodes[1].id))
    }

    // An area tile brings a group forward; focus says more, so it still lights its own set.
    @Test func aHighlightMarksItsNodesAndFocusStillLights() {
        let (simulation, nodes) = hub()
        let cache = GraphDrawCache()
        let group: Set<UUID> = [nodes[0].id, nodes[1].id, UUID()]

        let plan = cache.plan(for: simulation, focusedID: nil, highlighted: group)
        #expect(plan.highlightedNodes?.count == 2, "an id off the map is ignored")
        #expect(plan.isHighlighted(simulation.index(of: nodes[0].id)!))
        #expect(!plan.isHighlighted(simulation.index(of: nodes[4].id)!))

        let focused = cache.plan(for: simulation, focusedID: nodes[4].id, highlighted: group)
        #expect(focused.hasFocus)
        #expect(focused.litNodes.contains(simulation.index(of: nodes[5].id)!))

        let none = cache.plan(for: simulation, focusedID: nil)
        #expect(none.highlightedNodes == nil)
        #expect(none.isHighlighted(0))
    }

    @Test func thePlanRecomputesOnAHighlightChangeOnly() {
        let (simulation, nodes) = hub()
        let cache = GraphDrawCache()
        let group: Set<UUID> = [nodes[0].id]
        _ = cache.plan(for: simulation, focusedID: nil, highlighted: group)
        _ = cache.plan(for: simulation, focusedID: nil, highlighted: group)
        #expect(cache.recomputeCount == 1)
        _ = cache.plan(for: simulation, focusedID: nil, highlighted: [nodes[1].id])
        _ = cache.plan(for: simulation, focusedID: nil, highlighted: nil)
        #expect(cache.recomputeCount == 3)
    }

    // A focused node lands in the middle of what the panel and card leave uncovered.
    @Test func aFlightCanLandOffCentre() {
        let camera = GraphCamera()
        let center = SIMD2<Double>(200, 400)
        let point = SIMD2<Double>(30, -20)
        let offset = SIMD2<Double>(0, -150)
        camera.fly(to: point, now: 0, offset: offset)
        camera.advance(now: 10)
        #expect(close(camera.screen(point, center: center), center + offset))
    }

    @Test func noFocusAndAMissingFocusLightNothing() {
        let (simulation, _) = hub()
        let cache = GraphDrawCache()
        for focus in [nil, UUID()] {
            let plan = cache.plan(for: simulation, focusedID: focus)
            #expect(!plan.hasFocus)
            #expect(plan.litNodes.isEmpty)
            #expect(plan.litEdges.isEmpty)
        }
    }

    @Test func labelsRankBySizeWithoutFocus() {
        let (simulation, nodes) = hub()
        let plan = GraphDrawCache().plan(for: simulation, focusedID: nil)
        let order = plan.rankedLabels.map { simulation.nodes[$0].id }
        #expect(order == [nodes[0], nodes[4], nodes[5], nodes[1], nodes[2], nodes[3]].map(\.id))
    }

    @Test func labelsPutTheFocusAndItsNeighboursFirst() {
        let (simulation, nodes) = hub()
        let plan = GraphDrawCache().plan(for: simulation, focusedID: nodes[3].id)
        let order = plan.rankedLabels.map { simulation.nodes[$0].id }
        #expect(order == [nodes[3], nodes[0], nodes[4], nodes[5], nodes[1], nodes[2]].map(\.id))
    }

    @Test func labelsAreCappedAndFocusNeighboursAreCapped() {
        let center = node(1)
        let spokes = (0..<100).map { node($0 + 2) }
        let edges = spokes.map { EntityGraph.Edge(center.id, $0.id, weight: 1) }
        let simulation = GraphSimulation(nodes: [center] + spokes, edges: edges)
        let cache = GraphDrawCache()
        #expect(cache.plan(for: simulation, focusedID: nil).rankedLabels.count == GraphDrawCache.labelCap)

        let focused = cache.plan(for: simulation, focusedID: center.id)
        #expect(focused.rankedLabels.count == GraphDrawCache.labelCap)
        #expect(focused.rankedLabels.first == simulation.index(of: center.id))
        // The biggest 24 neighbours come right after the focus.
        let neighbourIDs = focused.rankedLabels[1...GraphDrawCache.focusLabelCap].map { simulation.nodes[$0].id }
        #expect(Set(neighbourIDs) == Set(spokes.suffix(GraphDrawCache.focusLabelCap).map(\.id)))
        #expect(focused.litNodes.count == 101)
        // Only the focus and its capped head glow, not all 100 neighbours.
        #expect(focused.glowNodes == Array(focused.rankedLabels.prefix(1 + GraphDrawCache.focusLabelCap)))
        #expect(cache.plan(for: simulation, focusedID: nil).glowNodes.isEmpty)
    }

    @Test func edgeStylesFollowWeightAndRecency() {
        #expect(GraphEdgeStyle(weight: 0.2, recency: 0.05) == GraphEdgeStyle(widthBucket: 0, opacityBucket: 0))
        #expect(GraphEdgeStyle(weight: 1, recency: 0.3) == GraphEdgeStyle(widthBucket: 1, opacityBucket: 2))
        #expect(GraphEdgeStyle(weight: 5, recency: 1) == GraphEdgeStyle(widthBucket: 3, opacityBucket: 3))
        #expect(GraphEdgeStyle(widthBucket: 3, opacityBucket: 3).lineWidth > GraphEdgeStyle(widthBucket: 0, opacityBucket: 3).lineWidth)
        #expect(GraphEdgeStyle(widthBucket: 0, opacityBucket: 3).opacity > GraphEdgeStyle(widthBucket: 0, opacityBucket: 0).opacity)
    }

    // MARK: - Labels

    @Test func labelBudgetScalesWithZoom() {
        #expect(GraphLabels.budget(zoom: 0.2) == 6)
        #expect(GraphLabels.budget(zoom: 0.5) == 6)
        #expect(GraphLabels.budget(zoom: 1) == 12)
        #expect(GraphLabels.budget(zoom: 2) == 48)
        #expect(GraphLabels.budget(zoom: 4) == 60)
    }

    @Test func labelOpacityFadesOverTheLastThirtyPercent() {
        #expect(GraphLabels.opacity(rank: 0, budget: 12) == 1)
        #expect(GraphLabels.opacity(rank: 8, budget: 12) == 1)
        #expect(GraphLabels.opacity(rank: 9, budget: 12) < 1)
        #expect(abs(GraphLabels.opacity(rank: 11, budget: 12) - 0.25) < 1e-9)
        #expect(GraphLabels.opacity(rank: 12, budget: 12) == 0)
        #expect(abs(GraphLabels.opacity(rank: 5, budget: 6) - 0.25) < 1e-9)
    }

    // MARK: - Hit-testing

    @Test func segmentDistance() {
        let a = SIMD2<Double>(0, 0), b = SIMD2<Double>(10, 0)
        #expect(GraphHitTest.distance(from: SIMD2(5, 3), toSegment: a, b) == 3)
        #expect(GraphHitTest.distance(from: SIMD2(-3, 4), toSegment: a, b) == 5)
        #expect(GraphHitTest.distance(from: SIMD2(13, 4), toSegment: a, b) == 5)
        #expect(GraphHitTest.distance(from: SIMD2(3, 4), toSegment: a, a) == 5)
    }

    @Test func edgeHitUsesATenPointTolerance() {
        let segments = [(SIMD2<Double>(0, 0), SIMD2<Double>(100, 0))]
        #expect(GraphHitTest.edge(at: SIMD2(50, 10), segments: segments) == 0)
        #expect(GraphHitTest.edge(at: SIMD2(50, -11), segments: segments) == nil)
        #expect(GraphHitTest.edge(at: SIMD2(110, 0), segments: segments) == 0)
        #expect(GraphHitTest.edge(at: SIMD2(111, 0), segments: segments) == nil)
    }

    @Test func theNearestEdgeWins() {
        let segments = [
            (SIMD2<Double>(0, 0), SIMD2<Double>(100, 0)),
            (SIMD2<Double>(0, 8), SIMD2<Double>(100, 8)),
        ]
        #expect(GraphHitTest.edge(at: SIMD2(50, 3), segments: segments) == 0)
        #expect(GraphHitTest.edge(at: SIMD2(50, 5), segments: segments) == 1)
    }

    @Test func nodeHitPrefersTheTopmostAndHasAMinimumSize() {
        let circles: [(center: SIMD2<Double>, radius: Double)] = [(SIMD2(0, 0), 20), (SIMD2(5, 0), 4)]
        #expect(GraphHitTest.node(at: SIMD2(4, 0), count: 2) { circles[$0] } == 1)
        #expect(GraphHitTest.node(at: SIMD2(-15, 0), count: 2) { circles[$0] } == 0)
        // A 4pt node still takes a tap 12pt away.
        #expect(GraphHitTest.node(at: SIMD2(5, 11.5), count: 2) { circles[$0] } == 1)
        #expect(GraphHitTest.node(at: SIMD2(50, 50), count: 2) { circles[$0] } == nil)
    }

    // MARK: - Redraw

    @Test func redrawPausesOnlyTwoSecondsAfterEverythingStops() {
        #expect(!GraphRedraw.shouldPause(settled: false, gestureActive: false, flying: false, lastActive: 0, now: 10))
        #expect(!GraphRedraw.shouldPause(settled: true, gestureActive: true, flying: false, lastActive: 0, now: 10))
        #expect(!GraphRedraw.shouldPause(settled: true, gestureActive: false, flying: true, lastActive: 0, now: 10))
        #expect(!GraphRedraw.shouldPause(settled: true, gestureActive: false, flying: false, lastActive: 9, now: 10))
        #expect(GraphRedraw.shouldPause(settled: true, gestureActive: false, flying: false, lastActive: 8, now: 10))
    }

    // MARK: - Frame timing

    @Test func samplerKeepsIntervalsOnlyBetweenInteractingFrames() {
        let sampler = FrameTimeSampler()
        sampler.record(frameStart: 0, workSeconds: 0.002, interacting: true)
        sampler.record(frameStart: 0.016, workSeconds: 0.003, interacting: true)
        sampler.record(frameStart: 0.032, workSeconds: 0.001, interacting: false)
        sampler.record(frameStart: 0.048, workSeconds: 0.001, interacting: true)
        // A resume after a pause is not a slow frame.
        sampler.record(frameStart: 1.048, workSeconds: 0.001, interacting: true)
        sampler.record(frameStart: 1.068, workSeconds: 0.001, interacting: true)
        #expect(sampler.intervals.count == 2)
        #expect(abs(sampler.intervals[0] - 0.016) < 1e-9)
        #expect(abs(sampler.intervals[1] - 0.020) < 1e-9)
        #expect(sampler.workTimes.count == 5)
    }

    @Test func samplerCompletesAfterFiveSeconds() {
        let sampler = FrameTimeSampler()
        var time: TimeInterval = 0
        sampler.record(frameStart: time, workSeconds: 0, interacting: true)
        for _ in 0..<299 {
            time += 1.0 / 60
            sampler.record(frameStart: time, workSeconds: 0, interacting: true)
        }
        #expect(!sampler.isComplete)
        time += 0.1
        sampler.record(frameStart: time, workSeconds: 0, interacting: true)
        #expect(sampler.isComplete)
    }

    @Test func percentilesUseNearestRank() {
        let values = (1...100).map(Double.init).shuffled()
        #expect(FrameTimeSampler.percentile(values, 0.5) == 50)
        #expect(FrameTimeSampler.percentile(values, 0.95) == 95)
        #expect(FrameTimeSampler.percentile([7], 0.95) == 7)
        #expect(FrameTimeSampler.percentile([], 0.5) == nil)
    }

    // MARK: - Layout order

    @Test func layoutOrderPutsHubsFirstAndIsStable() {
        let nodes = [node(1), node(8), node(3), node(8)]
        let ordered = GraphSimulation.Node.layoutOrdered(nodes)
        #expect(ordered.map(\.linkCount) == [8, 8, 3, 1])
        #expect(ordered[0].id.uuidString < ordered[1].id.uuidString)
        #expect(GraphSimulation.Node.layoutOrdered(nodes.reversed()) == ordered)
    }

    // MARK: - Camera

    @Test func screenAndWorldRoundTrip() {
        let camera = GraphCamera()
        camera.pan = SIMD2(13, -7)
        camera.setZoom(2.5, keeping: SIMD2(40, 90), center: SIMD2(200, 400))
        let point = SIMD2<Double>(-31, 57)
        let center = SIMD2<Double>(200, 400)
        #expect(close(camera.world(camera.screen(point, center: center), center: center), point))
    }

    @Test func pinchKeepsThePointUnderTheFingers() {
        let camera = GraphCamera()
        let center = SIMD2<Double>(200, 400)
        let anchor = SIMD2<Double>(260, 350)
        let before = camera.world(anchor, center: center)
        camera.setZoom(3, keeping: anchor, center: center)
        #expect(camera.zoom == 3)
        #expect(close(camera.world(anchor, center: center), before))
        camera.setZoom(40, keeping: anchor, center: center)
        #expect(camera.zoom == GraphCamera.zoomRange.upperBound)
    }

    @Test func aFlightLandsExactlyAndCentresTheNode() {
        let camera = GraphCamera()
        let center = SIMD2<Double>(200, 400)
        let target = SIMD2<Double>(120, -80)
        camera.fly(to: target, now: 100)
        #expect(camera.isFlying)
        #expect(camera.advance(now: 100.1))
        #expect(camera.zoom > 1 && camera.zoom < GraphCamera.readableZoom)
        #expect(!camera.advance(now: 100 + GraphCamera.flightDuration + 0.001))
        #expect(!camera.isFlying)
        #expect(camera.zoom == GraphCamera.readableZoom)
        #expect(close(camera.screen(target, center: center), center))
    }

    @Test func aFlightKeepsACloserZoom() {
        let camera = GraphCamera()
        camera.setZoom(3, keeping: .zero, center: .zero)
        camera.fly(to: SIMD2(10, 10), now: 0)
        camera.advance(now: 1)
        #expect(camera.zoom == 3)
        #expect(close(camera.screen(SIMD2(10, 10), center: .zero), .zero))
    }

    @Test func cancellingAFlightLeavesTheCameraWhereItIs() {
        let camera = GraphCamera()
        camera.fly(to: SIMD2(300, 300), now: 0)
        camera.advance(now: 0.1)
        let pan = camera.pan
        camera.cancelFlight()
        #expect(!camera.advance(now: 5))
        #expect(camera.pan == pan)
    }

    // MARK: - Lenses and entry dots

    @Test func aPaintSetsFillsFadesAndRecomputesOnlyOnANewGeneration() {
        let (simulation, nodes) = hub()
        let cache = GraphDrawCache()
        let paint = GraphPaint(generation: 1, palette: [.red, .blue], slotByID: [nodes[0].id: 1, nodes[1].id: 7], neutralUnslotted: true, faded: [nodes[2].id])
        let plan = cache.plan(for: simulation, focusedID: nil, paint: paint)
        #expect(plan.fills[0] == .slot(1))
        #expect(plan.fills[1] == .neutral, "a slot outside the palette falls back")
        #expect(plan.fills[3] == .neutral)
        #expect(plan.fadedNodes == [2])

        let unpainted = GraphDrawCache().plan(for: simulation, focusedID: nil)
        #expect(unpainted.fills.allSatisfy { $0 == .kind(.person) })
        #expect(unpainted.fadedNodes.isEmpty)

        let before = cache.recomputeCount
        var same = paint
        same.faded = []
        _ = cache.plan(for: simulation, focusedID: nil, paint: same)
        #expect(cache.recomputeCount == before, "only the generation is compared")
        same.generation = 2
        _ = cache.plan(for: simulation, focusedID: nil, paint: same)
        #expect(cache.recomputeCount == before + 1)
    }

    @Test func recencyGlowIsCappedAndGivesWayToFocus() {
        let nodes = (0..<40).map { node(40 - $0) }
        let simulation = GraphSimulation(nodes: nodes, edges: [EntityGraph.Edge(nodes[0].id, nodes[1].id, weight: 1)])
        let paint = GraphPaint(generation: 1, glowing: Set(nodes.map(\.id)))
        let plan = GraphDrawCache().plan(for: simulation, focusedID: nil, paint: paint)
        #expect(plan.glowNodes == Array(0..<GraphDrawCache.glowCap))

        let focused = GraphDrawCache().plan(for: simulation, focusedID: nodes[1].id, paint: paint)
        #expect(focused.glowNodes == [1, 0])
    }

    @Test func entryDotsAreNeverLabelledOrGlowingAndTheirEdgesAreFaint() {
        let person = node(5)
        let entry = GraphSimulation.Node(id: UUID(), kind: .other, linkCount: 1, isEntry: true)
        let other = node(2)
        let simulation = GraphSimulation(nodes: [person, entry, other], edges: [
            EntityGraph.Edge(entry.id, person.id, weight: 1, recency: 1),
            EntityGraph.Edge(person.id, other.id, weight: 3, recency: 1),
        ])
        let entryEdge = simulation.allEdges().firstIndex { $0.a == entry.id || $0.b == entry.id }!
        let personEdge = 1 - entryEdge

        let plan = GraphDrawCache().plan(for: simulation, focusedID: person.id, paint: GraphPaint(generation: 1, glowing: [entry.id]))
        #expect(plan.rankedLabels == [0, 2])
        #expect(plan.glowNodes == [0, 2])
        #expect(plan.litNodes == [0, 1, 2], "focus lights the entity's entries")
        #expect(plan.fills[1] == .neutral)
        #expect(plan.edgeStyles[entryEdge] == GraphEdgeStyle(widthBucket: 0, opacityBucket: 0))
        #expect(plan.edgeStyles[personEdge] != GraphEdgeStyle(widthBucket: 0, opacityBucket: 0))
        #expect(simulation.radius(of: entry.id) == GraphSimulation.entryRadius)
    }

    @Test func anEntityBeatsAnOverlappingEntryDotAndDotsNeedACloserTap() {
        let circles: [(SIMD2<Double>, Double)] = [(SIMD2(0, 0), 5), (SIMD2(6, 0), 2.5)]
        let isEntry: (Int) -> Bool = { $0 == 1 }
        #expect(GraphHitTest.node(at: SIMD2(6, 0), count: 2, isEntry: isEntry) { circles[$0] } == 0,
                "the dot is drawn later but sits inside the person's 12pt target")
        let far: [(SIMD2<Double>, Double)] = [(SIMD2(0, 0), 5), (SIMD2(40, 0), 2.5)]
        #expect(GraphHitTest.node(at: SIMD2(47, 0), count: 2, isEntry: isEntry) { far[$0] } == 1)
        #expect(GraphHitTest.node(at: SIMD2(49, 0), count: 2, isEntry: isEntry) { far[$0] } == nil)
    }

    @Test func anEdgeToAnEntryFocusesItsEntityEnd() {
        let person = node(1)
        let entry = GraphSimulation.Node(id: UUID(), kind: .other, linkCount: 4, isEntry: true)
        #expect(GraphHitTest.focusEnd(entry, person) == person)
        #expect(GraphHitTest.focusEnd(person, entry) == person)
        let big = node(9)
        #expect(GraphHitTest.focusEnd(person, big) == big)
    }

    @Test func aFlightCanKeepTheZoomAndACentroidSkipsWhatIsOffTheMap() {
        let camera = GraphCamera()
        camera.setZoom(0.5, keeping: .zero, center: .zero)
        camera.fly(to: SIMD2(100, 0), now: 0, zoom: camera.zoom)
        camera.advance(now: 1)
        #expect(camera.zoom == 0.5)
        #expect(close(camera.screen(SIMD2(100, 0), center: .zero), .zero))

        let (simulation, nodes) = hub()
        let a = simulation.position(of: nodes[0].id)!, b = simulation.position(of: nodes[1].id)!
        #expect(GraphHitTest.centroid(of: [nodes[0].id, nodes[1].id, UUID()], in: simulation) == (a + b) / 2)
        #expect(GraphHitTest.centroid(of: [UUID()], in: simulation) == nil)
    }
}
