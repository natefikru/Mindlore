import SwiftUI

// Keyed by id, not depth: depth is per-screen UI state, and rebuilding the sheet for a different
// entity must not reuse a stale simulation.
struct LocalGraphRoute: Identifiable {
    let id: UUID
}

// An entity's neighbours (depth 1) or their partners too (depth 2), from the entity page's
// "Graph" button. Owns its own NavigationStack, exactly ConnectionsView/EntryInsightsView's
// existing pattern, so a push made from inside this sheet can't corrupt the presenting page's
// own stack; it installs its own entityRouteReplacer for the same reason a merge made from in
// here must redirect this stack's own path, not the (absent) main one.
struct LocalGraphView: View {
    let subjectID: UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(GraphServices.self) private var graph
    @State private var depth = 1
    @State private var simulation: GraphSimulation?
    @State private var nameByID: [UUID: String] = [:]
    @State private var settleTask: Task<Void, Never>?
    @State private var path: [EntityRoute] = []

    private struct RebuildKey: Equatable {
        let depth: Int
        let revision: Int
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let simulation {
                    GraphCanvasView(simulation: simulation, namer: { nameByID[$0] }, anchoredID: subjectID) { id in
                        path.append(EntityRoute(id: id))
                    }
                    .accessibilityIdentifier("localGraphCanvas")
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(nameByID[subjectID] ?? "Graph")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    Picker("Depth", selection: $depth) {
                        Text("Neighbours").tag(1)
                        Text("Extended").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("localGraphDepth")
                }
            }
            .navigationDestination(for: EntityRoute.self) { EntityView(route: $0) }
            .environment(\.entityRouteReplacer, EntityRouteReplacer { loser, winner in
                path = EntityPagePresentation.replacing(loser, with: winner, in: path)
            })
            .task(id: RebuildKey(depth: depth, revision: graph.revision)) { rebuild() }
            .onDisappear { settleTask?.cancel() }
        }
    }

    // A full re-init, not a live re-force, since the node set itself changes with depth, and
    // keyed on graph.revision too, so a merge or rename made from a node pushed off this sheet's
    // own stack (its entityRouteReplacer keeps the id right; this is what keeps the picture and
    // its labels from going stale once the user pops back to it) rebuilds the picture as well.
    private func rebuild() {
        settleTask?.cancel()
        let data = graph.localGraph(around: subjectID, depth: depth, in: modelContext)
        nameByID = data.names
        let built = GraphSimulation(nodes: data.nodes, edges: data.edges)
        built.anchor(subjectID, at: .zero)
        simulation = built
        let start = Date.now
        settleTask = Task {
            await Self.waitForSettle(built)
            guard !Task.isCancelled else { return }
            graph.recordGraphRendered(nodes: data.nodes.count, edges: data.edges.count, settleMilliseconds: Date.now.timeIntervalSince(start) * 1000)
        }
    }

    private static func waitForSettle(_ simulation: GraphSimulation) async {
        while !simulation.settled {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if Task.isCancelled { return }
        }
    }
}
