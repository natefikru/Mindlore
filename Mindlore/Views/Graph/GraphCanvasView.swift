import QuartzCore
import SwiftUI

struct GraphRegion: Identifiable, Equatable {
    let id: String
    let name: String
    let point: SIMD2<Double>
    let color: Color
}

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
    // A group to bring forward (an area tile's entities); the rest fade while nothing is focused.
    var highlightedIDs: Set<UUID>?
    // Names the highlighted group; the camera flies to the group only when this changes, not
    // when the group's members do (a replay step, a filter change).
    var highlightGroup: String?
    // A lens's colours (nil: kind colours), and its name for the accessibility value.
    var paint: GraphPaint?
    // Life-area names drawn faintly at their spots while the map groups by area.
    var regions: [GraphRegion] = []
    // Entities a recent entry named. They breathe: a ring outside the node, rising and falling on
    // one shared sine. Empty turns the halo off, which is what the recency lens does, since that
    // lens is already saying this and saying it better.
    var haloedIDs: Set<UUID> = []
    // Nodes that have just joined the map, against the moment they joined: they scale and fade up
    // out of the spot the simulation put them in. The caller decides what counts as joining; see
    // `MindView.show`.
    var arrivedAt: [UUID: Date] = [:]
    var lens: MindLens = .kind
    // A replay is moving the map: keep drawing, and measure it.
    var animating = false
    // Whether a focus that leaves the simulation is cleared. Mind keeps it, since a search result
    // can be focused while it's filtered off the map.
    var clearsMissingFocus = true
    // What overlays cover, so a focused node lands in the middle of what's left.
    var visibleInsets = EdgeInsets()
    var onNavigate: (UUID) -> Void = { _ in }
    // A tapped entry dot. Dots never take focus.
    var onOpenEntry: (UUID) -> Void = { _ in }
    // Called once per appearance with what the device gate reads.
    var onRendered: (GraphRenderStats) -> Void = { _ in }

    private enum DragTarget: Equatable {
        case node(UUID)
        case canvas
    }

    private enum SymbolID: Hashable {
        case label(UUID)
        case region(String)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var camera = GraphCamera()
    @State private var cache = GraphDrawCache()
    @State private var sampler = FrameTimeSampler()
    @State private var activity = Activity()
    @State private var isIdle = false
    @State private var size: CGSize = .zero
    // UI tests only: where the first entry dot sits once the layout settles, so a test can tap it
    // through the real hit rule.
    @State private var entryDot: String?
    private static let reportsEntryDot = ProcessInfo.processInfo.arguments.contains(StoreLocation.uiTestingArgument)
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
    private static let neutralOpacity = 0.6
    private static let regionOpacity = 0.8

    var body: some View {
        let plan = cache.plan(for: simulation, focusedID: focusedID, highlighted: highlightedIDs, paint: paint, haloed: haloedIDs)
        let labelIDs = labelSymbolIDs(plan)
        // The canvas stops ticking once the simulation settles, which is why a map that has stopped
        // moving costs nothing. A halo has to keep breathing through exactly that, so an idle map
        // with rings on it slows down instead of stopping: a 2.4 s breath at 12 fps is smooth, and
        // the frame's work is one sine plus a stroke per colour bucket. `graph.rendered` carries the
        // measurement. Nothing to breathe, or Reduce Motion, and it pauses as before.
        let breathing = !plan.haloNodes.isEmpty && !reduceMotion
        let idleInterval: Double? = isIdle && breathing ? 1.0 / 12.0 : nil

        GeometryReader { geometry in
            let center = SIMD2(Double(geometry.size.width) / 2, Double(geometry.size.height) / 2)

            TimelineView(.animation(minimumInterval: idleInterval, paused: isIdle && !breathing)) { _ in
                Canvas { context, _ in
                    let frameStart = CACurrentMediaTime()
                    simulation.tick()
                    camera.advance(now: frameStart)
                    draw(in: &context, center: center, plan: cache.plan(for: simulation, focusedID: focusedID, highlighted: highlightedIDs, paint: paint, haloed: haloedIDs))
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
                    ForEach(regions) { region in
                        Text(region.name)
                            .font(.headline)
                            .foregroundStyle(region.color)
                            .tag(SymbolID.region(region.id))
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(center: center))
            .simultaneousGesture(magnifyGesture(center: center))
            .simultaneousGesture(tapGesture(center: center))
            .simultaneousGesture(longPressGesture(center: center))
        }
        .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Graph")
        .accessibilityValue(accessibilityValue(plan))
        .sensoryFeedback(.selection, trigger: focusedID) { _, new in new != nil }
        .onChange(of: focusedID) {
            flyToFocus()
            wake()
        }
        .onChange(of: highlightedIDs) { wake() }
        .onChange(of: highlightGroup) { flyToHighlight() }
        .onChange(of: regions.map(\.id)) { _, ids in
            if !ids.isEmpty, focusedID == nil { fitRegions() }
            wake()
        }
        .onChange(of: version) {
            if clearsMissingFocus, let focusedID, simulation.index(of: focusedID) == nil {
                self.focusedID = nil
            }
            wake()
        }
        .onChange(of: animating) { _, on in
            if on {
                // A fresh sample, so a replay is measured even after earlier touches reported.
                activity = Activity(appearedAt: CACurrentMediaTime(), measuresSettle: false)
                activity.measuresReplay = true
                sampler = FrameTimeSampler()
            }
            activity.animating = on
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
            activity.measuresReplay = animating
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

    // Entities and entry dots are counted apart, so `nodes=` means the same with dots on or off.
    // Tests match its start and its end (`focused=`), so new fields go in the middle.
    private func accessibilityValue(_ plan: GraphDrawPlan) -> String {
        let entries = simulation.nodes.lazy.filter(\.isEntry).count
        let highlighted = plan.hasFocus ? 0 : plan.highlightedNodes?.count ?? 0
        return "nodes=\(simulation.nodeCount - entries) highlighted=\(highlighted) entries=\(entries) lens=\(lens.rawValue) replay=\(animating ? "on" : "off")\(entryDot.map { " entryDot=\($0)" } ?? "") focused=\(focusedID.flatMap(namer) ?? "none")"
    }

    private func flyToFocus() {
        guard let focusedID, let position = simulation.position(of: focusedID) else { return }
        camera.fly(to: position, now: CACurrentMediaTime(), offset: visibleCenterOffset)
    }

    // A tile tap brings its group into view at the current zoom. Focus says more, so it wins.
    private func flyToHighlight() {
        guard focusedID == nil, let highlightedIDs,
              let point = GraphHitTest.centroid(of: highlightedIDs, in: simulation)
        else { return }
        camera.fly(to: point, now: CACurrentMediaTime(), offset: visibleCenterOffset, zoom: camera.zoom)
    }

    // Grouping spreads the map over a circle of area spots; zoom out so all of them show.
    private func fitRegions() {
        let extent = regions.map { ($0.point * $0.point).sum().squareRoot() }.max() ?? 0
        let width = Double(size.width - visibleInsets.leading - visibleInsets.trailing)
        let height = Double(size.height - visibleInsets.top - visibleInsets.bottom)
        guard extent > 0, width > 0, height > 0 else { return }
        let zoom = min(1, min(width, height) / (2 * (extent + GraphCanvasView.regionMargin)))
        camera.fly(to: .zero, now: CACurrentMediaTime(), offset: visibleCenterOffset, zoom: zoom)
    }

    private static let regionLabelOffset: Double = 90
    private static let regionMargin: Double = 120

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
        case .kind(let kind): kind.color
        case .slot(let slot): paint.flatMap { $0.palette.indices.contains(slot) ? $0.palette[slot] : nil } ?? .gray
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

        // The Breathe halo, under everything else so the node itself stays crisp on top. One sine
        // for the whole frame, one path per colour bucket: a week that touched forty names costs a
        // handful of strokes, not forty gradients. Under Reduce Motion the phase is fixed and the
        // ring simply sits there, which is what `Motion.resolve` means by returning nil for a
        // repeating animation.
        if !plan.haloNodes.isEmpty {
            let phase = reduceMotion ? 0 : sin(CACurrentMediaTime() * 2 * .pi / Motion.breatheSeconds)
            var rings: [GraphFill: Path] = [:]
            for index in plan.haloNodes {
                // A node the focus or a lens has already pushed back does not breathe over the top
                // of being pushed back.
                if plan.fadedNodes.contains(index) { continue }
                if dimmed && !plan.litNodes.contains(index) { continue }
                rings[plan.fills[index], default: Path()].addEllipse(in: circle(index, scale: 1.5 + 0.18 * phase))
            }
            for (fill, path) in rings {
                context.stroke(path, with: .color(color(fill).opacity(0.30 + 0.10 * phase)), lineWidth: 1.5)
            }
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

        // Nodes: one path per colour and strength, dimmest first so lit nodes sit on top.
        struct Bucket: Hashable {
            let fill: GraphFill
            let opacity: Double
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
            } else if !dimmed && !plan.isHighlighted(index) {
                opacity = Self.highlightDim
            }
            if plan.fadedNodes.contains(index) { opacity *= GraphPaint.fadedOpacity }
            var scale = 1.0
            if let elapsed = blooming[index] {
                scale = BloomCurve.scale(at: elapsed, reduceMotion: reduceMotion)
                opacity *= BloomCurve.opacity(at: elapsed)
            }
            nodePaths[Bucket(fill: plan.fills[index], opacity: opacity), default: Path()].addEllipse(in: circle(index, scale: scale))
        }
        for (bucket, path) in nodePaths.sorted(by: { $0.key.opacity < $1.key.opacity }) {
            let base = color(bucket.fill)
            context.fill(path, with: .color(base.opacity(bucket.opacity * (bucket.fill == .neutral ? Self.neutralOpacity : 1))))
        }
        if let focusedIndex = plan.focusedIndex {
            context.stroke(Path(ellipseIn: circle(focusedIndex)), with: .color(.primary), lineWidth: 2.5)
        }

        // Area names sit over the nodes, since they're the map's legend while it groups by area.
        for region in regions {
            guard let resolved = context.resolveSymbol(id: SymbolID.region(region.id)) else { continue }
            // Just outside the cluster, away from the middle.
            let length = (region.point * region.point).sum().squareRoot()
            let outward = length > 0 ? region.point / length * Self.regionLabelOffset : SIMD2(0, -Self.regionLabelOffset)
            let at = camera.screen(region.point + outward, center: center)
            var regionContext = context
            regionContext.opacity = Self.regionOpacity
            regionContext.draw(resolved, at: CGPoint(x: at.x, y: at.y))
        }

        // Labels: a zoom-sized prefix of the ranked list, fading by rank, dimmed outside the focus.
        let budget = GraphLabels.budget(zoom: zoom)
        for (rank, index) in plan.rankedLabels.prefix(budget).enumerated() {
            guard let resolved = context.resolveSymbol(id: SymbolID.label(nodes[index].id)) else { continue }
            var opacity = GraphLabels.opacity(rank: rank, budget: budget)
            if dimmed && !plan.litNodes.contains(index) { opacity *= Self.focusDim }
            if !dimmed && !plan.isHighlighted(index) { opacity *= Self.highlightDim }
            if plan.fadedNodes.contains(index) { opacity *= GraphPaint.fadedOpacity }
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
        // Set while a replay runs; `measuresReplay` marks a sample that started with one.
        var animating = false
        var measuresReplay = false

        init(appearedAt: TimeInterval = CACurrentMediaTime(), measuresSettle: Bool = true) {
            self.appearedAt = appearedAt
            self.measuresSettle = measuresSettle
            lastActive = appearedAt
        }

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
            if settled, !camera.isFlying, Self.reportsEntryDot { noteEntryDot() }
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

    private func noteEntryDot() {
        var point: String?
        if let dot = simulation.nodes.firstIndex(where: \.isEntry), size.width > 0, size.height > 0 {
            let center = SIMD2(Double(size.width) / 2, Double(size.height) / 2)
            let screen = camera.screen(simulation.position(at: dot), center: center)
            point = String(format: "%.4f,%.4f", screen.x / Double(size.width), screen.y / Double(size.height))
        }
        if point != entryDot { entryDot = point }
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
            workP95Milliseconds: FrameTimeSampler.percentile(sampler.workTimes, 0.95).map { $0 * 1000 },
            entryNodes: simulation.nodes.lazy.filter(\.isEntry).count,
            lens: lens,
            replay: activity.measuresReplay
        ))
    }

    // MARK: - Hit-testing

    private func nodeHit(_ point: SIMD2<Double>, center: SIMD2<Double>) -> GraphSimulation.Node? {
        let nodes = simulation.nodes
        let index = GraphHitTest.node(at: point, count: nodes.count, isEntry: { nodes[$0].isEntry }) { index in
            (camera.screen(simulation.position(at: index), center: center), simulation.radius(at: index) * camera.zoom)
        }
        return index.map { nodes[$0] }
    }

    // A tapped edge focuses its better-connected end, or its entity end when the other is a dot.
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
                    if !activity.pinching, let hit = nodeHit(start, center: center), !hit.isEntry,
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
                    if hit.isEntry {
                        onOpenEntry(id)
                    } else if focusedID == id {
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
                      let hit = nodeHit(Self.vector(drag.location), center: center),
                      !hit.isEntry
                else { return }
                let id = hit.id
                simulation.unpin(id)
                simulation.reheat(to: 0.1)
                wake()
            }
    }
}
