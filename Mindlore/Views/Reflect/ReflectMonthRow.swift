import SwiftUI
import SwiftData

// A month collapsed to one row: a title, a mood-chip strip, and a short generated line, not a
// chart. Tapping expands it into its constituent weeks, full density, same as the recent stretch.
// No collapsing back: everything here is a scroll of two densities, not a set of toggled panels.
//
// A plain VStack, not a List Section, for the same reason ReflectWeekSection dropped Section: a
// row whose height jumps once its own generation request lands must never be torn down and
// recreated by a reused-row container mid-request.
struct ReflectMonthRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let month: ReflectFeed.MonthRow
    let onTapItem: (ReflectQueueItem) -> Void
    var onEmpty: (Bool) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settings
    @Environment(EntrySaver.self) private var saver
    @Environment(GraphServices.self) private var graph
    @Environment(ProviderAccountStore.self) private var accounts
    @State private var moodCounts: [MoodCategory: Int] = [:]
    @State private var line: String?
    @State private var hasLoaded = false
    @State private var isExpanded = false

    // Same rule as a week: no summary line, no row.
    private var isEmpty: Bool { hasLoaded && (line ?? "").isEmpty }

    var body: some View {
        Group {
            if isExpanded {
                ForEach(ReflectFeed.weeks(in: month.interval).filter { ReflectSource.hasEntries(in: $0.interval, context: modelContext) }) { week in
                    ReflectWeekSection(week: week, onTapItem: onTapItem)
                }
            } else if isEmpty {
                Color.clear.frame(height: 0)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    collapsed
                    Divider().padding(.leading, 16)
                }
            }
        }
        .task(id: fingerprint) { await load() }
        .onChange(of: isEmpty, initial: true) { _, empty in onEmpty(empty) }
    }

    private var collapsed: some View {
            Button {
                withAnimation(Motion.resolve(.default, reduceMotion: reduceMotion)) { isExpanded = true }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(ReflectFidelity.title(kind: .month, interval: month.interval))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ReflectMoodChipStrip(moodCounts: moodCounts)
                    // No line limit: the generated line is a short paragraph on purpose (two to
                    // four sentences), and cutting it at two lines with no way to see the rest
                    // hid most of it.
                    if let line, !line.isEmpty {
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .accessibilityIdentifier("reflectMonth-\(month.interval.start.timeIntervalSince1970)")
    }

    private struct Fingerprint: Equatable {
        let start: Date
        let saver: Int
        let graph: Int
        let stamped: Int
    }

    private var fingerprint: Fingerprint {
        Fingerprint(start: month.interval.start, saver: saver.revision, graph: graph.revision, stamped: JournalSaves.revision)
    }

    private func load() async {
        moodCounts = ReflectSource.period(month.interval, in: modelContext).moodCounts
        let summary = await ReflectSummaryStore.generateIfNeeded(
            kind: .month,
            interval: month.interval,
            resolve: { AIServices.askGenerator(settings: settings, accounts: accounts) },
            voice: settings.promptVoice,
            in: modelContext
        )
        line = summary?.items.first?.body
        hasLoaded = true
    }
}
