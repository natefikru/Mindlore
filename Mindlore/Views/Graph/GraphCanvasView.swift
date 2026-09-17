import QuartzCore
import SwiftUI

// Mind's force-graph drawing surface. Touches no model type: everything it draws comes from the simulation itself and a namer closure, the
// same "stay free of SwiftData" shape EntityChipIndex's consumers already follow.
//
// It keeps redrawing while the simulation moves, a finger is down, or the camera flies, and stops
// two seconds after all three end. Nothing is written to view state inside the draw closure: the
// camera, the draw cache, and the frame sampler are plain objects held in @State.
struct GraphCanvasView: View {
    let simulation: GraphSimulation
    // The simulation's topologyVersion as of the parent's last update. The parent stores it in its
    // own state, so an in-place update re-renders this view, which then wakes the redraw.
    var version: Int = 0
    let namer: (UUID) -> String?
    @Binding var focusedID: UUID?
    // A centred subject, drawn distinctly and exempt from drag/long-press. Nothing passes one
    // until A5b's area regions.
    var anchoredID: UUID?
    // A group to bring forward (an area tile's entities); the rest fade while nothing is focused.
    var highlightedIDs: Set<UUID>?
    // Whether a focus that leaves the simulation is cleared. Mind keeps it, since a search result
    // can be focused while it's filtered off the map.
    var clearsMissingFocus = true
    // What overlays cover, so a focused node lands in the middle of what's left.
    var visibleInsets = EdgeInsets()
    var onNavigate: (UUID) -> Void = { _ in }
    // Called once per appearance with what the device gate reads.
    var onRendered: (GraphRenderStats) -> Void = { _ in }

    private enum DragTarget: Equatable {
        case node(UUID)
        case canvas
    }

    private enum SymbolID: Hashable {
        case label(UUID)
    }

    @State private var camera = GraphCamera()
    @State private var cache = GraphDrawCache()
    @State private var sampler = FrameTimeSampler()
    @State private var activity = Activity()
    @State private var isIdle = false
    @State private var activityToken = 0
    @State private var dragTarget: DragTarget?
    // Where the finger was last frame (a pan applies deltas, so a simultaneous pinch's own pan
    // correction survives) and, for a node drag, the grab point's offset from the node centre.
    @State private var lastTranslation: SIMD2<Double> = .zero
    @State private var grabOffset: SIMD2<Double> = .zero
    @State private var zoomAtGestureStart: Double?
    // SwiftUI resets these when a gesture ends or is cancelled (onEnded never runs on a cancel),
    // so the cleanup keys off them rather than off onEnded.
    @GestureState private var dragLive = false
    @GestureState private var pinchLive = false

    private static let focusDim = 0.15
    private static let highlightDim = 0.3

