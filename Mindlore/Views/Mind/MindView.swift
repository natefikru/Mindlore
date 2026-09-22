import SwiftData
import SwiftUI

// The Mind tab: the whole journal's map, full screen, with a search panel pulled up from the
// bottom. Tapping a node or a result focuses it and shows its card; the trail of focuses is the
// breadcrumb row. Entity pages push onto the router's Mind path.
struct MindView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @Environment(GraphServices.self) private var graph
    @Environment(AppRouter.self) private var router
    @Environment(SettingsStore.self) private var settings
    @Environment(RecordingSession.self) private var recording
    @Environment(ProviderAccountStore.self) private var accounts
    @State private var simulation: GraphSimulation?
    @State private var version = 0
    @State private var names: [UUID: String] = [:]
    @State private var filters = MindFilters()
    @State private var loadedFilters: MindFilters?
    @State private var areaOf: [UUID: LifeArea] = [:]
    @State private var entryAreas: [UUID: [LifeArea]] = [:]
    @State private var regionLabels: [GraphRegion] = []
    @State private var haloed: Set<UUID> = []
    @State private var arrivedAt: [UUID: Date] = [:]
    // Entities the journal has at all, whatever the filters do with them: what tells an empty
    // journal apart from a filtered-out one.
    @State private var browsableCount = 0
    @State private var highlightedArea: LifeArea?
    @State private var trail = FocusTrail()
    @State private var panelStop: SearchPanel.Stop = .half
    @State private var showingFilters = false
    @State private var lens: MindLens = .kind
    @State private var paint: GraphPaint?
    @State private var paintGeneration = 0
    @State private var player = MindReplayPlayer()
    @State private var replayTask: Task<Void, Never>?
    @State private var replayAvailable = false
    // The top bar's controls share one glass container, so three lenses a few points apart sample
    // once and blend instead of stacking. The namespace is what lets the replay control morph
    // between its round button and its wider date chip rather than being replaced by it.
    @Namespace private var glass

    // Grows with the text size, or the peek card's name, details, and bio clip at accessibility
    // sizes. Capped so the map keeps some room.
    static var cardHeight: CGFloat { min(UIFontMetrics.default.scaledValue(for: 200), 360) }
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
                    VStack(spacing: 4) {
                        topBar
                        if lens != .kind {
                            MindLensLegend(lens: lens, paint: paint)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
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
                    .animation(Motion.resolve(.snappy, reduceMotion: reduceMotion), value: trail.current)
                }
            }
            // The keyboard never resizes the map or the panel's stops; only the panel's list
            // makes room for it.
            .ignoresSafeArea(.keyboard)
            // Nobody watches a replay from another tab.
            .onDisappear { endReplay(finished: false) }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: EntityRoute.self) { EntityView(route: $0) }
        }
        .environment(\.entityRouteReplacer, EntityRouteReplacer { loser, winner in
            router.replaceInMind(loser, with: winner)
            trail.replace(loser, with: winner)
        })
        .task(id: RefreshKey(filters: filters, revision: graph.revision)) { refresh() }
        .onChange(of: router.mindFocusRequest?.token) {
            // Ending the replay refreshes, and the refresh takes the request.
            if player.isRunning { endReplay(finished: false) } else { takeFocusRequest() }
        }
        // Nor from under a pushed page.
        .onChange(of: router.mindPath.isEmpty) { _, empty in
            if !empty { endReplay(finished: false) }
        }
        .onChange(of: router.dismissPresentationsToken) { showingFilters = false }
        .onChange(of: lens) {
            repaint()
            graph.recordMindLensChanged(lens.rawValue)
        }
        // Hiding an area in Settings removes its tile, which would leave no way to clear it.
        .onChange(of: settings.visibleLifeAreas) { _, visible in
            if let area = highlightedArea, !visible.contains(area) { highlightedArea = nil }
            if filters.groupsByArea { refresh() }
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
                highlightGroup: highlightedArea?.rawValue,
                paint: paint,
                regions: regionLabels,
                // The recency lens already colours by how lately a name came up, over thirty days
                // rather than seven. Two answers to the same question on one map is one too many.
                haloedIDs: lens == .recency ? [] : haloed,
                arrivedAt: arrivedAt,
                lens: lens,
                animating: player.isRunning,
                clearsMissingFocus: false,
                visibleInsets: visibleInsets(available: available, safeArea: safeArea),
                onNavigate: { router.mindPath.append(EntityRoute(id: $0)) },
                onOpenEntry: { openEntry($0) },
                onRendered: { graph.recordGraphRendered($0) }
            )
            .accessibilityIdentifier("mindGraphCanvas")
            .overlay {
                if simulation.nodeCount == 0 {
                    emptyState
                        .padding(.bottom, SearchPanel.height(for: panelStop, available: available))
                }
            }
        } else {
            ProgressView()
        }
    }

    // Two ways for the map to be blank, and they need opposite things said to them. An empty
    // journal has nothing to draw and the only fix is writing something. A journal whose nodes are
    // all filtered out used to draw an empty screen with a panel on it and no explanation at all.
    @ViewBuilder
    private var emptyState: some View {
        if browsableCount > 0 {
            ContentUnavailableView {
                Label("Nothing matches these filters", systemImage: "line.3.horizontal.decrease")
            } description: {
                Text("Search still finds everything the map leaves out.")
            } actions: {
                // Back to this journal's own default, minimum included: a minimum set too high is
                // the likeliest reason the map went blank, so a clear that kept it would do
                // nothing and look broken.
                Button("Clear filters") {
                    filters = MindFilters(minimumMentions: MindFilters.defaultMinimum(browsableCount: browsableCount))
                }
                    .accessibilityIdentifier("mindClearFilters")
            }
            .accessibilityIdentifier("mindEmptyState")
        } else if !AIServices.insightsUsable(settings: settings, accounts: accounts) {
            // Names come from insights, so with AI off a new entry adds nothing here. Saying "record
            // something" then left people recording and watching the map stay empty.
            ContentUnavailableView {
                Label("Nothing on the map yet", systemImage: "circle.hexagongrid")
            } description: {
                Text("The map is built from the people, places, and projects AI finds in your entries. Turn on AI in Settings to start it.")
            } actions: {
                Button("Open AI settings") { router.showSettings() }
                    .accessibilityIdentifier("mindEmptyOpenSettings")
            }
            .accessibilityIdentifier("mindEmptyState")
        } else {
            ContentUnavailableView {
                Label("Nothing on the map yet", systemImage: "circle.hexagongrid")
            } description: {
                Text("The people, places, and things you write about gather here, and draw lines to each other as they turn up together.")
            } actions: {
                Button("Record something") { recording.begin() }
                    .disabled(recording.status != .idle)
                    .accessibilityIdentifier("mindEmptyRecord")
            }
            .accessibilityIdentifier("mindEmptyState")
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
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    MindReplayControls(
                        player: player,
                        available: replayAvailable,
                        play: startReplay,
                        stop: { endReplay(finished: false) },
                        glass: glass
                    )
                    Menu {
                        Picker("Color by", selection: $lens) {
                            ForEach(MindLens.allCases, id: \.self) { lens in
                                Label(lens.title, systemImage: lens.symbol)
                                    .accessibilityIdentifier("mindLens-\(lens.rawValue)")
                            }
                        }
                    } label: {
                        Image(systemName: "paintpalette")
                            .font(.body.weight(.semibold))
                            .frame(width: 40, height: 40)
                            .glassEffect(.regular.interactive(), in: Circle())
                    }
                    .accessibilityLabel("Color by")
                    .accessibilityIdentifier("mindLens")
                    Button {
                        showingFilters = true
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.body.weight(.semibold))
                            .symbolEffect(.bounce, value: filters)
                            .frame(width: 40, height: 40)
                            .glassEffect(.regular.interactive(), in: Circle())
                    }
                    .accessibilityLabel("Filters")
                    .accessibilityIdentifier("mindFilters")
                }
            }
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
        highlightedArea.map { area in
            Set(areaOf.compactMap { $0.value == area ? $0.key : nil })
                .union(entryAreas.compactMap { $0.value.contains(area) ? $0.key : nil })
        }
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

    // What the map shows at one moment: the live map, or one replay step.
    struct Frame {
        var nodes: [GraphSimulation.Node]
        var edges: [EntityGraph.Edge]
        var names: [UUID: String]
        var areaOf: [UUID: LifeArea]
        var entryAreas: [UUID: [LifeArea]]
        var regions: [UUID: SIMD2<Double>]
    }

    static func frame(_ snapshot: MindMapSnapshot, filters: MindFilters, visibleAreas: [LifeArea], asOf: Date) -> Frame {
        let data = MindMap.graph(snapshot, kinds: filters.kinds, minimumLinkCount: filters.minimumMentions, asOf: asOf)
        var nodes = data.nodes
        var edges = data.edges
        var entryAreas: [UUID: [LifeArea]] = [:]
        if filters.showsEntries {
            let dots = MindMap.entryNodes(snapshot, onMap: Set(nodes.map(\.id)), asOf: asOf)
            nodes += dots.nodes
            edges += dots.edges
            for dot in dots.nodes {
                entryAreas[dot.id] = snapshot.entries[dot.id]?.areas ?? []
            }
        }
        let areaOf = MindMap.primaryAreas(snapshot, asOf: asOf)
        var regions: [UUID: SIMD2<Double>] = [:]
        if filters.groupsByArea {
            let points = MindRegions.points(visible: visibleAreas, entityCount: snapshot.entities.count)
            regions = MindRegions.nodePoints(nodes: nodes, areaOf: areaOf, entryAreas: entryAreas, points: points)
        }
        return Frame(nodes: nodes, edges: edges, names: data.names, areaOf: areaOf, entryAreas: entryAreas, regions: regions)
    }

    // The first load builds the simulation; every change after that updates it in place, so
    // surviving nodes keep their spots and new ones grow out of their neighbours.
    private func refresh() {
        // During a replay the steps own the map; a graph change only re-reads its data.
        if player.isRunning {
            player.refetch()
            return
        }
        let now = Date.now
        let snapshot = graph.mapSnapshot(in: modelContext)
        replayAvailable = MindReplay(snapshot: snapshot, end: now) != nil
        if loadedFilters == nil {
            let minimum = MindFilters.defaultMinimum(browsableCount: snapshot.entities.count)
            if minimum != filters.minimumMentions {
                filters.minimumMentions = minimum
            }
        }
        let frame = Self.frame(snapshot, filters: filters, visibleAreas: settings.visibleLifeAreas, asOf: now)
        show(frame, snapshot: snapshot, asOf: now, blooms: loadedFilters == filters)

        let directory = EntityDirectory(in: modelContext)
        trail.normalize(root: directory.root(of:), exists: { directory.entity($0).map { !$0.isDeleted } ?? false })
        // A focused entity off the map (filtered, or under the minimum) still needs its crumb name.
        for id in trail.ids where names[id] == nil {
            names[id] = directory.entity(id)?.name
        }

        if let loadedFilters, loadedFilters != filters {
            graph.recordMindFiltersChanged(
                kinds: filters.kinds.count,
                minimum: filters.minimumMentions,
                entries: filters.showsEntries,
                regions: filters.groupsByArea,
                nodes: frame.nodes.count
            )
        }
        loadedFilters = filters
        takeFocusRequest()
    }

    // Puts a frame on the canvas. State is only written when it changed. `publish: false` moves
    // the simulation alone: a replay step's view-state writes re-render all of Mind, which on the
    // phone pushed frame p95 to 32 ms at ten steps a second, so a replay publishes twice a second.
    private func show(_ frame: Frame, snapshot: MindMapSnapshot, asOf: Date, publish: Bool = true, blooms: Bool = false) {
        if !publish, let simulation {
            simulation.update(nodes: frame.nodes, edges: frame.edges, regions: frame.regions)
            return
        }
        // Bloom is the app noticing something, so it fires for the one case the user caused: a
        // name that was not on the map before an entry was written. Not on the first build, where
        // three hundred nodes arriving at once is a firework rather than a notice; not on a filter
        // change, where the stepper reveals nodes that are not new; and not during a replay, which
        // adds nodes by construction and is already its own animation. `blooms` carries the last
        // two, the `simulation` check the first.
        if blooms, let simulation {
            let known = Set(simulation.nodes.map(\.id))
            let arrived = frame.nodes.filter { !known.contains($0.id) && !$0.isEntry }
            if !arrived.isEmpty {
                let now = Date.now
                // Better-connected first, one Motion.stagger apart, on the rare entry that brings
                // several names at once.
                arrivedAt = Dictionary(uniqueKeysWithValues: arrived
                    .sorted { $0.linkCount == $1.linkCount ? $0.id.uuidString < $1.id.uuidString : $0.linkCount > $1.linkCount }
                    .enumerated()
                    .map { ($0.element.id, now.addingTimeInterval(Double($0.offset) * Motion.stagger)) })
            }
        }
        var names = frame.names
        for id in trail.ids where names[id] == nil {
            names[id] = self.names[id]
        }
        if names != self.names { self.names = names }
        if frame.areaOf != areaOf { areaOf = frame.areaOf }
        if frame.entryAreas != entryAreas { entryAreas = frame.entryAreas }
        let labels = regionLabels(snapshot)
        if labels != regionLabels { regionLabels = labels }
        // Taken at the frame's own date, so a replay's rings follow the replay.
        let rings = MindMap.haloed(snapshot, asOf: asOf)
        if rings != haloed { haloed = rings }
        if snapshot.entities.count != browsableCount { browsableCount = snapshot.entities.count }

        if let simulation {
            simulation.update(nodes: frame.nodes, edges: frame.edges, regions: frame.regions)
            if version != simulation.topologyVersion { version = simulation.topologyVersion }
        } else {
            simulation = GraphSimulation(nodes: frame.nodes, edges: frame.edges, regions: frame.regions)
        }
        repaint(snapshot, asOf: asOf)
    }

    private func regionLabels(_ snapshot: MindMapSnapshot) -> [GraphRegion] {
        guard filters.groupsByArea else { return [] }
        let points = MindRegions.points(visible: settings.visibleLifeAreas, entityCount: snapshot.entities.count)
        return LifeArea.allCases.compactMap { area in
            points[area].map { GraphRegion(id: area.rawValue, name: settings.name(of: area), point: $0, color: area.color) }
        }
    }

    // Rebuilds the lens paint for what the simulation holds now, at the replay's date while one
    // runs. Only a paint that differs is written, so a replay step doesn't re-render Mind.
    private func repaint(_ snapshot: MindMapSnapshot? = nil, asOf: Date? = nil) {
        guard let simulation else { return }
        if lens == .kind {
            if paint != nil { paint = nil }
            return
        }
        let snapshot = snapshot ?? graph.mapSnapshot(in: modelContext)
        let onMap = Set(simulation.nodes.lazy.filter { !$0.isEntry }.map(\.id))
        let date = asOf ?? player.asOf ?? .now
        guard let new = lens.paint(snapshot, onMap: onMap, asOf: date, generation: paintGeneration + 1),
              !(paint?.sameColours(as: new) ?? false)
        else { return }
        paintGeneration += 1
        paint = new
    }

    // MARK: - Replay

    private func startReplay() {
        guard !player.isRunning,
              player.start(now: .now, fetch: { graph.mapSnapshot(in: modelContext) })
        else { return }
        replayTask = Task { await runReplay() }
    }

    // Steps the map every 100 ms off a monotonic clock until the replay's end.
    private func runReplay() async {
        let clock = ContinuousClock()
        let began = clock.now
        while !Task.isCancelled {
            let stepStart = clock.now
            guard let step = player.step(elapsed: (stepStart - began).seconds) else { return }
            let frame = Self.frame(step.snapshot, filters: filters, visibleAreas: settings.visibleLifeAreas, asOf: step.asOf)
            show(frame, snapshot: step.snapshot, asOf: step.asOf, publish: MindReplay.publishes(step: player.stepSeconds.count) || step.finished)
            player.noteStep(seconds: (clock.now - stepStart).seconds)
            if step.finished {
                endReplay(finished: true)
                return
            }
            try? await Task.sleep(for: MindReplay.stepInterval)
        }
    }

    // Every way out comes through here, once: the map goes back to today in place.
    private func endReplay(finished: Bool) {
        guard player.isRunning else { return }
        replayTask?.cancel()
        replayTask = nil
        let steps = player.stepSeconds
        let duration = player.startedAt.map { (ContinuousClock.now - $0).seconds } ?? 0
        player.stop()
        graph.recordMindReplayed(
            steps: steps.count,
            durationMilliseconds: duration * 1000,
            stepP95Milliseconds: FrameTimeSampler.percentile(steps, 0.95).map { $0 * 1000 },
            finished: finished,
            nodes: simulation?.nodeCount ?? 0
        )
        refresh()
    }

    // A tapped entry dot opens the entry on the Journal tab, for reading when it's finished.
    private func openEntry(_ id: UUID) {
        guard let entry = try? modelContext.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id })).first,
              !entry.isDeleted
        else { return }
        router.showEntry(id, forReading: EntryReadMode.opensForReading(entry, automationStartedAt: settings.automationStartedAt))
        graph.recordMindEntryOpened()
    }
}

