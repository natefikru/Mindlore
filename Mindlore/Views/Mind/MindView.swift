import SwiftData
import SwiftUI

// The Mind tab: the whole journal's map, full screen, with a search panel pulled up from the
// bottom. Tapping a node or a result focuses it and shows its card; the trail of focuses is the
// breadcrumb row. Entity pages push onto the router's Mind path.
struct MindView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(GraphServices.self) private var graph
    @Environment(AppRouter.self) private var router
    @Environment(SettingsStore.self) private var settings
    @State private var simulation: GraphSimulation?
    @State private var version = 0
    @State private var names: [UUID: String] = [:]
    @State private var filters = MindFilters()
    @State private var loadedFilters: MindFilters?
    @State private var areaOf: [UUID: LifeArea] = [:]
    @State private var highlightedArea: LifeArea?
    @State private var trail = FocusTrail()
    @State private var panelStop: SearchPanel.Stop = .half
    @State private var showingFilters = false

    static let cardHeight: CGFloat = 200
    private static let topBarHeight: CGFloat = 52

    private struct RefreshKey: Equatable {
        let filters: MindFilters
        let revision: Int
    }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.mindPath) {
            GeometryReader { geometry in
                let available = geometry.size.height
                let safeArea = geometry.safeAreaInsets
                ZStack(alignment: .bottom) {
                    graphLayer(available: available, safeArea: safeArea)
                        .ignoresSafeArea()
                    VStack(spacing: 0) {
                        topBar
                        Spacer(minLength: 0)
                    }
                    VStack(spacing: 8) {
                        if let focused = trail.current {
                            MindPeekOverlay(
                                entityID: focused,
                                onMap: simulation?.index(of: focused) != nil,
                                open: { router.mindPath.append($0) },
                                dismiss: { trail.clear() }
                            )
                            .padding(.horizontal, 12)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        SearchPanel(
                            stop: $panelStop,
                            available: available,
                            highlightedArea: $highlightedArea,
                            select: { focus($0, source: .search) },
                            open: { router.mindPath.append(EntityRoute(id: $0)) }
                        )
                    }
                    .animation(.snappy, value: trail.current)
                }
            }
            // The keyboard never resizes the map or the panel's stops; only the panel's list
            // makes room for it.
            .ignoresSafeArea(.keyboard)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: EntityRoute.self) { EntityView(route: $0) }
        }
        .environment(\.entityRouteReplacer, EntityRouteReplacer { loser, winner in
            router.replaceInMind(loser, with: winner)
            trail.replace(loser, with: winner)
        })
        .task(id: RefreshKey(filters: filters, revision: graph.revision)) { refresh() }
        .onChange(of: router.mindFocusRequest?.token) { takeFocusRequest() }
        .onChange(of: router.dismissPresentationsToken) { showingFilters = false }
        // Hiding an area in Settings removes its tile, which would leave no way to clear it.
        .onChange(of: settings.visibleLifeAreas) { _, visible in
            if let area = highlightedArea, !visible.contains(area) { highlightedArea = nil }
        }
        .sheet(isPresented: $showingFilters) {
            MindFiltersView(filters: $filters)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Layers

    @ViewBuilder
    private func graphLayer(available: CGFloat, safeArea: EdgeInsets) -> some View {
        if let simulation {
            GraphCanvasView(
                simulation: simulation,
                version: version,
                namer: { names[$0] },
                focusedID: Binding(
                    get: { trail.current },
                    set: { new in
                        if let new {
                            focus(new, source: .node)
                        } else {
                            trail.clear()
                        }
                    }
                ),
                highlightedIDs: highlightedIDs,
                clearsMissingFocus: false,
                visibleInsets: visibleInsets(available: available, safeArea: safeArea),
                onNavigate: { router.mindPath.append(EntityRoute(id: $0)) },
                onRendered: { graph.recordGraphRendered($0) }
            )
            .accessibilityIdentifier("mindGraphCanvas")
            .overlay {
                if simulation.nodeCount == 0 {
                    ContentUnavailableView(
                        "Nothing on the map yet",
                        systemImage: "circle.hexagongrid",
                        description: Text("People, places, and tags from your entries will gather here.")
                    )
                    .padding(.bottom, SearchPanel.height(for: panelStop, available: available))
                }
            }
        } else {
            ProgressView()
        }
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 8) {
            if trail.ids.count > 1 {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(trail.ids, id: \.self) { id in
                                crumb(id)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .onChange(of: trail.current) { proxy.scrollTo(trail.current, anchor: .trailing) }
                }
            }
            Spacer(minLength: 0)
            Button {
                showingFilters = true
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.body.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .background(.regularMaterial, in: Circle())
            }
            .accessibilityLabel("Filters")
            .accessibilityIdentifier("mindFilters")
            .padding(.trailing, 12)
        }
        .frame(height: Self.topBarHeight)
    }

    private func crumb(_ id: UUID) -> some View {
        let name = names[id] ?? "…"
        let isCurrent = id == trail.current
        return Button {
            trail.back(to: id)
            graph.recordMindFocused(source: .crumb, onMap: simulation?.index(of: id) != nil)
        } label: {
            Text(name)
                .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isCurrent ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.regularMaterial), in: Capsule())
        }
        .buttonStyle(.plain)
        .id(id)
        .accessibilityIdentifier("mindCrumb-\(name)")
    }

    private var highlightedIDs: Set<UUID>? {
        highlightedArea.map { area in Set(areaOf.compactMap { $0.value == area ? $0.key : nil }) }
    }

    // In the canvas's own space, which runs under the status bar and the tab bar.
    private func visibleInsets(available: CGFloat, safeArea: EdgeInsets) -> EdgeInsets {
        let card = trail.current == nil ? 0 : Self.cardHeight + 8
        return EdgeInsets(
            top: safeArea.top + Self.topBarHeight,
            leading: 0,
            bottom: safeArea.bottom + SearchPanel.height(for: panelStop, available: available) + card,
            trailing: 0
        )
    }

    // MARK: - Focus

    private func focus(_ id: UUID, source: GraphServices.FocusSource) {
        // An entity off the map has no name from the graph data; its crumb still needs one.
        if names[id] == nil {
            names[id] = EntityDirectory(in: modelContext).entity(id)?.name
        }
        trail.focus(id)
        panelStop = .peek
        graph.recordMindFocused(source: source, onMap: simulation?.index(of: id) != nil)
    }

    // A jump from elsewhere starts a fresh trail. Taken only once the map exists, so the first
    // refresh picks up a jump that arrived before Mind was ever built.
    private func takeFocusRequest() {
        guard simulation != nil, let id = router.consumeMindFocus() else { return }
        trail.clear()
        focus(EntityDirectory(in: modelContext).root(of: id), source: .showInMind)
    }

    // MARK: - Data

    // The first load builds the simulation; every change after that updates it in place, so
    // surviving nodes keep their spots and new ones grow out of their neighbours.
    private func refresh() {
        if loadedFilters == nil {
            let browsable = ((try? modelContext.fetch(FetchDescriptor<Entity>())) ?? []).filter { !$0.isDeleted && $0.isBrowsable }.count
            let minimum = MindFilters.defaultMinimum(browsableCount: browsable)
            if minimum != filters.minimumMentions {
                filters.minimumMentions = minimum
            }
        }
        let data = graph.globalGraph(kinds: filters.kinds, minimumLinkCount: filters.minimumMentions, in: modelContext)
        let nodes = GraphSimulation.Node.layoutOrdered(data.nodes)
        names = data.names
        areaOf = graph.primaryAreas(in: modelContext)

        let directory = EntityDirectory(in: modelContext)
        trail.normalize(root: directory.root(of:), exists: { directory.entity($0).map { !$0.isDeleted } ?? false })
        // A focused entity off the map (filtered, or under the minimum) still needs its crumb name.
        for id in trail.ids where names[id] == nil {
            names[id] = directory.entity(id)?.name
        }

        if let simulation {
            simulation.update(nodes: nodes, edges: data.edges)
            version = simulation.topologyVersion
        } else {
            simulation = GraphSimulation(nodes: nodes, edges: data.edges)
        }
        if let loadedFilters, loadedFilters != filters {
            graph.recordMindFiltersChanged(kinds: filters.kinds.count, minimum: filters.minimumMentions, nodes: nodes.count)
        }
        loadedFilters = filters
        takeFocusRequest()
    }
}