    var body: some View {
        let plan = cache.plan(for: simulation, focusedID: focusedID, highlighted: highlightedIDs)
        let labelIDs = labelSymbolIDs(plan)

        GeometryReader { geometry in
            let center = SIMD2(Double(geometry.size.width) / 2, Double(geometry.size.height) / 2)

            TimelineView(.animation(paused: isIdle)) { _ in
                Canvas { context, _ in
                    let frameStart = CACurrentMediaTime()
                    simulation.tick()
                    camera.advance(now: frameStart)
                    draw(in: &context, center: center, plan: cache.plan(for: simulation, focusedID: focusedID, highlighted: highlightedIDs))
                    sampler.record(
                        frameStart: frameStart,
                        workSeconds: CACurrentMediaTime() - frameStart,
                        interacting: !activity.reported && (activity.gestureActive || camera.isFlying)
                    )
                } symbols: {
                    ForEach(labelIDs, id: \.self) { id in
                        if let name = namer(id) {
                            Text(name).font(.caption2).tag(SymbolID.label(id))
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(center: center))
            .simultaneousGesture(magnifyGesture(center: center))
            .simultaneousGesture(tapGesture(center: center))
            .simultaneousGesture(longPressGesture(center: center))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Graph")
        .accessibilityValue("nodes=\(simulation.nodeCount) highlighted=\(plan.hasFocus ? 0 : plan.highlightedNodes?.count ?? 0) focused=\(focusedID.flatMap(namer) ?? "none")")
        .sensoryFeedback(.selection, trigger: focusedID) { _, new in new != nil }
        .onChange(of: focusedID) {
            flyToFocus()
            wake()
        }
        .onChange(of: highlightedIDs) { wake() }
        .onChange(of: version) {
            if clearsMissingFocus, let focusedID, simulation.index(of: focusedID) == nil {
                self.focusedID = nil
            }
            wake()
        }
        .onChange(of: dragLive) { _, live in
            if !live { endDrag() }
        }
        .onChange(of: pinchLive) { _, live in
            if !live { endPinch() }
        }
        .onAppear {
            // Settle time only means something when the layout is still moving at appearance; a
            // return visit to an already settled graph reports none.
            activity = Activity(appearedAt: CACurrentMediaTime(), measuresSettle: !simulation.settled)
            sampler = FrameTimeSampler()
            // A canvas built with a focus already set (a jump into Mind) centres it too; without
            // one, the first appearance centres the layout in the uncovered part.
            if focusedID == nil, camera.pan == .zero {
                camera.pan = visibleCenterOffset
            }
            flyToFocus()
            wake()
        }
        .onDisappear {
            endDrag()
            endPinch()
            report()
        }
        .task(id: activityToken) { await watch() }
    }

    private func flyToFocus() {
        guard let focusedID, let position = simulation.position(of: focusedID) else { return }
        camera.fly(to: position, now: CACurrentMediaTime(), offset: visibleCenterOffset)
    }

    private var visibleCenterOffset: SIMD2<Double> {
        SIMD2(
            Double(visibleInsets.leading - visibleInsets.trailing) / 2,
            Double(visibleInsets.top - visibleInsets.bottom) / 2
        )
    }

    // MARK: - Drawing

    private func labelSymbolIDs(_ plan: GraphDrawPlan) -> [UUID] {
        let nodes = simulation.nodes
        var ids = plan.rankedLabels.map { nodes[$0].id }
        if let anchoredID, simulation.index(of: anchoredID) != nil, !ids.contains(anchoredID) {
            ids.append(anchoredID)
        }
        return ids
    }

    private func draw(in context: inout GraphicsContext, center: SIMD2<Double>, plan: GraphDrawPlan) {
        let nodes = simulation.nodes
        let zoom = camera.zoom
        let dimmed = plan.hasFocus
        let screen = (0..<nodes.count).map { camera.screen(simulation.position(at: $0), center: center) }
        func point(_ index: Int) -> CGPoint { CGPoint(x: screen[index].x, y: screen[index].y) }
        func circle(_ index: Int, scale: Double = 1) -> CGRect {
            let r = simulation.radius(at: index) * zoom * scale
            return CGRect(x: screen[index].x - r, y: screen[index].y - r, width: r * 2, height: r * 2)
        }

        // Edges: one path per style bucket, lit edges in their own paths per width.
        let buckets = GraphEdgeStyle.bucketCount
        // A second set of slots holds edges that leave a highlighted group, drawn fainter.
        var edgePaths = Array(repeating: Path(), count: 2 * buckets * buckets)
        var litPaths = Array(repeating: Path(), count: buckets)
        for (position, pair) in simulation.edgeIndices.enumerated() {
            let style = plan.edgeStyles[position]
            if plan.litEdges.contains(position) {
                litPaths[style.widthBucket].move(to: point(pair.a))
                litPaths[style.widthBucket].addLine(to: point(pair.b))
            } else {
                let outside = !dimmed && !(plan.isHighlighted(pair.a) && plan.isHighlighted(pair.b))
                let slot = (outside ? buckets * buckets : 0) + style.widthBucket * buckets + style.opacityBucket
                edgePaths[slot].move(to: point(pair.a))
                edgePaths[slot].addLine(to: point(pair.b))
            }
        }
        let edgeFade = dimmed ? Self.focusDim : 1
        for (slot, path) in edgePaths.enumerated() where !path.isEmpty {
            let local = slot % (buckets * buckets)
            let fade = slot >= buckets * buckets ? Self.focusDim : edgeFade
            let style = GraphEdgeStyle(widthBucket: local / buckets, opacityBucket: local % buckets)
            context.stroke(path, with: .color(.secondary.opacity(style.opacity * fade)), lineWidth: style.lineWidth)
        }
        for (width, path) in litPaths.enumerated() where !path.isEmpty {
            let style = GraphEdgeStyle(widthBucket: width, opacityBucket: 0)
            context.stroke(path, with: .color(.primary.opacity(0.9)), lineWidth: style.lineWidth + 1)
        }

        // Glow behind the lit nodes: a gradient fill, no blur filter.
        for index in plan.glowNodes {
            let color = nodes[index].kind.color
            let rect = circle(index, scale: 2.2)
            context.fill(
                Path(ellipseIn: rect),
                with: .radialGradient(
                    Gradient(colors: [color.opacity(0.55), color.opacity(0)]),
                    center: point(index),
                    startRadius: simulation.radius(at: index) * zoom * 0.8,
                    endRadius: rect.width / 2
                )
            )
        }

        // Nodes: one fill per kind, faded ones first so lit nodes sit on top.
        var bright: [EntityKind: Path] = [:]
        var faded: [EntityKind: Path] = [:]
        var muted: [EntityKind: Path] = [:]
        for index in nodes.indices {
            if dimmed && !plan.litNodes.contains(index) {
                faded[nodes[index].kind, default: Path()].addEllipse(in: circle(index))
            } else if !dimmed && !plan.isHighlighted(index) {
                muted[nodes[index].kind, default: Path()].addEllipse(in: circle(index))
            } else {
                bright[nodes[index].kind, default: Path()].addEllipse(in: circle(index))
            }
        }
        for kind in EntityKind.allCases {
            if let path = faded[kind] { context.fill(path, with: .color(kind.color.opacity(Self.focusDim))) }
            if let path = muted[kind] { context.fill(path, with: .color(kind.color.opacity(Self.highlightDim))) }
        }
        for kind in EntityKind.allCases {
            if let path = bright[kind] { context.fill(path, with: .color(kind.color)) }
        }
        if let anchoredID, let index = simulation.index(of: anchoredID) {
            context.stroke(Path(ellipseIn: circle(index)), with: .color(.primary), lineWidth: 3)
        }
        if let focusedIndex = plan.focusedIndex, nodes[focusedIndex].id != anchoredID {
            context.stroke(Path(ellipseIn: circle(focusedIndex)), with: .color(.primary), lineWidth: 2.5)
        }

        // Labels: a zoom-sized prefix of the ranked list, fading by rank, dimmed outside the focus.
        let budget = GraphLabels.budget(zoom: zoom)
        var labelled = plan.rankedLabels.prefix(budget).enumerated().map { (index: $0.element, rank: $0.offset) }
        if let anchoredID, let index = simulation.index(of: anchoredID), !labelled.contains(where: { $0.index == index }) {
            labelled.append((index, 0))
        }
        for (index, rank) in labelled {
            guard let resolved = context.resolveSymbol(id: SymbolID.label(nodes[index].id)) else { continue }
            var opacity = GraphLabels.opacity(rank: rank, budget: budget)
            if dimmed && !plan.litNodes.contains(index) { opacity *= Self.focusDim }
            if !dimmed && !plan.isHighlighted(index) { opacity *= Self.highlightDim }
            var labelContext = context
            labelContext.opacity = opacity
            let r = simulation.radius(at: index) * zoom
            labelContext.draw(resolved, at: CGPoint(x: screen[index].x, y: screen[index].y - r - 10))
        }
    }

    // MARK: - Activity

    // Plain object, so gestures and the watcher can update it without re-rendering anything.
    private final class Activity {
        var dragging = false
        var pinching = false
        var lastActive: TimeInterval
        let appearedAt: TimeInterval
        // Off for an appearance that starts settled. A drag before the first settle holds the
        // layout warm, so the settle time then includes that drag.
        let measuresSettle: Bool
        var settleSeconds: Double?
        var reported = false

        init(appearedAt: TimeInterval = CACurrentMediaTime(), measuresSettle: Bool = true) {
            self.appearedAt = appearedAt
            self.measuresSettle = measuresSettle
            lastActive = appearedAt
        }

        var gestureActive: Bool { dragging || pinching }
    }

    // Every change that can move something comes through here.
    private func wake() {
        activity.lastActive = CACurrentMediaTime()
        isIdle = false
        activityToken &+= 1
    }

    // Polls while the canvas is drawing: notes the first settle, reports once 5 s of interaction
    // frames exist, and pauses the timeline once nothing has moved for two seconds.
    private func watch() async {
        while !Task.isCancelled {
            let now = CACurrentMediaTime()
            let settled = simulation.settled
            let active = GraphRedraw.isActive(settled: settled, gestureActive: activity.gestureActive, flying: camera.isFlying)
            if active { activity.lastActive = now }
            if settled, activity.measuresSettle, activity.settleSeconds == nil {
                activity.settleSeconds = now - activity.appearedAt
            }
            if sampler.isComplete { report() }
            if GraphRedraw.shouldPause(settled: settled, gestureActive: activity.gestureActive, flying: camera.isFlying, lastActive: activity.lastActive, now: now) {
                isIdle = true
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private func report() {
        guard !activity.reported else { return }
        activity.reported = true
        onRendered(GraphRenderStats(
            nodes: simulation.nodeCount,
            edges: simulation.edgeIndices.count,
            settleMilliseconds: activity.settleSeconds.map { $0 * 1000 },
            frameSamples: sampler.intervals.count,
            frameP50Milliseconds: FrameTimeSampler.percentile(sampler.intervals, 0.5).map { $0 * 1000 },
            frameP95Milliseconds: FrameTimeSampler.percentile(sampler.intervals, 0.95).map { $0 * 1000 },
            workP95Milliseconds: FrameTimeSampler.percentile(sampler.workTimes, 0.95).map { $0 * 1000 }
        ))
    }

    // MARK: - Hit-testing

    private func nodeHit(_ point: SIMD2<Double>, center: SIMD2<Double>) -> UUID? {
        let index = GraphHitTest.node(at: point, count: simulation.nodeCount) { index in
            (camera.screen(simulation.position(at: index), center: center), simulation.radius(at: index) * camera.zoom)
        }
        return index.map { simulation.nodes[$0].id }
    }

    // A tapped edge focuses its better-connected end.
    private func edgeHit(_ point: SIMD2<Double>, center: SIMD2<Double>) -> UUID? {
        let pairs = simulation.edgeIndices
        let segments = pairs.map { pair in
            (camera.screen(simulation.position(at: pair.a), center: center), camera.screen(simulation.position(at: pair.b), center: center))
        }
        guard let position = GraphHitTest.edge(at: point, segments: segments) else { return nil }
        let nodes = simulation.nodes
        let a = nodes[pairs[position].a], b = nodes[pairs[position].b]
        return a.linkCount >= b.linkCount ? a.id : b.id
    }

    private static func vector(_ point: CGPoint) -> SIMD2<Double> {
        SIMD2(Double(point.x), Double(point.y))
    }

    // MARK: - Gestures

    // A hit at the drag's start pins that node for the rest of the drag, sticky after release,
    // and holds the simulation warm so its neighbours follow; a miss pans the canvas instead. A
    // hit on the anchored subject is treated as a miss too, since dragging it would move the one
    // point the view promises stays still, and so is a drag that starts during a pinch. The
    // 8pt threshold keeps a slightly shaky tap from pinning the node it focuses.
    private func dragGesture(center: SIMD2<Double>) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .updating($dragLive) { _, live, _ in live = true }
            .onChanged { value in
                let translation = SIMD2(Double(value.translation.width), Double(value.translation.height))
                if dragTarget == nil {
                    camera.cancelFlight()
                    let start = Self.vector(value.startLocation)
                    if !activity.pinching, let hit = nodeHit(start, center: center), hit != anchoredID,
                       let position = simulation.position(of: hit) {
                        dragTarget = .node(hit)
                        grabOffset = position - camera.world(start, center: center)
                        simulation.alphaTarget = GraphSimulation.dragAlphaTarget
                    } else {
                        dragTarget = .canvas
                    }
                    lastTranslation = .zero
                    activity.dragging = true
                    wake()
                }
                switch dragTarget {
                case .node(let id):
                    simulation.pin(id, at: camera.world(Self.vector(value.location), center: center) + grabOffset)
                case .canvas, nil:
                    camera.pan += translation - lastTranslation
                }
                lastTranslation = translation
            }
    }

    // Runs when the drag ends or is cancelled, and on disappear.
    private func endDrag() {
        guard dragTarget != nil || activity.dragging else { return }
        if case .node = dragTarget {
            simulation.alphaTarget = 0
        }
        dragTarget = nil
        activity.dragging = false
        wake()
    }

    // Zooms around where the pinch started, so the node under the fingers stays under them.
    private func magnifyGesture(center: SIMD2<Double>) -> some Gesture {
        MagnifyGesture()
            .updating($pinchLive) { _, live, _ in live = true }
            .onChanged { value in
                if zoomAtGestureStart == nil {
                    zoomAtGestureStart = camera.zoom
                    camera.cancelFlight()
                    activity.pinching = true
                    wake()
                }
                camera.setZoom((zoomAtGestureStart ?? 1) * Double(value.magnification), keeping: Self.vector(value.startLocation), center: center)
            }
    }

    private func endPinch() {
        guard zoomAtGestureStart != nil || activity.pinching else { return }
        zoomAtGestureStart = nil
        activity.pinching = false
        wake()
    }

    // A tap on a node focuses it; a second tap on the focused node navigates. A tap on an edge
    // focuses its better-connected end. A tap on empty canvas clears the focus.
    private func tapGesture(center: SIMD2<Double>) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                let point = Self.vector(value.location)
                if let id = nodeHit(point, center: center) {
                    if focusedID == id {
                        onNavigate(id)
                    } else {
                        focusedID = id
                    }
                } else {
                    focusedID = edgeHit(point, center: center)
                }
            }
    }

    // Unpinning a pinned (not anchored) node: a long-press, not a second tap, since a real
    // double-tap recognizer has no defined priority against the focus/navigate tap state above.
    private func longPressGesture(center: SIMD2<Double>) -> some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            .onEnded { value in
                guard case .second(true, let drag?) = value,
                      let id = nodeHit(Self.vector(drag.location), center: center),
                      id != anchoredID
                else { return }
                simulation.unpin(id)
                simulation.reheat(to: 0.1)
                wake()
            }
    }
}