// The card over the map for the focused entity. Swiping it up opens the page, down dismisses.
private struct MindPeekOverlay: View {
    let entityID: UUID
    let onMap: Bool
    let open: (EntityRoute) -> Void
    let dismiss: () -> Void

    var body: some View {
        // Glass goes here, on the overlay, never inside `EntityPeekCard`. The same card is also
        // presented as a partial-height sheet (AskView, the editor), which iOS 26 already draws as
        // glass; giving the card itself glass would double it there. Over the map it is a plain
        // floating child with nothing under it but the canvas, which is what glass is for.
        EntityPeekCard(route: EntityRoute(id: entityID), showsMapHint: !onMap, open: open)
            .id(entityID)
            .frame(height: MindView.cardHeight)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
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
                Section {
                    Toggle(isOn: $filters.showsEntries) {
                        Label("Entries", systemImage: "circle.fill")
                    }
                    .accessibilityIdentifier("mindShowEntries")
                    Toggle(isOn: $filters.groupsByArea) {
                        Label("Group by life area", systemImage: "square.grid.3x3")
                    }
                    .accessibilityIdentifier("mindGroupByArea")
                } header: {
                    Text("Also")
                } footer: {
                    Text("Entries show as small grey dots beside what they mention. Tap one to read it.")
                }
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

private extension Duration {
    var seconds: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