// The card over the map for the focused entity. Swiping it up opens the page, down dismisses.
private struct MindPeekOverlay: View {
    let entityID: UUID
    let onMap: Bool
    let open: (EntityRoute) -> Void
    let dismiss: () -> Void

    var body: some View {
        EntityPeekCard(route: EntityRoute(id: entityID), showsMapHint: !onMap, open: open)
            .id(entityID)
            .frame(height: MindView.cardHeight)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        if value.translation.height < -60 {
                            open(EntityRoute(id: entityID))
                        } else if value.translation.height > 60 {
                            dismiss()
                        }
                    }
            )
    }
}

private struct MindFiltersView: View {
    @Binding var filters: MindFilters
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Show") {
                    ForEach(EntityKind.allCases, id: \.self) { kind in
                        Toggle(isOn: Binding(
                            get: { filters.kinds.contains(kind) },
                            set: { on in
                                if on { filters.kinds.insert(kind) } else { filters.kinds.remove(kind) }
                            }
                        )) {
                            Label(kind.heading, systemImage: kind.symbol)
                        }
                        .accessibilityIdentifier("mindKind-\(kind.rawValue)")
                    }
                }
                Section {
                    Stepper(
                        filters.minimumMentions == 1 ? "At least 1 mention" : "At least \(filters.minimumMentions) mentions",
                        value: $filters.minimumMentions,
                        in: 1...20
                    )
                    .accessibilityIdentifier("mindMinimumMentions")
                } footer: {
                    Text("Search still finds everything the map leaves out.")
                }
            }
            .navigationTitle("Map filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
