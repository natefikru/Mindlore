import Combine
import SwiftData
import SwiftUI

// Mind's pull-up panel: search and the kind chips, then what changed in the window, every name
// the window holds ranked by how often it came up, and a row for the names the user hid. The review
// questions are a button on Mind's top bar, where they get seen. Not a system sheet, which would cover the tab bar and the recording accessory.
// Only the header drags the panel; the list below scrolls on its own, so the two gestures never
// fight.
//
// Dragging is split from the content so it stays smooth. The panel used to set its frame height
// from the finger on every drag tick: each tick re-laid out the List and its rows, re-ran this whole
// body (the loose-end query's key, the search ranking), swapped glass for Paper at the first tick
// off `.peek`, clamped hard at the ends, and on release snapped with a fixed animation that ignored
// how fast the finger was going. Now `DrawerSurface` owns the drag in its own state, so a tick
// re-renders only that small view; the panel is always laid out at its full height and moved with
// an offset, so nothing inside it re-lays out while it moves; the list is an equatable view that a
// tick never rebuilds; the ends rubber-band; the two materials cross-fade by how far open it is;
// and release settles on a spring seeded with the finger's own velocity.
struct SearchPanel: View {
    enum Stop: String, CaseIterable {
        case peek, half, full
    }

    static var peekHeight: CGFloat { min(UIFontMetrics.default.scaledValue(for: 76), 120) }
    static let fullTopGap: CGFloat = 60
    static let edgeFade: CGFloat = 32
    // How far past its first and last stops the panel gives, and so how much taller than `.full`
    // it is laid out, so pulling it past the top never lifts its bottom edge off the tab bar.
    static let overscroll: CGFloat = 80
    // The distance off `.peek` over which glass turns into Paper and the kind chips fade in.
    static let revealDistance: CGFloat = 48

    nonisolated static func height(for stop: Stop, available: CGFloat) -> CGFloat {
        switch stop {
        case .peek: peekHeight
        case .half: max(peekHeight, available * 0.35)
        case .full: max(peekHeight, available - fullTopGap)
        }
    }

    // The height the panel is laid out at, whatever stop it rests on.
    nonisolated static func layoutHeight(available: CGFloat) -> CGFloat {
        height(for: .full, available: available) + overscroll
    }

    // The stop nearest to where the drag would come to rest. `predictedTranslation` is positive
    // downward, as DragGesture reports it.
    nonisolated static func snap(from stop: Stop, predictedTranslation: CGFloat, available: CGFloat) -> Stop {
        let target = height(for: stop, available: available) - predictedTranslation
        return Stop.allCases.min { abs(height(for: $0, available: available) - target) < abs(height(for: $1, available: available) - target) } ?? stop
    }

    // How much of the panel shows while a finger holds it: 1:1 between the lowest and highest stops,
    // and past either end the curve iOS scroll views use, which never gives more than `overscroll`.
    nonisolated static func visibleHeight(from stop: Stop, translation: CGFloat, available: CGFloat) -> CGFloat {
        let low = height(for: .peek, available: available)
        let high = height(for: .full, available: available)
        let raw = height(for: stop, available: available) - translation
        if raw > high { return high + rubberBand(raw - high) }
        if raw < low { return low - rubberBand(low - raw) }
        return raw
    }

    nonisolated static func rubberBand(_ overshoot: CGFloat, limit: CGFloat = overscroll) -> CGFloat {
        guard overshoot > 0 else { return 0 }
        return (1 - 1 / (overshoot * 0.55 / limit + 1)) * limit
    }

    // 0 at `.peek` (glass, no chips), 1 once the panel is `revealDistance` taller (Paper, chips).
    nonisolated static func reveal(visible: CGFloat, peek: CGFloat) -> CGFloat {
        min(1, max(0, (visible - peek) / revealDistance))
    }

    // The spring's starting speed, in the unit SwiftUI wants: the whole settle's distance per
    // second. The finger's velocity is in points per second, positive downward, while the height
    // grows upward. Capped, so a hard flick into a near stop can't fling the panel past it.
    nonisolated static func settleVelocity(from current: CGFloat, to target: CGFloat, dragVelocity: CGFloat) -> Double {
        let distance = target - current
        guard abs(distance) >= 1 else { return 0 }
        return min(12, max(-3, Double(-dragVelocity / distance)))
    }

