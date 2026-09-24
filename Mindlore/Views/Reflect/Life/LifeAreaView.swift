import Charts
import SwiftData
import SwiftUI

// One life area over Life's window: how much of the writing it took and how that felt month by
// month against your usual, who is in it, what keeps coming up in it, what it has left open, how
// its loose ends close, and its latest entries.
struct LifeAreaView: View {
    let route: LifeAreaRoute

    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settings
    @Environment(EntrySaver.self) private var saver
    @Environment(GraphServices.self) private var graph
    @Environment(AppRouter.self) private var router
    @Environment(ProviderAccountStore.self) private var accounts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var detail: LifeSignals.AreaDetail?
    @State private var people: [LifeSource.Person] = []
    @State private var threads: [ReflectLooseEnds.Item] = []
    @State private var latest: [LifeSource.EntryRow] = []
    @State private var peek: PeekTarget?
    @State private var words: LifeWords.AreaWordsView?
    @State private var writingWords = false

    // The three monotonic counters, never a count.
    private struct RefreshKey: Equatable {
        let saver: Int
        let graph: Int
        let stamped: Int
    }

    private struct PeekTarget: Identifiable {
        let id: UUID
    }

    private var area: LifeArea { route.area }
    private var name: String { settings.name(of: area) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let detail {
                    wordsCard
                    feeling(detail)
                    if !people.isEmpty { peopleCard }
                    if !detail.tags.isEmpty { tagsCard(detail) }
                    if !threads.isEmpty { threadsCard }
                    if let follow = detail.followThrough {
                        LifeCard(title: "How its loose ends close", symbol: "checkmark.circle", tint: area.color) {
                            LifeFollowRow(follow: follow, name: name)
                        }
                    }
                    if !latest.isEmpty { latestCard }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .paperBackground()
        // The header carries the name; the bar stays empty rather than saying it twice.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: RefreshKey(saver: saver.revision, graph: graph.revision, stamped: JournalSaves.revision)) { load() }
        .sheet(item: $peek) { target in
            EntityPeekSheet(entityID: target.id)
        }
        .onAppear { LifeDiagnostics.areaOpened(area, window: route.window) }
        .accessibilityIdentifier("lifeAreaView")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: area.symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(area.color)
                .frame(width: 60, height: 60)
                .background(area.color.opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .journalText(.title, weight: .semibold)
                    .foregroundStyle(Palette.ink)
                if let reading = detail?.reading {
                    Text("\(LifeCopy.percent(reading.share)) of what you wrote \(LifeCopy.windowPhrase(route.window))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(LifeCopy.areaLine(reading, name: settings.name(of:)).capitalizedFirst)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Nothing here \(LifeCopy.windowPhrase(route.window))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func feeling(_ detail: LifeSignals.AreaDetail) -> some View {
        LifeCard(title: "How it has felt", symbol: "waveform.path.ecg", tint: area.color) {
            Chart {
                RuleMark(y: .value("Your usual", 0))
                    .foregroundStyle(Color.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 5]))
                ForEach(detail.months) { month in
                    if let height = month.height {
                        BarMark(
                            x: .value("Month", month.month, unit: .month),
                            y: .value("Against your usual", height)
                        )
                        .foregroundStyle(area.color.opacity(height >= 0 ? 0.85 : 0.45).gradient)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
            }
            .chartYScale(domain: -span(detail)...span(detail))
            .chartYAxis {
                AxisMarks(values: [-span(detail) * 0.8, 0, span(detail) * 0.8]) { value in
                    AxisValueLabel {
                        let v = value.as(Double.self) ?? 0
                        Text(v > 0.01 ? "Lighter" : (v < -0.01 ? "Heavier" : "Usual"))
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: route.window == .year ? 2 : 1)) { _ in
                    AxisValueLabel(format: .dateTime.month(route.window == .year ? .narrow : .abbreviated))
                }
            }
            .frame(height: 170)
            .accessibilityLabel("How \(name) has felt, month by month, against your usual")
            Text(countLine(detail))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // The chart's half-height: the largest month's distance from usual, with room, so a quiet
    // area's small moves still read as moves.
    private func span(_ detail: LifeSignals.AreaDetail) -> Double {
        let largest = detail.months.compactMap(\.height).map(abs).max() ?? 0
        return max(0.5, largest * 1.25)
    }

    private func countLine(_ detail: LifeSignals.AreaDetail) -> String {
        let withEntries = detail.months.filter { $0.entries > 0 }.count
        let total = detail.months.reduce(0) { $0 + $1.entries }
        return "\(total) \(total == 1 ? "entry" : "entries") across \(withEntries) \(withEntries == 1 ? "month" : "months"). A bar needs a mood that month."
    }

    private var peopleCard: some View {
        LifeCard(title: "Who's in it", symbol: "person.2", tint: area.color) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(people) { person in
                        Button {
                            peek = PeekTarget(id: person.id)
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(person.kind.color)
                                    .frame(width: 8, height: 8)
                                Text(person.name)
                                    .font(.subheadline.weight(.medium))
                                Text("\(person.entries)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(person.kind.color.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("lifePerson")
                    }
                }
            }
        }
    }

    private func tagsCard(_ detail: LifeSignals.AreaDetail) -> some View {
        LifeCard(title: "Comes up here", symbol: "number", tint: area.color) {
            LifeFlowLayout(spacing: 8) {
                ForEach(detail.tags, id: \.tag) { tag in
                    HStack(spacing: 4) {
                        Text(tag.tag)
                        Text("\(tag.count)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.1), in: Capsule())
                }
            }
        }
    }

    private var threadsCard: some View {
        LifeCard(title: "Still open here", symbol: "circle", tint: Palette.ember) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(threads) { item in
                    Button {
                        if let id = item.sourceEntryID { router.showEntry(id, forReading: true, returningTo: .reflect) }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: "circle")
                                .foregroundStyle(Palette.ember)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.text)
                                    .journalText(.body)
                                    .foregroundStyle(Palette.ink)
                                    .multilineTextAlignment(.leading)
                                Text(ReflectLooseEnds.detail(item))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var latestCard: some View {
        LifeCard(title: "Latest", symbol: "book", tint: area.color) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(latest.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().padding(.vertical, 10) }
                    Button {
                        router.showEntry(row.id, forReading: true, returningTo: .reflect)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(row.title.isEmpty ? "Untitled" : row.title)
                                    .journalText(.headline)
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                Spacer()
                                Text(row.date, format: .dateTime.day().month(.abbreviated))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if !row.preview.isEmpty {
                                Text(row.preview)
                                    .journalText(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("lifeLatestEntry")
                }
            }
        }
    }

    // The area's paragraph and two lines in the author's own words, when AI can read them. Hidden
    // entirely when it can't: the numbers stand on their own.
    @ViewBuilder
    private var wordsCard: some View {
        if let words {
            LifeCard(title: "What it's been about", symbol: "text.quote", tint: area.color) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(words.paragraph)
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(words.quotes.enumerated()), id: \.offset) { _, quote in
                        Button {
                            router.showEntry(quote.entryID, forReading: true, returningTo: .reflect)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(area.color)
                                    .frame(width: 3)
                                Text("“\(quote.text)”")
                                    .journalText(.body)
                                    .italic()
                                    .foregroundStyle(Palette.ink)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("lifeQuote")
                    }
                }
            }
            .transition(.opacity)
            .accessibilityIdentifier("lifeAreaWords")
        } else if writingWords {
            LifeCard(title: "What it's been about", symbol: "text.quote", tint: area.color) {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Reading this part of your journal…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func loadWords(_ ids: [UUID]) async {
        words = LifeWords.areaWords(area, route.window, in: modelContext)
        guard case .success = AIServices.askGenerator(settings: settings, accounts: accounts) else { return }
        if words == nil { writingWords = true }
        let written = await LifeWords.writeAreaIfNeeded(
            area,
            window: route.window,
            name: name,
            entryIDs: ids,
            resolve: { AIServices.askGenerator(settings: settings, accounts: accounts) },
            in: modelContext
        )
        withAnimation(Motion.resolve(Motion.settle, reduceMotion: reduceMotion)) {
            words = written ?? words
            writingWords = false
        }
    }

    private func load() {
        let facts = LifeSource.facts(in: modelContext)
        let next = LifeSignals.detail(for: area, entries: facts.entries, threads: facts.threads, window: route.window, now: .now)
        detail = next
        people = LifeSource.people(in: next?.entryIDs ?? [], context: modelContext)
        threads = LifeSource.openThreads(area: area, context: modelContext)
        latest = LifeSource.entryRows(next?.entryIDs ?? [], context: modelContext)
        let ids = next?.entryIDs ?? []
        Task { await loadWords(ids) }
    }
}

private extension String {
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}

// Chips that wrap onto as many lines as they need.
struct LifeFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
