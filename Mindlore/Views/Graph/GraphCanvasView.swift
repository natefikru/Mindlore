import SwiftUI

// The shared force-graph drawing surface LocalGraphView and GlobalGraphView both embed. Touches
// no model type: everything it draws comes from the simulation itself and a namer closure, the
// same "stay free of SwiftData" shape EntityChipIndex's consumers already follow.
struct GraphCanvasView: View {
    let simulation: GraphSimulation
    let namer: (UUID) -> String?
    // The local graph's centred subject, drawn distinctly and exempt from drag/long-press.
    var anchoredID: UUID?
    var onNavigate: (UUID) -> Void = { _ in }

    private enum DragTarget: Equatable {
        case node(UUID)
        case canvas
    }

    @State private var pan: CGSize = .zero
    @State private var zoom: CGFloat = 1
    @State private var panAtGestureStart: CGSize = .zero
    @State private var zoomAtGestureStart: CGFloat = 1
    @State private var dragTarget: DragTarget?
    @State private var selectedID: UUID?
    @State private var labelledIDs: [UUID] = []
    @State private var lastLabelledNodeSet: Set<UUID> = []

    private static let labelledCount = 12

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

            TimelineView(.animation(paused: simulation.settled)) { _ in
                Canvas { context, _ in
                    simulation.tick()
                    updateLabelledSubsetIfNeeded()

                    let neighboursOfSelected = selectedID.map {
                        EntityGraph.neighbourhood(of: $0, in: simulation.allEdges(), depth: 1)
                    } ?? []

                    var links = Path()
                    for edge in simulation.allEdges() {
                        guard let a = simulation.position(of: edge.a), let b = simulation.position(of: edge.b) else { continue }
                        links.move(to: screenPoint(a, center: center))
                        links.addLine(to: screenPoint(b, center: center))
                    }
                    context.stroke(links, with: .color(.secondary.opacity(0.3)), lineWidth: 1)

                    for id in simulation.allNodeIDs() {
                        guard let position = simulation.position(of: id),
                              let radius = simulation.radius(of: id),
                              let kind = simulation.kind(of: id)
                        else { continue }
                        let point = screenPoint(position, center: center)
                        let scaledRadius = radius * zoom
                        let circle = Path(ellipseIn: CGRect(x: point.x - scaledRadius, y: point.y - scaledRadius, width: scaledRadius * 2, height: scaledRadius * 2))
                        context.fill(circle, with: .color(kind.color))

                        if id == anchoredID {
                            context.stroke(circle, with: .color(.primary), lineWidth: 3)
                        } else if id == selectedID || neighboursOfSelected.contains(id) {
                            context.stroke(circle, with: .color(.primary), lineWidth: 2)
                        }
                    }

                    for id in labelSubset() {
                        guard let resolved = context.resolveSymbol(id: id),
                              let position = simulation.position(of: id),
                              let radius = simulation.radius(of: id)
                        else { continue }
                        let point = screenPoint(position, center: center)
                        context.draw(resolved, at: CGPoint(x: point.x, y: point.y - radius * zoom - 10))
                    }
                } symbols: {
                    ForEach(labelSubset(), id: \.self) { id in
                        if let name = namer(id) {
                            Text(name).font(.caption2).tag(id)
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(dragGesture(center: center))
                .gesture(magnificationGesture)
                .simultaneousGesture(tapGesture(center: center))
                .simultaneousGesture(longPressGesture(center: center))
            }
        }
    }

    // MARK: - Labelled subset

    // The largest nodes by linkCount, recomputed only when the node set changes (it depends on
    // static linkCount, not position, so re-sorting every frame would be wasted work), plus
    // whichever node is selected or anchored regardless of rank.
    private func updateLabelledSubsetIfNeeded() {
        let currentIDs = Set(simulation.allNodeIDs())
        guard currentIDs != lastLabelledNodeSet else { return }
        lastLabelledNodeSet = currentIDs
        let ranked = simulation.allNodeIDs().sorted { (simulation.linkCount(of: $0) ?? 0) > (simulation.linkCount(of: $1) ?? 0) }
        labelledIDs = Array(ranked.prefix(Self.labelledCount))
    }

    private func labelSubset() -> [UUID] {
        var result = labelledIDs
        if let selectedID, !result.contains(selectedID) { result.append(selectedID) }
        if let anchoredID, !result.contains(anchoredID) { result.append(anchoredID) }
        return result
    }

    // MARK: - Coordinate conversion

    private func screenPoint(_ world: SIMD2<Double>, center: CGPoint) -> CGPoint {
        CGPoint(x: center.x + CGFloat(world.x) * zoom + pan.width, y: center.y + CGFloat(world.y) * zoom + pan.height)
    }

    private func worldPoint(_ screen: CGPoint, center: CGPoint) -> SIMD2<Double> {
        SIMD2(Double((screen.x - center.x - pan.width) / zoom), Double((screen.y - center.y - pan.height) / zoom))
    }

    private func hitTest(_ point: CGPoint, center: CGPoint) -> UUID? {
        for id in simulation.allNodeIDs().reversed() {
            guard let position = simulation.position(of: id), let radius = simulation.radius(of: id) else { continue }
            let screen = screenPoint(position, center: center)
            let dx = point.x - screen.x, dy = point.y - screen.y
            if (dx * dx + dy * dy).squareRoot() <= max(radius * zoom, 12) { return id }
        }
        return nil
    }

    // MARK: - Gestures

    // A hit at the drag's start pins that node for the rest of the drag, sticky after release; a
    // miss pans the canvas instead.
    private func dragGesture(center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .local)
            .onChanged { value in
                if dragTarget == nil {
                    dragTarget = hitTest(value.startLocation, center: center).map(DragTarget.node) ?? .canvas
                }
                switch dragTarget {
                case .node(let id):
                    simulation.pin(id, at: worldPoint(value.location, center: center))
                case .canvas, nil:
                    pan = CGSize(width: panAtGestureStart.width + value.translation.width, height: panAtGestureStart.height + value.translation.height)
                }
            }
            .onEnded { _ in
                dragTarget = nil
                panAtGestureStart = pan
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in zoom = max(0.2, min(4, zoomAtGestureStart * value)) }
            .onEnded { _ in zoomAtGestureStart = zoom }
    }

    // First tap on a node selects it; a second tap on the already-selected node navigates. A tap
    // on empty canvas clears the selection.
    private func tapGesture(center: CGPoint) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                guard let id = hitTest(value.location, center: center) else {
                    selectedID = nil
                    return
                }
                if selectedID == id {
                    onNavigate(id)
                } else {
                    selectedID = id
                }
            }
    }

    // Unpinning a pinned (not anchored) node: a long-press, not a second tap, since a real
    // double-tap recognizer has no defined priority against the select/navigate tap state above.
    private func longPressGesture(center: CGPoint) -> some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            .onEnded { value in
                guard case .second(true, let drag?) = value, let id = hitTest(drag.location, center: center), id != anchoredID else { return }
                simulation.unpin(id)
            }
    }
}
