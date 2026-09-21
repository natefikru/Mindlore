import RealityKit
import SwiftData
import SwiftUI

#if DEBUG

// The Phase A 3D spike, reached from a Debug row in Settings. It answers one question on the
// device: at 300 nodes, is the 3D picture easier to read and to hit than Mind's 2D map?
//
// It is deliberately not Mind. There are no filters, no lenses, no replay, no editing, and the
// layout is built once from a snapshot rather than kept warm. Everything it needs lives in this
// folder, so the whole thing is deleted by removing the folder, the Settings row, and the tests.
struct Mind3DSpikeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(GraphServices.self) private var graph

    @State private var model = Mind3DSpikeModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let scene = model.scene {
                spike(scene)
            } else {
                ProgressView("Settling")
                    .tint(.white)
                    .foregroundStyle(.white)
            }
            readout
        }
        .navigationTitle("3D spike")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.black, for: .navigationBar)
        .task {
            await model.load(graph: graph, context: modelContext)
        }
        .onDisappear {
            model.report(to: graph)
        }
    }

    private func spike(_ scene: Graph3DScene.Build) -> some View {
        RealityView { content in
            content.camera = .virtual
            content.add(scene.root)
            content.add(model.camera)
            model.placeCamera()
            model.subscribe(to: content)
        }
        .gesture(orbit)
        .simultaneousGesture(zoom)
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in model.select(entityNamed: value.entity.name) }
        )
    }

    private var orbit: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { model.orbit(to: $0.translation) }
            .onEnded { _ in model.endOrbit() }
    }

    private var zoom: some Gesture {
        MagnifyGesture()
            .onChanged { model.zoom(by: $0.magnification) }
            .onEnded { _ in model.endZoom() }
    }

    // Counts on screen, so a screenshot says which journal it was taken over and whether the
    // layout ever settled.
    private var readout: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 4) {
                if let selected = model.selectedName {
                    Text(selected)
                        .font(.headline)
                }
                Text(model.summary)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
            .padding(16)
        }
        .foregroundStyle(.white)
        .allowsHitTesting(false)
    }
}

// The spike's state and its camera. Separate from the view so the RealityView closures, which
// run outside the view's body, hold one object rather than a fistful of bindings.
@MainActor
@Observable
final class Mind3DSpikeModel {
    private(set) var scene: Graph3DScene.Build?
    private(set) var selectedName: String?
    private(set) var summary = "loading"

    let camera = PerspectiveCamera()

    // Orbit, in radians, and the camera's distance from the origin in metres.
    private var yaw: Float = 0
    private var pitch: Float = 0.35
    private var distance: Float = 1
    private var restDistance: Float = 1
    private var orbitStart: (yaw: Float, pitch: Float)?
    private var zoomStart: Float?
    // Auto-rotate runs until the first touch and never comes back: the comparison is about what
    // the owner can do with it, not about a demo reel.
    private var autoRotating = true
    private var gestureActive = false

    // What the camera looks at. The settled cloud does not sit on the origin: measured at 8 to 19
    // units off it, a fifth to nearly half the cloud's own radius, worst at small node counts. A
    // camera aimed at the origin therefore pushed the picture off to one side, and at four nodes
    // pushed it off the screen.
    private var centre: SIMD3<Float> = .zero
    private var names: [UUID: String] = [:]
    private var layout: Graph3DLayout?
    private let sampler = FrameTimeSampler()
    private var reported = false
    private var subscription: EventSubscription?

    // Radians a second while nothing is being touched.
    static let autoRotateRate: Float = 0.2
    static let maximumPitch: Float = 1.4
    static let orbitRadiansPerPoint: Float = 0.008

    func load(graph: GraphServices, context: ModelContext) async {
        guard layout == nil else { return }
        // The same path Mind takes, at the default filters: one cached snapshot, then the map.
        let snapshot = graph.mapSnapshot(in: context)
        let filters = MindFilters()
        let data = MindMap.graph(snapshot, kinds: filters.kinds, minimumLinkCount: filters.minimumMentions, asOf: .now)
        names = data.names
        // MindMap.graph already hands back layout-ordered nodes, which is what makes the
        // starting positions deterministic; ordering them again here would say otherwise.
        let settled = await GraphSimulation3D.settled(nodes: data.nodes, edges: data.edges)
        layout = settled
        centre = Self.centre(settled)
        restDistance = Self.framingDistance(settled, about: centre)
        distance = restDistance
        scene = Graph3DScene.build(
            settled,
            names: names,
            labelFontSize: Graph3DScene.labelFontSize(atDistance: restDistance, fieldOfView: Self.fieldOfView)
        )
        summary = Self.summary(settled)
    }

