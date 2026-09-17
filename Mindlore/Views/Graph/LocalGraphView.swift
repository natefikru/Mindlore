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
    @State private var version = 0
    @State private var nameByID: [UUID: String] = [:]
    @State private var focusedID: UUID?
    @State private var path: [EntityRoute] = []

    private struct RebuildKey: Equatable {
        let depth: Int
        let revision: Int
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let simulation {
                    GraphCanvasView(
                        simulation: simulation,
                        version: version,
                        namer: { nameByID[$0] },
                        focusedID: $focusedID,
                        anchoredID: subjectID,
                        onNavigate: { path.append(EntityRoute(id: $0)) },
                        onRendered: { graph.recordGraphRendered($0) }
                    )
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
            .task(id: RebuildKey(depth: depth, revision: graph.revision)) { refresh() }
        }
    }

    // Built once, then updated in place when the depth changes, so the extended ring grows out of
    // the neighbours already on screen and the anchored subject stays put. Keyed on
    // graph.revision too, so a merge or rename made from a node pushed off this sheet's own stack
    // (its entityRouteReplacer keeps the id right; this is what keeps the picture and its labels
    // from going stale once the user pops back to it) updates the picture as well.
    private func refresh() {
        let data = graph.localGraph(around: subjectID, depth: depth, in: modelContext)
        let nodes = GraphSimulation.Node.layoutOrdered(data.nodes)
        nameByID = data.names
        if let simulation {
            simulation.update(nodes: nodes, edges: data.edges)
            version = simulation.topologyVersion
        } else {
            let built = GraphSimulation(nodes: nodes, edges: data.edges)
            built.anchor(subjectID, at: .zero)
            simulation = built
        }
    }
}