    static let shape = UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous)

    @Binding var stop: Stop
    let available: CGFloat
    // The kind filter, owned by Mind because it filters the map as well as this list.
    @Binding var segment: EntitySearch.Segment
    // Review questions skipped this session, owned by Mind, whose top bar counts them.
    @Binding var skipped: Set<String>
    // The window's numbers, computed by Mind once per revision and window.
    let stats: MindDrawer.Stats
    let select: (UUID) -> Void
    let open: (UUID) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(GraphServices.self) private var graph
    @Environment(EntrySaver.self) private var saver
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var looseEnds: [LooseEnd]
    @State private var query = ""
    @State private var rows = MindDirectory.Rows()
    @State private var ranked: [MindDrawer.RankedRow] = []
    @State private var cards: [MindDrawer.ChangeCard] = []
    @State private var showingTidyUp = false
    @State private var keyboardOverlap: CGFloat = 0
    @State private var panelBottom: CGFloat = 0
    @FocusState private var fieldFocused: Bool

    private var searching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var results: [EntitySearch.Row] {
        EntitySearch.rank(EntitySearch.filter(rows.visible, segment: segment, query: query), query: query)
    }

    private var hiddenResults: [EntitySearch.Row] {
        EntitySearch.rank(EntitySearch.filter(rows.hidden, segment: segment, query: query), query: query)
    }

    private struct ContentKey: Equatable {
        let rows: [EntitySearch.Row]
        let stats: MindDrawer.Stats
        let segment: EntitySearch.Segment
    }

    private var refreshKey: MindDirectory.RefreshKey {
        MindDirectory.RefreshKey(revision: graph.revision, looseEnds: MindDirectory.looseEndKey(looseEnds.map { ($0.id, $0.statusRaw) }))
    }

    // Every stop change the panel makes itself; a drag's release animates its own way.
    private func move(to next: Stop) {
        withAnimation(Motion.resolve(.snappy(duration: 0.3), reduceMotion: reduceMotion)) { stop = next }
    }

    var body: some View {
        DrawerSurface(
            stop: $stop,
            available: available,
            reduceMotion: reduceMotion,
            willSettle: { next in if next != .full { fieldFocused = false } },
            header: header,
            chips: kindChips
                // Five words in one row; past this they pushed Themes off the screen.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge),
            rows: list.equatable()
        )
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { panelBottom = $0 }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            keyboardOverlap = max(0, panelBottom - frame.minY)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardOverlap = 0
        }
        .sensoryFeedback(Haptics.detent, trigger: stop)
        .onChange(of: fieldFocused) { _, focused in
            if focused { move(to: .full) }
        }
        .task(id: refreshKey) { refresh() }
        // Joined here, not in `body`.
        .task(id: ContentKey(rows: rows.visible, stats: stats, segment: segment)) {
            ranked = MindDrawer.ranked(rows.visible, stats: stats, segment: segment)
            cards = MindDrawer.cards(rows.visible, stats: stats, segment: segment)
        }
        .sheet(isPresented: $showingTidyUp, onDismiss: refresh) {
            TidyUpView(skipped: $skipped, hidden: rows.hidden, open: open)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mindSearchPanel")
        .accessibilityValue("stop=\(stop.rawValue)")
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(.secondary.opacity(0.5))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .accessibilityElement()
                .accessibilityLabel("Panel")
                .accessibilityIdentifier("mindPanelGrabber")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { move(to: stop == .peek ? .half : .peek) }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search people, places, themes", text: $query)
                    .focused($fieldFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .onSubmit { if let first = results.first { choose(first.id) } }
                    .accessibilityIdentifier("mindSearchField")
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Clear search")
                }
                if fieldFocused {
                    Button("Cancel") {
                        query = ""
                        fieldFocused = false
                        move(to: .half)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 16)
            // The same at every stop, so the header never changes height mid-drag; the chips
            // below it are always laid out and only fade in.
            .padding(.bottom, 4)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
    }

    // The kind chips sit with the field, since they filter the search, the list, and the map
    // alike. In the list they scrolled away, and the half-open panel's edge used to slice straight
    // through them.
    private var kindChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(EntitySearch.Segment.allCases, id: \.self) { option in
                    let selected = option == segment
                    Button {
                        segment = option
                    } label: {
                        Text(option.title)
                            .chip(tint: selected ? Palette.ember : nil, selected: selected)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("mindKindChip-\(option.rawValue)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
        }
        .sensoryFeedback(.selection, trigger: segment)
    }

    // MARK: - Content

    // Built from values only, so a drag tick, which never changes any of them, never rebuilds it.
    private var list: DrawerList {
        let isSearching = searching
        return DrawerList(
            query: query,
            searching: isSearching,
            results: isSearching ? results : [],
            hiddenResults: isSearching ? hiddenResults : [],
            cards: cards,
            ranked: ranked,
            hasVisible: !rows.visible.isEmpty,
            hiddenCount: rows.hidden.count,
            keyboardOverlap: keyboardOverlap,
            // The panel is laid out taller than what shows at this stop; the rows below the visible
            // edge must still be able to scroll up into view.
            bottomMargin: Self.edgeFade + max(0, Self.layoutHeight(available: available) - Self.height(for: stop, available: available)),
            tapCard: { card in
                graph.recordMindChangeTapped(card.change.kind, kind: card.kind)
                select(card.id)
            },
            choose: { choose($0) },
            open: open,
            showHidden: { showingTidyUp = true }
        )
    }

    // MARK: - Actions

    private func choose(_ id: UUID) {
        query = ""
        fieldFocused = false
        select(id)
    }

    private func refresh() {
        rows = MindDirectory.rows(in: modelContext)
    }
}

// Everything that moves while a finger holds the panel, and nothing else, so a drag tick re-renders
// only this. The panel is laid out once at `SearchPanel.layoutHeight` and slid with an offset;
// this view's own frame is the resting stop's height, which is all Mind's layout sees, and it clips
// whatever hangs below its bottom edge so the tall panel never covers the tab bar; the panel's
// content shape keeps that hidden part from taking touches.
private struct DrawerSurface<Header: View, Chips: View, Rows: View>: View {
    @Binding var stop: SearchPanel.Stop
    let available: CGFloat
    let reduceMotion: Bool
    // Runs just before a release changes the stop.
    let willSettle: (SearchPanel.Stop) -> Void
    let header: Header
    let chips: Chips
    let rows: Rows

    // Plain state, not @GestureState: the release animates it back to zero together with the new
    // stop in one spring, where a GestureState would reset on its own, unanimated, first.
    @State private var translation: CGFloat = 0
    // The translation of the drag's first reported tick, taken off every later one, so the panel
    // starts moving from where it was instead of jumping by the gesture's minimum distance.
    @State private var origin: CGFloat?
    @State private var topHeight: CGFloat = 0
    // Only to notice a drag that ended without onEnded (a cancel), which leaves `translation` set.
    @GestureState private var dragging = false

    var body: some View {
        let peek = SearchPanel.height(for: .peek, available: available)
        let settled = SearchPanel.height(for: stop, available: available)
        let visible = SearchPanel.visibleHeight(from: stop, translation: translation, available: available)
        let reveal = SearchPanel.reveal(visible: visible, peek: peek)
        let closed = stop == .peek

        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: settled)
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                    VStack(spacing: 8) {
                        header
                        chips
                            .padding(.bottom, 8)
                            .opacity(reveal)
                            .allowsHitTesting(!closed)
                            .accessibilityHidden(closed)
                    }
                    .contentShape(Rectangle())
                    .gesture(drag)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topHeight = $0 }
                    rows
                        // Whatever the visible edge cuts off fades out rather than stopping on a
                        // hard line, which reads as more below. The fade follows the edge.
                        .mask(alignment: .top) { fade(height: visible - topHeight) }
                        .allowsHitTesting(!closed)
                        .accessibilityHidden(closed)
                }
                .frame(maxWidth: .infinity)
                .frame(height: SearchPanel.layoutHeight(available: available), alignment: .top)
                .background { background(reveal: reveal) }
                .clipShape(SearchPanel.shape)
                // Touches only on what shows: a clip hides the part hanging below the resting
                // edge but would still let it take a tap meant for whatever is under it.
                .contentShape(TopSlice(height: visible))
                .offset(y: settled - visible)
            }
            .clipShape(AboveBottomEdge())
            .onChange(of: dragging) { _, live in
                // onEnded has had its turn by the time this task runs.
                if !live { Task { releaseIfCancelled() } }
            }
    }

    // The panel is two different things at its two sizes, and it needs a different material for
    // each. At `.peek` it is a grabber and a search field floating over the map, which is what the
    // house rule reserves glass for. Opened, it is most of the screen holding cards and rows, and
    // the same rule says never glass on list rows: the map bleeds through as blurred colour behind
    // them and reads as smudge rather than depth. Opened, it is an opaque surface with a hairline,
    // like every other content card in the app. The two cross-fade over the first
    // `revealDistance` points, so a drag never jumps from one to the other.
    @ViewBuilder
    private func background(reveal: CGFloat) -> some View {
        ZStack {
            if reveal < 1 {
                SearchPanel.shape.fill(.clear).glassEffect(.regular, in: SearchPanel.shape)
            }
            SearchPanel.shape
                .fill(Palette.paper)
                .overlay(SearchPanel.shape.stroke(Palette.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 8, y: -2)
                .opacity(reveal)
        }
    }

    private func fade(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            Color.black
                .frame(height: max(0, height - SearchPanel.edgeFade))
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: SearchPanel.edgeFade)
            Spacer(minLength: 0)
        }
    }

    // Global, since the header this sits on moves with the drag. Each tick writes one number with
    // animations off, so nothing eases behind the finger.
    private var drag: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .updating($dragging) { _, live, _ in live = true }
            .onChanged { value in
                let start = origin ?? value.translation.height
                if origin == nil { origin = start }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { translation = value.translation.height - start }
            }
            .onEnded { value in settle(value) }
    }

    // To the stop nearest where the flick would have carried it, on a spring that starts at the
    // finger's own speed, so letting go continues the motion rather than restarting it.
    private func settle(_ value: DragGesture.Value) {
        let start = origin ?? 0
        origin = nil
        let moved = value.translation.height - start
        let current = SearchPanel.visibleHeight(from: stop, translation: moved, available: available)
        let next = SearchPanel.snap(from: stop, predictedTranslation: value.predictedEndTranslation.height - start, available: available)
        let velocity = SearchPanel.settleVelocity(
            from: current,
            to: SearchPanel.height(for: next, available: available),
            dragVelocity: value.velocity.height
        )
        willSettle(next)
        withAnimation(settleAnimation(velocity: velocity)) {
            translation = 0
            stop = next
        }
    }

    private func releaseIfCancelled() {
        guard !dragging, origin != nil || translation != 0 else { return }
        origin = nil
        withAnimation(settleAnimation(velocity: 0)) { translation = 0 }
    }

    private func settleAnimation(velocity: Double) -> Animation? {
        Motion.resolve(.interpolatingSpring(duration: 0.4, bounce: 0.1, initialVelocity: velocity), reduceMotion: reduceMotion)
    }
}

