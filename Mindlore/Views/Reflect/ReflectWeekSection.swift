import SwiftUI
import SwiftData

// One week, full density: a header (title and mood chips) and its queue items underneath. The
// current week shows only its live reused signals, never a generated section, since nothing can
// honestly summarize a week that isn't over yet.
//
// A plain VStack, not a List Section: List reuses and re-measures rows during its initial layout
// pass, and a row here starts as a small ProgressView and jumps to full height once its own
// generation request lands. That height change made List tear down and recreate several rows
// while it settled, cancelling their in-flight AI requests mid-request (AIError.cancelled) before
// they ever had a chance to finish. A LazyVStack inside a ScrollView creates a row once and keeps
// it, so its task is never torn down out from under it.
struct ReflectWeekSection: View {
    let week: ReflectFeed.WeekRow
    let onTapItem: (ReflectQueueItem) -> Void
    // Told when the section has settled on having nothing to show, so the feed knows when every
    // row has gone and it should say so instead.
    var onEmpty: (Bool) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settings
    @Environment(EntrySaver.self) private var saver
    @Environment(GraphServices.self) private var graph
    @Environment(ProviderAccountStore.self) private var accounts
    @State private var items: [ReflectQueueItem] = []
    @State private var dismissedIDs: Set<String> = []
    @State private var moodCounts: [MoodCategory: Int] = [:]
    @State private var hasLoaded = false
    // A rewrite running behind the summary already on screen.
    @State private var refreshing = false

    private var periodKey: String { ReflectDismissal.periodKey(kind: .week, periodStart: week.interval.start) }
    private var visibleItems: [ReflectQueueItem] { items.filter { !dismissedIDs.contains($0.id) } }

    // A week with no summary to show has no row at all: mood chips over nothing read as clutter
    // (owner, 2026-09-22). It stays in the feed as a zero-height view only so its load can run.
    private var isEmpty: Bool { hasLoaded && visibleItems.isEmpty }

    var body: some View {
        Group {
            if isEmpty {
                Color.clear.frame(height: 0)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    section
                    Divider().padding(.leading, 16)
                }
            }
        }
        .task(id: fingerprint) { await load() }
        .onChange(of: isEmpty, initial: true) { _, empty in onEmpty(empty) }
    }

    private var section: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(ReflectFidelity.title(kind: .week, interval: week.interval))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.ink)
                    // The running week's summary is rewritten as entries arrive, and final once
                    // the week is over.
                    if week.isCurrent {
                        Text("So far")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if refreshing {
                        ProgressView()
                            .controlSize(.mini)
                            .accessibilityLabel("Updating")
                    }
                }
                ReflectMoodChipStrip(moodCounts: moodCounts)
            }
            // Scoped to the header alone, not the whole section: applied to an ancestor of the
            // queue rows below, it silently overwrote their own identifiers (a row came back
            // identified as this week's own id, not "reflectQueueRow"), which is why no automated
            // test could ever find one.
            .accessibilityIdentifier("reflectWeek-\(week.isCurrent ? "current" : "\(week.interval.start.timeIntervalSince1970)")")

            if !hasLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(visibleItems) { item in
                        ReflectQueueRow(item: item, periodKey: periodKey, onTap: { onTapItem(item) }, onDismiss: { dismiss(item) })
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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

        // Whatever is cached shows at once, even while the week is being rewritten behind it: the
        // old summary with a small spinner beats a blank row with a big one (owner, 2026-09-24).
        // Usually there is nothing to wait for, since RootView rewrites the running week in the
        // background after its entries change.
        if let cached = ReflectSummaryStore.summary(kind: .week, periodStart: week.interval.start, in: modelContext) {
            items = cached.items
            hasLoaded = true
        }
        refreshing = hasLoaded
        defer { refreshing = false }
        // The running week too: its summary is rewritten whenever its entries have changed.
        let summary = await ReflectSummaryStore.generateIfNeeded(
            kind: .week,
            interval: week.interval,
            resolve: { AIServices.askGenerator(settings: settings, accounts: accounts) },
            voice: settings.promptVoice,
            in: modelContext
        )
        // A failed rewrite keeps what was on screen.
        if let summary { items = summary.items } else if !hasLoaded { items = [] }
        hasLoaded = true
    }

    private func dismiss(_ item: ReflectQueueItem) {
        settings.dismissReflectItem(item.id, for: periodKey)
        dismissedIDs.insert(item.id)
    }
}
