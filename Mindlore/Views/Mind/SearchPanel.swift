import Combine
import SwiftData
import SwiftUI

// Mind's pull-up panel: search and the kind chips, then what changed in the window, every name
// the window holds ranked by how often it came up, and a Tidy up row for the review questions and
// hidden names. Not a system sheet, which would cover the tab bar and the recording accessory.
// Only the header drags the panel; the list below scrolls on its own, so the two gestures never
// fight.
struct SearchPanel: View {
    enum Stop: String, CaseIterable {
        case peek, half, full
    }

    static var peekHeight: CGFloat { min(UIFontMetrics.default.scaledValue(for: 76), 120) }
    static let fullTopGap: CGFloat = 60
    static let edgeFade: CGFloat = 32

    nonisolated static func height(for stop: Stop, available: CGFloat) -> CGFloat {
        switch stop {
        case .peek: peekHeight
        case .half: max(peekHeight, available * 0.35)
        case .full: max(peekHeight, available - fullTopGap)
        }
    }

    // The stop nearest to where the drag would come to rest. `predictedTranslation` is positive
    // downward, as DragGesture reports it.
    nonisolated static func snap(from stop: Stop, predictedTranslation: CGFloat, available: CGFloat) -> Stop {
        let target = height(for: stop, available: available) - predictedTranslation
        return Stop.allCases.min { abs(height(for: $0, available: available) - target) < abs(height(for: $1, available: available) - target) } ?? stop
    }

    @Binding var stop: Stop
    let available: CGFloat
    // The kind filter, owned by Mind because it filters the map as well as this list.
    @Binding var segment: EntitySearch.Segment
    // The window's numbers, computed by Mind once per revision and window.
    let stats: MindDrawer.Stats
    let select: (UUID) -> Void
    let open: (UUID) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(GraphServices.self) private var graph
    @Environment(EntrySaver.self) private var saver
    @Environment(SettingsStore.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var looseEnds: [LooseEnd]
    @State private var query = ""
    @State private var rows = MindDirectory.Rows()
    @State private var ranked: [MindDrawer.RankedRow] = []
    @State private var cards: [MindDrawer.ChangeCard] = []
    @State private var questionCount = 0
    @State private var skipped: Set<String> = []
    @State private var showingTidyUp = false
    @State private var dragOffset: CGFloat = 0
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

    private var height: CGFloat {
        let base = Self.height(for: stop, available: available)
        return min(Self.height(for: .full, available: available), max(Self.peekHeight, base - dragOffset))
    }

    private static let shape = UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous)

    // The panel is two different things at its two sizes, and it needs a different material for
    // each. At `.peek` it is a grabber and a search field floating over the map, which is what the
    // house rule reserves glass for. Opened, it is most of the screen holding review cards, area
    // tiles and rows, and the same rule says never glass on list rows: the map bleeds through as
    // blurred colour behind the tiles and reads as smudge rather than depth. Opened, it is an
    // opaque surface with a hairline, like every other content card in the app.
    //
    // Found by looking at the screenshots. It looked right in the diff.
    @ViewBuilder
    private var panelBackground: some View {
        if stop == .peek {
            Self.shape.fill(.clear).glassEffect(.regular, in: Self.shape)
        } else {
            Self.shape
                .fill(Palette.paper)
                .overlay(Self.shape.stroke(Palette.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 8, y: -2)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if stop != .peek {
                content
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .top)
        .background(panelBackground)
        .clipShape(Self.shape)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { panelBottom = $0 }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            keyboardOverlap = max(0, panelBottom - frame.minY)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardOverlap = 0
        }
        .animation(Motion.resolve(.snappy(duration: 0.3), reduceMotion: reduceMotion), value: stop)
        .sensoryFeedback(Haptics.detent, trigger: stop)
        .onChange(of: fieldFocused) { _, focused in
            if focused { stop = .full }
        }
        .task(id: refreshKey) { refresh() }
        // Joined here, not in `body`: a drag re-renders the panel every frame.
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
                .accessibilityAction { stop = stop == .peek ? .half : .peek }
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
                        stop = .half
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, stop == .peek ? 12 : 4)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            // The kind chips sit with the field, since they filter the search, the list, and the
            // map alike. In the list they scrolled away, and the half-open panel's edge used to
            // slice straight through them.
            if stop != .peek {
                kindChips
                    .padding(.bottom, 8)
                    // Five words in one row; past this they pushed Themes off the screen.
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            // Global, since the header this sits on moves with the drag.
            DragGesture(minimumDistance: 6, coordinateSpace: .global)
                .onChanged { dragOffset = $0.translation.height }
                .onEnded { value in
                    let next = Self.snap(from: stop, predictedTranslation: value.predictedEndTranslation.height, available: available)
                    dragOffset = 0
                    if next != .full { fieldFocused = false }
                    stop = next
                }
        )
    }

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

    private var content: some View {
        List {
            if searching {
                searchResults
            } else {
                if !cards.isEmpty {
                    MindChangesRow(cards: cards) { card in
                        graph.recordMindChangeTapped(card.change.kind, kind: card.kind)
                        select(card.id)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                Section {
                    ForEach(ranked) { row in
                        MindRankedRow(row: row, areaName: row.area.map(settings.name(of:))) { choose(row.id) }
                            .accessibilityIdentifier("mindRow-\(row.name)")
                    }
                    if ranked.isEmpty, !rows.visible.isEmpty {
                        Text("No names in this stretch. Search still finds every one.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .listRowSeparator(.hidden)
                            .accessibilityIdentifier("mindDrawerEmptyWindow")
                    }
                }
                .listRowBackground(Color.clear)
                if questionCount > 0 || !rows.hidden.isEmpty {
                    Button {
                        showingTidyUp = true
                    } label: {
                        HStack {
                            Label("Tidy up", systemImage: "sparkles")
                            Spacer()
                            if questionCount > 0 {
                                Text(questionCount == 1 ? "1 to check" : "\(questionCount) to check")
                                    .foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("mindTidyUp")
                }
                // A row, not an overlay. Centred over the whole list it landed on top of the chips,
                // which are still there and still tappable.
                if rows.visible.isEmpty, rows.hidden.isEmpty {
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
        // Whatever the panel's edge cuts off fades out rather than stopping on a hard line, which
        // reads as more below; the margin lets the last row scroll clear of the fade.
        .contentMargins(.bottom, Self.edgeFade, for: .scrollContent)
        .mask {
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: Self.edgeFade)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: keyboardOverlap)
        }
        .overlay {
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

    // MARK: - Actions

    private func choose(_ id: UUID) {
        query = ""
        fieldFocused = false
        select(id)
    }

    private func refresh() {
        rows = MindDirectory.rows(in: modelContext)
        questionCount = ReviewQueue.questions(
            suggestions: graph.editor.suggestions(in: modelContext),
            unsure: graph.unsureLinks(in: modelContext),
            skipped: skipped
        ).count
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