// Everything above a view's bottom edge, however far above: the panel may slide up past its own
// frame, and must never show below it.
private struct AboveBottomEdge: Shape {
    func path(in rect: CGRect) -> Path {
        let reach: CGFloat = 10_000
        return Path(CGRect(x: rect.minX, y: rect.maxY - reach, width: rect.width, height: reach))
    }
}

// The top `height` points of a view: the part of the panel that shows.
private struct TopSlice: Shape {
    let height: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: min(rect.height, max(0, height))))
    }
}

// The list under the header. Equatable over its values and blind to its closures, so a re-render
// of the panel that changed none of them (a drag tick, a keyboard frame that moved nothing) skips
// it, rows and all.
private struct DrawerList: View, Equatable {
    let query: String
    let searching: Bool
    let results: [EntitySearch.Row]
    let hiddenResults: [EntitySearch.Row]
    let cards: [MindDrawer.ChangeCard]
    let ranked: [MindDrawer.RankedRow]
    let hasVisible: Bool
    let hiddenCount: Int
    let keyboardOverlap: CGFloat
    let bottomMargin: CGFloat
    let tapCard: (MindDrawer.ChangeCard) -> Void
    let choose: (UUID) -> Void
    let open: (UUID) -> Void
    let showHidden: () -> Void

