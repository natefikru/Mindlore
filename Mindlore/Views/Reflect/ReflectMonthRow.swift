import SwiftUI
import SwiftData

// A month collapsed to one row: a title, a mood-chip strip, and a short generated line, not a
// chart. Tapping expands it into its constituent weeks, full density, same as the recent stretch.
// No collapsing back: everything here is a scroll of two densities, not a set of toggled panels.
struct ReflectMonthRow: View {
    let month: ReflectFeed.MonthRow
    let onTapItem: (ReflectQueueItem) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settings
    @Environment(EntrySaver.self) private var saver
    @Environment(GraphServices.self) private var graph
    @Environment(ProviderAccountStore.self) private var accounts
    @State private var moodCounts: [MoodCategory: Int] = [:]
    @State private var line: String?
    @State private var hasLoaded = false
    @State private var isExpanded = false

    var body: some View {
        if isExpanded {
            ForEach(ReflectFeed.weeks(in: month.interval)) { week in
                ReflectWeekSection(week: week, onTapItem: onTapItem)
            }
        } else {
            Section {
                Button {
                    withAnimation { isExpanded = true }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(ReflectFidelity.title(kind: .month, interval: month.interval))
                                .font(.system(.subheadline, design: .serif).weight(.medium))
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ReflectMoodChipStrip(moodCounts: moodCounts)
                        if let line, !line.isEmpty {
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            .task(id: fingerprint) { await load() }
            .accessibilityIdentifier("reflectMonth-\(month.interval.start.timeIntervalSince1970)")
        }
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
        let summary = await ReflectSummaryStore.generateIfMissing(
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
