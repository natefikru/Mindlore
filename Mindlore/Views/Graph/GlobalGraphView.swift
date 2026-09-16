import SwiftUI

// Every browsable entity across the journal, pushed from Connections' own stack rather than a
// sheet: tapping a node here appends to the same path a Connections row already uses, instead of
// opening a second stack.
struct GlobalGraphView: View {
    @Binding var path: [ConnectionsPathItem]
    @Environment(\.modelContext) private var modelContext
    @Environment(GraphServices.self) private var graph
    @State private var kinds: Set<EntityKind> = Set(EntityKind.allCases)
    @State private var minimumLinkCount = 2
    @State private var asOf = Date.now
    @State private var showingFilters = false
    @State private var simulation: GraphSimulation?
    @State private var nameByID: [UUID: String] = [:]
    @State private var settleTask: Task<Void, Never>?

    private struct RebuildKey: Equatable {
        let kinds: Set<EntityKind>
        let minimumLinkCount: Int
        let asOf: Date
        let revision: Int
    }

    var body: some View {
        Group {
            if let simulation {
                GraphCanvasView(simulation: simulation, namer: { nameByID[$0] }) { id in
                    path.append(.entity(EntityRoute(id: id)))
                }
                .accessibilityIdentifier("globalGraphCanvas")
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Graph")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingFilters = true
                } label: {
                    Label("Filters", systemImage: "slider.horizontal.3")
                }
                .accessibilityIdentifier("globalGraphFilters")
            }
        }
        .sheet(isPresented: $showingFilters) {
            GlobalGraphFiltersView(kinds: $kinds, minimumLinkCount: $minimumLinkCount, asOf: $asOf)
        }
        .task(id: RebuildKey(kinds: kinds, minimumLinkCount: minimumLinkCount, asOf: asOf, revision: graph.revision)) { rebuild() }
        .onDisappear { settleTask?.cancel() }
    }

    // A full re-init every control change, the same as the local graph's depth toggle: nothing
    // in this phase updates a running simulation's node/edge set in place. Keyed on graph.revision
    // too, so a merge or rename made from a node pushed onto this same stack rebuilds the picture
    // once the user pops back to it, rather than showing a stale name or a since-merged node.
    private func rebuild() {
        settleTask?.cancel()
        let data = graph.globalGraph(asOf: asOf, kinds: kinds, minimumLinkCount: minimumLinkCount, in: modelContext)
        nameByID = data.names
        let built = GraphSimulation(nodes: data.nodes, edges: data.edges)
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

private struct GlobalGraphFiltersView: View {
    @Binding var kinds: Set<EntityKind>
    @Binding var minimumLinkCount: Int
    @Binding var asOf: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Kinds") {
                    ForEach(EntityKind.allCases, id: \.self) { candidate in
                        Toggle(isOn: Binding(
                            get: { kinds.contains(candidate) },
                            set: { on in
                                if on { kinds.insert(candidate) } else { kinds.remove(candidate) }
                            }
                        )) {
                            Label(candidate.heading, systemImage: candidate.symbol)
                        }
                        .accessibilityIdentifier("globalGraphKind-\(candidate.rawValue)")
                    }
                }
                Section("Minimum mentions") {
                    Stepper("At least \(minimumLinkCount)", value: $minimumLinkCount, in: 0...20)
                        .accessibilityIdentifier("globalGraphMinimumLinkCount")
                }
                Section("As of") {
                    DatePicker("Date", selection: $asOf, in: ...Date.now, displayedComponents: .date)
                        .accessibilityIdentifier("globalGraphAsOf")
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