    nonisolated static func == (lhs: DrawerList, rhs: DrawerList) -> Bool {
        lhs.query == rhs.query
            && lhs.searching == rhs.searching
            && lhs.results == rhs.results
            && lhs.hiddenResults == rhs.hiddenResults
            && lhs.cards == rhs.cards
            && lhs.ranked == rhs.ranked
            && lhs.hasVisible == rhs.hasVisible
            && lhs.hiddenCount == rhs.hiddenCount
            && lhs.keyboardOverlap == rhs.keyboardOverlap
            && lhs.bottomMargin == rhs.bottomMargin
    }

    var body: some View {
        List {
            if searching {
                searchResults
            } else {
                if !cards.isEmpty {
                    MindChangesRow(cards: cards, tap: tapCard)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                Section {
                    ForEach(ranked) { row in
                        MindRankedRow(row: row) { choose(row.id) }
                            .accessibilityIdentifier("mindRow-\(row.name)")
                    }
                    if ranked.isEmpty, hasVisible {
                        Text("No names in this stretch. Search still finds every one.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .listRowSeparator(.hidden)
                            .accessibilityIdentifier("mindDrawerEmptyWindow")
                    }
                }
                .listRowBackground(Color.clear)
                if hiddenCount > 0 {
                    Button(action: showHidden) {
                        HStack {
                            Label("Hidden names", systemImage: "eye.slash")
                            Spacer()
                            Text("\(hiddenCount)")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("mindHiddenNames")
                }
                // A row, not an overlay. Centred over the whole list it landed on top of the chips,
                // which are still there and still tappable.
                if !hasVisible, hiddenCount == 0 {
                    ContentUnavailableView(
                        "No names yet",
                        systemImage: "person.2",
                        description: Text("AI insights pull the people, places, and projects out of your entries.")
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("mindDirectoryEmpty")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        // The margin lets the last row scroll clear of the fade and of the part of the panel that
        // hangs below the visible edge at this stop.
        .contentMargins(.bottom, bottomMargin, for: .scrollContent)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: keyboardOverlap)
        }
        // Top-aligned: the list runs on below the visible edge, so its centre is not what shows.
        .overlay(alignment: .top) {
            if searching, results.isEmpty, hiddenResults.isEmpty {
                ContentUnavailableView.search(text: query)
                    .padding(.top, 40)
            }
        }
    }

    // Searching ignores the window: every name, hidden ones last, ranked by how well they match.
    @ViewBuilder
    private var searchResults: some View {
        Section {
            ForEach(results) { row in
                EntityRowButton(row: row) { choose(row.id) }
                    .accessibilityIdentifier("mindRow-\(row.name)")
            }
        }
        .listRowBackground(Color.clear)
        if !hiddenResults.isEmpty {
            Section("Hidden") {
                ForEach(hiddenResults) { row in
                    EntityRowButton(row: row) { open(row.id) }
                        .accessibilityIdentifier("mindHiddenRow-\(row.name)")
                }
            }
            .listRowBackground(Color.clear)
        }
    }
}

private struct EntityRowButton: View {
    let row: EntitySearch.Row
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: row.kind.symbol)
                    .foregroundStyle(row.kind.color)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if row.openLooseEnds > 0 {
                    Text("\(row.openLooseEnds) open")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.fill.tertiary, in: Capsule())
                        .accessibilityIdentifier("mindRowOpen-\(row.name)")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var detail: String {
        guard let last = row.lastMentioned else { return row.kind.label }
        return "\(row.kind.label) · last mentioned \(last.formatted(.relative(presentation: .named)))"
    }
}
