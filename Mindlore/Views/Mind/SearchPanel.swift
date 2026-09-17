import Combine
import SwiftData
import SwiftUI

// Mind's pull-up panel: search, one review question, the area tiles, and every entity. Not a
// system sheet, which would cover the tab bar and the recording accessory. Only the header drags
// the panel; the list below scrolls on its own, so the two gestures never fight.
struct SearchPanel: View {
    enum Stop: String, CaseIterable {
        case peek, half, full
    }

    static let peekHeight: CGFloat = 76
    static let fullTopGap: CGFloat = 60

    nonisolated static func height(for stop: Stop, available: CGFloat) -> CGFloat {
        switch stop {
        case .peek: peekHeight
        case .half: max(peekHeight, available * 0.45)
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
    @Binding var highlightedArea: LifeArea?
    let select: (UUID) -> Void
    let open: (UUID) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(GraphServices.self) private var graph
    @Environment(EntrySaver.self) private var saver
    @Environment(SettingsStore.self) private var settings
    @Query private var looseEnds: [LooseEnd]
    @State private var query = ""
    @State private var segment: EntitySearch.Segment = .all
    @State private var rows = MindDirectory.Rows()
    @State private var question: ReviewQueue.Question?
    @State private var questionDate: Date?
    @State private var skipped: Set<String> = []
    @State private var dragOffset: CGFloat = 0
    @State private var keyboardOverlap: CGFloat = 0
    @State private var panelBottom: CGFloat = 0
    @State private var showsHidden = false
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

    private var refreshKey: MindDirectory.RefreshKey {
        MindDirectory.RefreshKey(revision: graph.revision, looseEnds: MindDirectory.looseEndKey(looseEnds.map { ($0.id, $0.statusRaw) }))
    }

    private var height: CGFloat {
        let base = Self.height(for: stop, available: available)
        return min(Self.height(for: .full, available: available), max(Self.peekHeight, base - dragOffset))
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
        .background(.regularMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16, style: .continuous))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, y: -2)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { panelBottom = $0 }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            keyboardOverlap = max(0, panelBottom - frame.minY)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardOverlap = 0
        }
        .animation(.snappy(duration: 0.3), value: stop)
        .onChange(of: fieldFocused) { _, focused in
            if focused { stop = .full }
        }
        .task(id: refreshKey) { refresh() }
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
                TextField("Search people, places, tags", text: $query)
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
            .padding(.bottom, 12)
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

    // MARK: - Content

    private var content: some View {
        List {
            if !searching {
                if let question {
                    ReviewCard(question: question, entryDate: questionDate, names: namesByID, answer: answer)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                areaTiles
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            Picker("Show", selection: $segment) {
                ForEach(EntitySearch.Segment.allCases, id: \.self) { segment in
                    Text(segment.title)
                        .accessibilityIdentifier("mindSegment-\(segment.title)")
                        .tag(segment)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section {
                ForEach(results) { row in
                    EntityRowButton(row: row) { choose(row.id) }
                        .accessibilityIdentifier("mindRow-\(row.name)")
                }
            }
            .listRowBackground(Color.clear)

            if !hiddenResults.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $showsHidden) {
                        ForEach(hiddenResults) { row in
                            EntityRowButton(row: row) { open(row.id) }
                                .accessibilityIdentifier("mindHiddenRow-\(row.name)")
                        }
                    } label: {
                        Text("Hidden (\(hiddenResults.count))")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("mindHiddenSection")
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: keyboardOverlap)
        }
        .overlay {
            if results.isEmpty && hiddenResults.isEmpty {
                if searching {
                    ContentUnavailableView.search(text: query)
                        .padding(.top, 40)
                } else if rows.visible.isEmpty && rows.hidden.isEmpty {
                    ContentUnavailableView(
                        "No people or places yet",
                        systemImage: "person.2",
                        description: Text("Insights on your entries fill this in.")
                    )
                    .padding(.top, 120)
                }
            }
        }
    }

    private var areaTiles: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(settings.visibleLifeAreas, id: \.self) { area in
                let selected = highlightedArea == area
                Button {
                    highlightedArea = selected ? nil : area
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: area.symbol)
                            .foregroundStyle(area.color)
                        Text(settings.name(of: area))
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        selected ? AnyShapeStyle(area.color.opacity(0.25)) : AnyShapeStyle(.fill.tertiary),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay {
                        if selected {
                            RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(area.color, lineWidth: 1.5)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("areaTile-\(area.rawValue)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var namesByID: [UUID: String] {
        Dictionary((rows.visible + rows.hidden).map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Actions

    private func choose(_ id: UUID) {
        query = ""
        fieldFocused = false
        select(id)
    }

    private func answer(_ question: ReviewQueue.Question, _ answer: GraphServices.ReviewAnswer) {
        if answer == .skip {
            skipped.insert(question.id)
        }
        saver.flush()
        graph.answer(question, with: answer, in: modelContext)
        // A real answer bumps graph.revision, which refreshes; a skip doesn't.
        if answer == .skip {
            refresh()
        }
    }

    private func refresh() {
        rows = MindDirectory.rows(in: modelContext)
        question = ReviewQueue.next(
            suggestions: graph.editor.suggestions(in: modelContext),
            unsure: graph.unsureLinks(in: modelContext),
            skipped: skipped
        )
        if case .whichOne(let unsure) = question {
            let entryID = unsure.mention.entryID
            var descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == entryID })
            descriptor.fetchLimit = 1
            questionDate = (try? modelContext.fetch(descriptor))?.first?.entryDate
        } else {
            questionDate = nil
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

// One question at a time from the review queue, answered with one tap.
private struct ReviewCard: View {
    let question: ReviewQueue.Question
    let entryDate: Date?
    let names: [UUID: String]
    let answer: (ReviewQueue.Question, GraphServices.ReviewAnswer) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch question {
            case .same(let a, let b):
                Text("Are **\(names[a] ?? "these")** and **\(names[b] ?? "these")** the same?")
                HStack {
                    Button("Same") { answer(question, .same) }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("reviewSame-\(a)")
                    Button("Not the same") { answer(question, .notSame) }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("reviewNotSame-\(a)")
                    Spacer()
                    skip
                }
            case .whichOne(let unsure):
                if let entryDate {
                    Text("\u{201C}\(unsure.mention.surface)\u{201D} in your entry from \(entryDate.formatted(date: .abbreviated, time: .omitted)): which one?")
                } else {
                    Text("Which one did you mean by \u{201C}\(unsure.mention.surface)\u{201D}?")
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(unsure.candidates) { candidate in
                            Button(candidate.name) { answer(question, .whichOne(candidate.id)) }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("whichOneCandidate-\(candidate.name)")
                        }
                        skip
                    }
                }
            }
        }
        .font(.subheadline)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mindReviewCard")
    }

    private var skip: some View {
        Button("Skip") { answer(question, .skip) }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("reviewSkip")
    }
}
