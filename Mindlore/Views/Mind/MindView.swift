import SwiftData
import SwiftUI

// The Mind tab: the whole journal's map, full screen, with a search panel pulled up from the
// bottom. Each channel means one thing: colour is kind (tags a small dark pin), size
// is how many entries in the window name it, and the window control at the top is time. Tapping a
// node or a result focuses it and shows its card; the trail of focuses is the breadcrumb row.
// Entity pages push onto the router's Mind path.
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
    @State private var arrivedAt: [UUID: Date] = [:]
    // Names a journal entry has at all, whatever the window does with them: what tells an empty
    // map apart from a quiet stretch, and a name only notes carry from one the window hides.
    @State private var journalNamed: Set<UUID> = []
    @State private var trail = FocusTrail()
    @State private var panelStop: SearchPanel.Stop = .half
    // Remembered for as long as the app runs, never saved as a setting (owner, 2026-09-23).
    @State private var window = MindWindow.default
    @State private var segment: EntitySearch.Segment = .all
    @State private var loadedKey: RefreshKey?
    @State private var drawerStats = MindDrawer.Stats.empty
    // Review questions left to answer, for the top bar's Tidy up button. Skips last the session and
    // are shared with the drawer's sheet, so an answered or skipped question leaves the count.
    @State private var reviewCount = 0
    @State private var skipped: Set<String> = []
    @State private var tidyingUp = false
    @State private var tidyHidden: [EntitySearch.Row] = []
    // The replay plays the window on screen, its start to today, and ends on the map it started
    // from (owner, 2026-09-23).
    @State private var player = MindReplayPlayer()
    @State private var replayTask: Task<Void, Never>?
    @State private var replayAvailable = false
    @Namespace private var glass

    // Grows with the text size, or the peek card's name, details, and bio clip at accessibility
    // sizes. Capped so the map keeps some room.
    static var cardHeight: CGFloat { min(UIFontMetrics.default.scaledValue(for: 260), 460) }
    private static let topBarHeight: CGFloat = 56
    private static let crumbRowHeight: CGFloat = 36

    private struct RefreshKey: Equatable {
        let revision: Int
        let window: MindWindow
        let segment: EntitySearch.Segment
        // Who the author is, so "what changed" never lists them.
        let userName: String
    }

    private var refreshKey: RefreshKey {
        RefreshKey(revision: graph.revision, window: window, segment: segment, userName: settings.userName)
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
                                mapHint: MindView.mapHint(for: focused, in: simulation, journalNamed: journalNamed),
                                open: { router.mindPath.append($0) },
                                dismiss: { trail.clear() }
                            )
                            .padding(.horizontal, 12)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        SearchPanel(
                            stop: $panelStop,
                            available: available,
                            segment: $segment,
                            skipped: $skipped,
                            stats: drawerStats,
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
            // On the map, inside the stack, where the drawer's copy of this sheet always worked.
            // Attached to the NavigationStack itself, it showed no question in the UI test that
            // renames a name on its page (whose Edit and Rename are sheets), comes back, and taps
            // Tidy up, while the same steps through the drawer's sheet passed.
            .sheet(isPresented: $tidyingUp, onDismiss: refreshReview) {
                TidyUpView(skipped: $skipped, hidden: tidyHidden, open: { router.mindPath.append(EntityRoute(id: $0)) })
            }
        }
        .environment(\.entityRouteReplacer, EntityRouteReplacer { loser, winner in
            router.replaceInMind(loser, with: winner)
            trail.replace(loser, with: winner)
        })
        .task(id: refreshKey) { refresh() }
        .onChange(of: skipped) { refreshReview() }
        .onChange(of: router.mindFocusRequest?.token) {
            // Ending the replay refreshes, and the refresh takes the request.
            if player.isRunning { endReplay(finished: false) } else { takeFocusRequest() }
        }
        // Nor from under a pushed page.
        .onChange(of: router.mindPath.isEmpty) { _, empty in
            if !empty { endReplay(finished: false) }
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
                arrivedAt: arrivedAt,
                recentreToken: MindWindow.allCases.firstIndex(of: window) ?? 0,
                animating: player.isRunning,
                clearsMissingFocus: false,
                visibleInsets: visibleInsets(available: available, safeArea: safeArea),
                onNavigate: { router.mindPath.append(EntityRoute(id: $0)) },
                onRendered: { graph.recordGraphRendered($0, window: window) },
                accessibilityIdentifier: "mindGraphCanvas"
            )
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
    // journal has nothing to draw and the only fix is writing something. A journal with nothing in
    // this stretch (or of this kind) has plenty; it only needs the window opened back up.
    @ViewBuilder
    private var emptyState: some View {
        if !journalNamed.isEmpty {
            ContentUnavailableView {
                Label("Nothing in this stretch", systemImage: "calendar")
            } description: {
                Text("Search still finds every name.")
            } actions: {
                if window != .all {
                    Button("Show all time") { window = .all }
                        .accessibilityIdentifier("mindShowAllTime")
                }
                if segment != .all {
                    Button("Show every kind") { segment = .all }
                        .accessibilityIdentifier("mindShowEveryKind")
                }
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

    // Play and the window control, centred, with room on the right for a button later (Reflect's
    // Numbers), and the breadcrumbs on their own row beneath once there are two. One glass
    // container, so the play button growing into the replay's date chip blends with the control.
    private var topBar: some View {
        VStack(spacing: 0) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    MindReplayControls(
                        player: player,
                        available: replayAvailable,
                        play: startReplay,
                        stop: { endReplay(finished: false) },
                        glass: glass
                    )
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    windowControl
                    // Up here rather than at the foot of the drawer, where nobody scrolled to it.
                    if reviewCount > 0 {
                        TidyUpButton(count: reviewCount, glass: glass) {
                            tidyHidden = MindDirectory.rows(in: modelContext).hidden
                            tidyingUp = true
                        }
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    }
                }
            }
            .frame(height: Self.topBarHeight)
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
                .frame(height: Self.crumbRowHeight)
            }
        }
    }

    // One glass capsule holding the four stretches; the chosen one sits in a tinted capsule that
    // slides between them rather than jumping. A replay plays the chosen one, so it stays chosen;
    // tapping any stretch ends the replay on it. Each stretch is a full 44pt tall and at least 48
    // wide, and the whole padded capsule takes the tap, not just the word (owner, 2026-09-24: the
    // old 30pt strips were hard to hit). No gap between them, so a tap never lands on nothing.
    private var windowControl: some View {
        HStack(spacing: 0) {
            ForEach(MindWindow.allCases, id: \.self) { option in
                let selected = option == window
                Button {
                    window = option
                    endReplay(finished: false)
                } label: {
                    Text(option.title)
                        .font(.subheadline.weight(selected ? .semibold : .regular))
                        .foregroundStyle(selected ? .primary : .secondary)
                        .lineLimit(1)
                        // Room for the play and Tidy up buttons on the narrowest phone.
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 14)
                        .frame(minWidth: 48, minHeight: 44)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(.tint.opacity(0.22))
                                    .matchedGeometryEffect(id: "selectedWindow", in: glass)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mindWindow-\(option.rawValue)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .glassEffect(.regular.interactive(), in: Capsule())
        // Four words across one row: past the largest standard size they truncated to "M…" and
        // "Y…". VoiceOver and Large Content Viewer still read the full titles.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .animation(Motion.resolve(.snappy, reduceMotion: reduceMotion), value: window)
        .sensoryFeedback(.selection, trigger: window)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Time")
        .accessibilityIdentifier("mindWindow")
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

    // In the canvas's own space, which runs under the status bar and the tab bar.
    private func visibleInsets(available: CGFloat, safeArea: EdgeInsets) -> EdgeInsets {
        let card = trail.current == nil ? 0 : Self.cardHeight + 8
        let crumbs = trail.ids.count > 1 ? Self.crumbRowHeight : 0
        return EdgeInsets(
            top: safeArea.top + Self.topBarHeight + crumbs,
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
        withAnimation(Motion.resolve(.snappy(duration: 0.3), reduceMotion: reduceMotion)) { panelStop = .peek }
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

    // What the map shows for one window and kind.
    struct Frame {
        var nodes: [GraphSimulation.Node]
        var edges: [EntityGraph.Edge]
        var names: [UUID: String]
    }

    static func frame(_ snapshot: MindMapSnapshot, window: MindWindow, segment: EntitySearch.Segment, asOf: Date) -> Frame {
        let kinds = segment == .all ? nil : Set(EntityKind.allCases.filter(segment.includes))
        let data = MindMap.graph(
            snapshot,
            window: window,
            kinds: kinds,
            minimumLinkCount: MindMap.minimumMentions(browsableCount: snapshot.linkedEntityIDs.count),
            asOf: asOf
        )
        return Frame(nodes: data.nodes, edges: data.edges, names: data.names)
    }

    // The first load builds the simulation; every change after that updates it in place, so
    // surviving nodes keep their spots and new ones grow out of their neighbours.
    private func refresh() {
        refreshReview()
        // During a replay the steps own the map; a graph change only re-reads its data.
        if player.isRunning {
            player.refetch()
            return
        }
        let now = Date.now
        let key = refreshKey
        let snapshot = graph.mapSnapshot(in: modelContext)
        replayAvailable = MindReplay(snapshot: snapshot, window: window, end: now) != nil
        let frame = Self.frame(snapshot, window: window, segment: segment, asOf: now)
        // Only a change the journal made blooms; a window or kind change reveals names that are
        // not new.
        let sameView = loadedKey.map { $0.window == key.window && $0.segment == key.segment } ?? false
        show(frame, snapshot: snapshot, blooms: sameView)
        let stats = MindDrawer.Stats.make(snapshot, window: window, asOf: now, excluding: MindStats.authorIDs(named: settings.userName, in: snapshot))
        if stats != drawerStats { drawerStats = stats }

        let directory = EntityDirectory(in: modelContext)
        trail.normalize(root: directory.root(of:), exists: { directory.entity($0).map { !$0.isDeleted } ?? false })
        // A focused entity off the map (another stretch, another kind) still needs its crumb name.
        for id in trail.ids where names[id] == nil {
            names[id] = directory.entity(id)?.name
        }

        if let loadedKey, loadedKey.window != key.window {
            graph.recordMindWindowChanged(key.window, nodes: frame.nodes.count)
        }
        loadedKey = key
        takeFocusRequest()
    }

    // The same questions TidyUpView asks, counted. Every answer bumps the graph revision, which
    // refreshes; a skip changes `skipped`, which calls this directly.
    private func refreshReview() {
        let count = ReviewQueue.questions(
            suggestions: graph.editor.suggestions(in: modelContext),
            unsure: graph.unsureLinks(in: modelContext),
            skipped: skipped
        ).count
        if count != reviewCount { reviewCount = count }
    }

    // Puts a frame on the canvas. State is only written when it changed. `publish: false` moves
    // the simulation alone: a replay step's view-state writes re-render all of Mind, which on the
    // phone pushed frame p95 to 32 ms at ten steps a second, so a replay publishes twice a second.
    private func show(_ frame: Frame, snapshot: MindMapSnapshot, publish: Bool = true, blooms: Bool) {
        if !publish, let simulation {
            simulation.update(nodes: frame.nodes, edges: frame.edges)
            return
        }
        // Bloom is the app noticing something, so it fires for the one case the user caused: a
        // name that was not on the map before an entry was written. Not on the first build, where
        // three hundred nodes arriving at once is a firework rather than a notice, and not on a
        // window or kind change, which reveals nodes that are not new. `blooms` carries the
        // second, the `simulation` check the first.
        if blooms, let simulation {
            let known = Set(simulation.nodes.map(\.id))
            let arrived = frame.nodes.filter { !known.contains($0.id) }
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
        if snapshot.linkedEntityIDs != journalNamed { journalNamed = snapshot.linkedEntityIDs }

        if let simulation {
            simulation.update(nodes: frame.nodes, edges: frame.edges)
            if version != simulation.topologyVersion { version = simulation.topologyVersion }
        } else {
            simulation = GraphSimulation(nodes: frame.nodes, edges: frame.edges)
        }
    }

    // MARK: - Replay

    private func startReplay() {
        guard !player.isRunning,
              player.start(now: .now, window: window, fetch: { graph.mapSnapshot(in: modelContext) })
        else { return }
        replayTask = Task { await runReplay() }
    }

    // Steps the map every 100 ms off a monotonic clock until the replay's end. The player's snapshot
    // is already trimmed to the window, so each step is all of what it holds as of the step's date,
    // in the kind the drawer has chosen.
    private func runReplay() async {
        let clock = ContinuousClock()
        let began = clock.now
        while !Task.isCancelled {
            let stepStart = clock.now
            guard let step = player.step(elapsed: (stepStart - began).seconds) else { return }
            let frame = Self.frame(step.snapshot, window: .all, segment: segment, asOf: step.asOf)
            show(frame, snapshot: step.snapshot, publish: MindReplay.publishes(step: player.stepSeconds.count) || step.finished, blooms: false)
            player.noteStep(seconds: (clock.now - stepStart).seconds)
            if step.finished {
                endReplay(finished: true)
                return
            }
            try? await Task.sleep(for: MindReplay.stepInterval)
        }
    }

    // Every way out comes through here, once: the map goes back to the window in place.
    private func endReplay(finished: Bool) {
        guard player.isRunning else { return }
        replayTask?.cancel()
        replayTask = nil
        let steps = player.stepSeconds
        let played = player.window
        let duration = player.startedAt.map { (ContinuousClock.now - $0).seconds } ?? 0
        player.stop()
        graph.recordMindReplayed(
            steps: steps.count,
            durationMilliseconds: duration * 1000,
            stepP95Milliseconds: FrameTimeSampler.percentile(steps, 0.95).map { $0 * 1000 },
            finished: finished,
            window: played,
            nodes: simulation?.nodeCount ?? 0
        )
        refresh()
    }
}

private extension Duration {
    var seconds: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}

// Tidy up's way in: a round glass button with the number of questions waiting. Mind only shows it
// while there is at least one, so it never sits there saying zero.
private struct TidyUpButton: View {
    let count: Int
    let glass: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "sparkles")
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: Circle())
                .glassEffectID("tidyUp", in: glass)
                .overlay(alignment: .topTrailing) {
                    Text(count > 99 ? "99+" : "\(count)")
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Palette.ember, in: Capsule())
                        .offset(x: 4, y: -4)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tidy up")
        .accessibilityValue(count == 1 ? "1 to check" : "\(count) to check")
        .accessibilityIdentifier("mindTidyUp")
    }
}

extension MindView {
    // Nothing until the map has been built once, so a Show in Mind jump never flashes the wrong
    // reason before the first refresh.
    static func mapHint(for id: UUID, in simulation: GraphSimulation?, journalNamed: Set<UUID>) -> EntityPeekCard.MapHint? {
        guard let simulation, simulation.index(of: id) == nil else { return nil }
        return journalNamed.contains(id) ? .outsideView : .notInJournal
    }
}

// The card over the map for the focused entity. Swiping it up opens the page, down dismisses.
private struct MindPeekOverlay: View {
    let entityID: UUID
    let mapHint: EntityPeekCard.MapHint?
    let open: (EntityRoute) -> Void
    let dismiss: () -> Void

    var body: some View {
        // Glass goes here, on the overlay, never inside `EntityPeekCard`. The same card is also
        // presented as a partial-height sheet (AskView, the editor), which iOS 26 already draws as
        // glass; giving the card itself glass would double it there. Over the map it is a plain
        // floating child with nothing under it but the canvas, which is what glass is for.
        EntityPeekCard(route: EntityRoute(id: entityID), mapHint: mapHint, open: open)
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
