import SwiftUI
import SwiftData

// One week, full density: a header (title and mood chips) and its queue items underneath. The
// current week shows only its live reused signals, never a generated section, since nothing can
// honestly summarize a week that isn't over yet.
struct ReflectWeekSection: View {
    let week: ReflectFeed.WeekRow
    let onTapItem: (ReflectQueueItem) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settings
    @Environment(EntrySaver.self) private var saver
    @Environment(GraphServices.self) private var graph
    @Environment(ProviderAccountStore.self) private var accounts
    @State private var items: [ReflectQueueItem] = []
    @State private var dismissedIDs: Set<String> = []
    @State private var moodCounts: [MoodCategory: Int] = [:]
    @State private var hasLoaded = false

    private var periodKey: String { ReflectDismissal.periodKey(kind: .week, periodStart: week.interval.start) }
    private var visibleItems: [ReflectQueueItem] { items.filter { !dismissedIDs.contains($0.id) } }

    var body: some View {
        Section {
            if !hasLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if visibleItems.isEmpty {
                Text("All caught up.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("reflectAllCaughtUp")
            } else {
                ForEach(visibleItems) { item in
                    ReflectQueueRow(item: item, onTap: { onTapItem(item) }, onDismiss: { dismiss(item) })
                }
            }
        } header: {
            VStack(alignment: .leading, spacing: 4) {
                Text(ReflectFidelity.title(kind: .week, interval: week.interval))
                    .font(.system(.subheadline, design: .serif).weight(.medium))
                    .foregroundStyle(Palette.ink)
                ReflectMoodChipStrip(moodCounts: moodCounts)
            }
            .textCase(nil)
        }
        .task(id: fingerprint) { await load() }
        .accessibilityIdentifier("reflectWeek-\(week.isCurrent ? "current" : "\(week.interval.start.timeIntervalSince1970)")")
    }

    private struct Fingerprint: Equatable {
        let start: Date
        let saver: Int
        let graph: Int
        let stamped: Int
    }

    private var fingerprint: Fingerprint {
        Fingerprint(start: week.interval.start, saver: saver.revision, graph: graph.revision, stamped: JournalSaves.revision)
    }

    private func load() async {
        dismissedIDs = settings.dismissedReflectItems(for: periodKey)
        moodCounts = ReflectSource.period(week.interval, in: modelContext).moodCounts

        let referenceEnd = week.isCurrent ? Date.now : week.interval.end
        var loaded = ReflectSource.queueSignals(weekEnd: referenceEnd, in: modelContext)
        if !week.isCurrent {
            let summary = await ReflectSummaryStore.generateIfMissing(
                kind: .week,
                interval: week.interval,
                resolve: { AIServices.askGenerator(settings: settings, accounts: accounts) },
                voice: settings.promptVoice,
                in: modelContext
            )
            if let summary { loaded += summary.items }
        }
        items = loaded
        hasLoaded = true
    }

    private func dismiss(_ item: ReflectQueueItem) {
        settings.dismissReflectItem(item.id, for: periodKey)
        dismissedIDs.insert(item.id)
    }
}