    // The field of view, applied to the phone's narrow axis. RealityKit's 60 degrees defaults to
    // the vertical, which on a portrait phone leaves about 15 degrees either side horizontally and
    // pushed a third of the 300-entry graph off the left edge.
    static let fieldOfView: Float = 60

    // A bounding sphere of radius R fits a half-angle A at R / sin(A), which is 2R at 30 degrees.
    // R is the 90th-percentile radius, not the largest: the cloud is not a sphere, and framing on
    // its one most distant node left the 300-entry graph filling half the screen with black
    // around it. The outermost few sit near the edge, and a pinch reaches them.
    static let framingPercentile = 0.9

    static func centre(_ layout: Graph3DLayout) -> SIMD3<Float> {
        guard !layout.positions.isEmpty else { return .zero }
        var sum = SIMD3<Double>(repeating: 0)
        for position in layout.positions { sum += position }
        return SIMD3<Float>(sum / Double(layout.positions.count))
    }

    static func framingDistance(_ layout: Graph3DLayout, about centre: SIMD3<Float> = .zero) -> Float {
        let middle = SIMD3<Double>(centre)
        let radii = layout.positions.map { (($0 - middle) * ($0 - middle)).sum().squareRoot() }
        let extent = FrameTimeSampler.percentile(radii, framingPercentile) ?? 0
        let halfAngle = fieldOfView / 2 * .pi / 180
        return max(0.5, Float(extent) * Graph3DScene.metresPerUnit / sin(halfAngle))
    }

    static func summary(_ layout: Graph3DLayout) -> String {
        let settle = layout.settleMilliseconds.map { String(format: "%.0f ms", $0) } ?? "never settled"
        return "\(layout.nodes.count) nodes, \(layout.edgeIndices.count) edges, settled in \(settle)"
    }

    // MARK: - Camera

    func placeCamera() {
        camera.camera.fieldOfViewInDegrees = Self.fieldOfView
        camera.camera.fieldOfViewOrientation = .horizontal
        let rotation = simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: pitch, axis: SIMD3(1, 0, 0))
        camera.transform = Transform(
            scale: .one,
            rotation: rotation,
            translation: centre * Graph3DScene.metresPerUnit + rotation.act(SIMD3(0, 0, distance))
        )
    }

    func orbit(to translation: CGSize) {
        stopAutoRotating()
        let start = orbitStart ?? (yaw, pitch)
        orbitStart = start
        yaw = start.yaw + Float(translation.width) * Self.orbitRadiansPerPoint
        pitch = min(Self.maximumPitch, max(-Self.maximumPitch, start.pitch + Float(translation.height) * Self.orbitRadiansPerPoint))
        placeCamera()
    }

    func endOrbit() {
        orbitStart = nil
        gestureActive = false
    }

    func zoom(by magnification: CGFloat) {
        stopAutoRotating()
        let start = zoomStart ?? distance
        zoomStart = start
        distance = min(restDistance * 4, max(restDistance * 0.1, start / Float(max(magnification, 0.01))))
        placeCamera()
    }

    func endZoom() {
        zoomStart = nil
        gestureActive = false
    }

    private func stopAutoRotating() {
        autoRotating = false
        gestureActive = true
    }

    // MARK: - Selection

    func select(entityNamed name: String) {
        guard let id = scene?.idByEntityName[name] else { return }
        selectedName = names[id]
    }

    // MARK: - Frames

    // One subscription to RealityKit's own update, which is both the auto-rotate clock and the
    // frame-time sample.
    //
    // It samples while the picture is moving, which is the same rule the 2D canvas uses, but not
    // the same window: 2D is still settling its layout while it draws, and this scene arrives
    // settled, so what is measured here is the auto-rotate and the gestures alone. Read the two
    // frame percentiles as "the cost of moving the picture", not as the same five seconds.
    func subscribe(to content: RealityViewCameraContent) {
        subscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            guard let self else { return }
            let started = CACurrentMediaTime()
            if autoRotating {
                yaw += Self.autoRotateRate * Float(event.deltaTime)
                placeCamera()
            }
            sampler.record(
                frameStart: started,
                workSeconds: CACurrentMediaTime() - started,
                interacting: autoRotating || gestureActive
            )
        }
    }

    // Once per appearance, on the way out, so a short look still leaves a line to compare.
    func report(to graph: GraphServices) {
        guard !reported, let layout else { return }
        reported = true
        graph.recordGraph3DRendered(Graph3DRenderStats(
            nodes: layout.nodes.count,
            edges: layout.edgeIndices.count,
            settleMilliseconds: layout.settleMilliseconds,
            frameSamples: sampler.intervals.count,
            frameP50Milliseconds: FrameTimeSampler.percentile(sampler.intervals, 0.5).map { $0 * 1000 },
            frameP95Milliseconds: FrameTimeSampler.percentile(sampler.intervals, 0.95).map { $0 * 1000 }
        ))
    }
}
#endif
