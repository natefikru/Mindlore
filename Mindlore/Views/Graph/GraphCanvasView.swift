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
    // Each node's life area in the window; colour always means area. `areaGeneration` is bumped
    // with every new map so the draw cache never compares the dictionary.
    var areaOf: [UUID: LifeArea] = [:]
    var areaGeneration = 0
    // Nodes that have just joined the map, against the moment they joined: they scale and fade up
    // out of the spot the simulation put them in. The caller decides what counts as joining; see
    // `MindView.show`.
    var arrivedAt: [UUID: Date] = [:]
    // Bumped by the caller when the whole picture changed (Mind's window): with nothing focused,
    // the camera comes back to the layout's middle in what the overlays leave uncovered.
    var recentreToken = 0
    // A replay is moving the map: keep drawing between its steps.
    var animating = false
    // Whether a focus that leaves the simulation is cleared. Mind keeps it, since a search result
    // can be focused while it's filtered off the map.
    var clearsMissingFocus = true
    // What overlays cover, so a focused node lands in the middle of what's left.
    var visibleInsets = EdgeInsets()
    var onNavigate: (UUID) -> Void = { _ in }
    // Called once per appearance with what the device gate reads.
    var onRendered: (GraphRenderStats) -> Void = { _ in }
    // Set here rather than by the caller: applied from outside, it lands on the hidden canvas as
    // well as the element and a query finds two.
    var accessibilityIdentifier = "graphCanvas"

    private enum DragTarget: Equatable {
        case node(UUID)
        case canvas
    }

    private enum SymbolID: Hashable {
        case label(UUID)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var camera = GraphCamera()
    @State private var cache = GraphDrawCache()
    @State private var sampler = FrameTimeSampler()
    @State private var activity = Activity()
    @State private var isIdle = false
    @State private var size: CGSize = .zero
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
    private static let neutralOpacity = 0.6
    // A tag's name is lighter than a person's or a place's, the way its node is only a ring.
    private static let ringLabelOpacity = 0.6
    private static let ringWidth = 1.5

    private var currentPlan: GraphDrawPlan {
        cache.plan(for: simulation, focusedID: focusedID, areaOf: areaOf, areaGeneration: areaGeneration)
    }

    var body: some View {
        let plan = currentPlan
        let labelIDs = labelSymbolIDs(plan)

        GeometryReader { geometry in
            let center = SIMD2(Double(geometry.size.width) / 2, Double(geometry.size.height) / 2)

            // The canvas stops ticking once the simulation settles, so a map that has stopped
            // moving costs nothing.
            TimelineView(.animation(paused: isIdle)) { _ in
                Canvas { context, _ in
                    let frameStart = CACurrentMediaTime()
                    simulation.tick()
                    camera.advance(now: frameStart)
                    draw(in: &context, center: center, plan: currentPlan)
                    sampler.record(
                        frameStart: frameStart,
                        workSeconds: CACurrentMediaTime() - frameStart,
                        interacting: !activity.reported && (activity.gestureActive || camera.isFlying)
                    )
                } symbols: {
                    // Capped: at accessibility sizes a caption grew to headline size and every
                    // name sat on top of the nodes around it. Zoom is how a map gets bigger text;
                    // search and the card read every name at full size.
                    ForEach(labelIDs, id: \.self) { id in
                        if let name = namer(id) {
                            Text(name).font(.caption2).tag(SymbolID.label(id))
                        }
                    }
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(center: center))
            .simultaneousGesture(magnifyGesture(center: center))
            .simultaneousGesture(tapGesture(center: center))
            .simultaneousGesture(longPressGesture(center: center))
        }
        .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
        .accessibilityHidden(true)
        // The accessibility element covers only the part of the map left visible. The canvas runs
        // under the bars and the panel; with the element that size too, VoiceOver outlined the tab
        // bar as part of the map, and a UI test's pinch, which starts near the element's corners,
        // put a finger on a tab. Hit testing is off, so every touch still reaches the canvas.
        .overlay(alignment: .topLeading) {
            Color.clear
                .frame(
                    width: max(0, size.width - visibleInsets.leading - visibleInsets.trailing),
                    height: max(0, size.height - visibleInsets.top - visibleInsets.bottom)
                )
                .accessibilityElement()
                .accessibilityLabel("Graph")
                .accessibilityValue(accessibilityValue(plan))
                .accessibilityIdentifier(accessibilityIdentifier)
                .offset(x: visibleInsets.leading, y: visibleInsets.top)
                .allowsHitTesting(false)
        }
        .sensoryFeedback(.selection, trigger: focusedID) { _, new in new != nil }
        .onChange(of: focusedID) {
            flyToFocus()
            wake()
        }
        .onChange(of: areaGeneration) { wake() }
        .onChange(of: animating) { _, on in
            activity.animating = on
            wake()
        }
        .onChange(of: recentreToken) {
            // Gravity pulls the layout toward the origin, so the origin is its middle.
            guard focusedID == nil else { return }
            camera.fly(to: .zero, now: CACurrentMediaTime(), offset: visibleCenterOffset, zoom: camera.zoom)
            wake()
        }
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
            activity.animating = animating
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

    // Tests match its start (`nodes=`) and its end (`focused=`), so new fields go in the middle.
    private func accessibilityValue(_ plan: GraphDrawPlan) -> String {
        "nodes=\(simulation.nodeCount) rings=\(plan.ringNodes.count) focused=\(focusedID.flatMap(namer) ?? "none")"
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
        return plan.rankedLabels.map { nodes[$0].id }
    }

    private func color(_ fill: GraphFill) -> Color {
        switch fill {
        case .area(let area): area.color
        case .neutral: .gray
        }
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
        var edgePaths = Array(repeating: Path(), count: buckets * buckets)
        var litPaths = Array(repeating: Path(), count: buckets)
        for (position, pair) in simulation.edgeIndices.enumerated() {
            let style = plan.edgeStyles[position]
            if plan.litEdges.contains(position) {
                litPaths[style.widthBucket].move(to: point(pair.a))
                litPaths[style.widthBucket].addLine(to: point(pair.b))
            } else {
                let slot = style.widthBucket * buckets + style.opacityBucket
                edgePaths[slot].move(to: point(pair.a))
                edgePaths[slot].addLine(to: point(pair.b))
            }
        }
        let edgeFade = dimmed ? Self.focusDim : 1
        for (slot, path) in edgePaths.enumerated() where !path.isEmpty {
            let style = GraphEdgeStyle(widthBucket: slot / buckets, opacityBucket: slot % buckets)
            context.stroke(path, with: .color(.secondary.opacity(style.opacity * edgeFade)), lineWidth: style.lineWidth)
        }
        for (width, path) in litPaths.enumerated() where !path.isEmpty {
            let style = GraphEdgeStyle(widthBucket: width, opacityBucket: 0)
            context.stroke(path, with: .color(.primary.opacity(0.9)), lineWidth: style.lineWidth + 1)
        }

        // Glow behind the lit nodes: a gradient fill, no blur filter.
        for index in plan.glowNodes {
            let color = color(plan.fills[index])
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

        // Nodes: one path per colour, strength, and shape, dimmest first so lit nodes sit on top.
        // A tag is a ring, stroked; everything else is filled.
        struct Bucket: Hashable {
            let fill: GraphFill
            let opacity: Double
            let ring: Bool
        }
        // Nodes that arrived in the last 0.6 s, as indices. Usually one; an entry that named five
        // new people is five. Resolved here rather than per node, since the lookup is by id.
        var blooming: [Int: Double] = [:]
        if !arrivedAt.isEmpty {
            let now = Date.now
            for (id, at) in arrivedAt {
                let elapsed = now.timeIntervalSince(at)
                guard BloomCurve.isRunning(at: elapsed), let index = simulation.index(of: id) else { continue }
                blooming[index] = elapsed
            }
        }
        var nodePaths: [Bucket: Path] = [:]
        for index in nodes.indices {
            var opacity = 1.0
            if dimmed && !plan.litNodes.contains(index) {
                opacity = Self.focusDim
            }
            var scale = 1.0
            if let elapsed = blooming[index] {
                scale = BloomCurve.scale(at: elapsed, reduceMotion: reduceMotion)
                opacity *= BloomCurve.opacity(at: elapsed)
            }
            let ring = plan.ringNodes.contains(index)
            // A ring's stroke sits inside the node's radius, so a tag and a name of one size match.
            let rect = circle(index, scale: scale)
            nodePaths[Bucket(fill: plan.fills[index], opacity: opacity, ring: ring), default: Path()]
                .addEllipse(in: ring ? rect.insetBy(dx: Self.ringWidth / 2, dy: Self.ringWidth / 2) : rect)
        }
        for (bucket, path) in nodePaths.sorted(by: { $0.key.opacity < $1.key.opacity }) {
            let shading = GraphicsContext.Shading.color(color(bucket.fill).opacity(bucket.opacity * (bucket.fill == .neutral ? Self.neutralOpacity : 1)))
            if bucket.ring {
                context.stroke(path, with: shading, lineWidth: Self.ringWidth)
            } else {
                context.fill(path, with: shading)
            }
        }
        if let focusedIndex = plan.focusedIndex {
            context.stroke(Path(ellipseIn: circle(focusedIndex)), with: .color(.primary), lineWidth: 2.5)
        }

        // Labels: a zoom-sized prefix of the ranked list, fading by rank, dimmed outside the focus.
        // A label that would land on a higher-ranked one is skipped rather than drawn over it.
        let budget = GraphLabels.budget(zoom: zoom)
        var placed: [(index: Int, rank: Int, symbol: GraphicsContext.ResolvedSymbol, at: CGPoint)] = []
        var frames: [CGRect] = []
        for (rank, index) in plan.rankedLabels.prefix(budget).enumerated() {
            guard let resolved = context.resolveSymbol(id: SymbolID.label(nodes[index].id)) else { continue }
            let r = simulation.radius(at: index) * zoom
            let at = CGPoint(x: screen[index].x, y: screen[index].y - r - 10)
            let size = resolved.size
            frames.append(CGRect(x: at.x - size.width / 2, y: at.y - size.height / 2, width: size.width, height: size.height))
            placed.append((index, rank, resolved, at))
        }
        for (label, visible) in zip(placed, GraphLabels.unobstructed(frames)) where visible {
            var opacity = GraphLabels.opacity(rank: label.rank, budget: budget)
            if dimmed && !plan.litNodes.contains(label.index) { opacity *= Self.focusDim }
            if plan.ringNodes.contains(label.index) { opacity *= Self.ringLabelOpacity }
            var labelContext = context
            labelContext.opacity = opacity
            labelContext.draw(label.symbol, at: label.at)
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

        // Set while a replay runs.
        var animating = false

        // Anything that keeps the canvas drawing besides the layout's own motion.
        var gestureActive: Bool { dragging || pinching || animating }
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

    private func nodeHit(_ point: SIMD2<Double>, center: SIMD2<Double>) -> GraphSimulation.Node? {
        let nodes = simulation.nodes
        let index = GraphHitTest.node(at: point, count: nodes.count) { index in
            (camera.screen(simulation.position(at: index), center: center), simulation.radius(at: index) * camera.zoom)
        }
        return index.map { nodes[$0] }
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
        return GraphHitTest.focusEnd(a, b).id
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
                    if !activity.pinching, let hit = nodeHit(start, center: center),
                       let position = simulation.position(of: hit.id) {
                        dragTarget = .node(hit.id)
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
                if let hit = nodeHit(point, center: center) {
                    let id = hit.id
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
                      let hit = nodeHit(Self.vector(drag.location), center: center)
                else { return }
                let id = hit.id
                simulation.unpin(id)
                simulation.reheat(to: 0.1)
                wake()
            }
    }
}
