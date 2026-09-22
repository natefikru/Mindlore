import SwiftData
import SwiftUI

// A scroll of weeks and months, newest first: the last `recentWeekCount` weeks in full, then
// every month before that back to the journal's first entry, collapsed. Presented as a sheet from
// Today's week strip, its own NavigationStack, no change to AppRouter or the tab bar. Not scoped
// to whatever week the caller tapped from: this is one feed, always the same shape.
struct ReflectView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @State private var earliestEntryDate: Date?
    @State private var months: [ReflectFeed.MonthRow] = []
    @State private var hasLoaded = false

    var recentWeekCount = ReflectFeed.defaultRecentWeekCount

    var body: some View {
        NavigationStack {
            Group {
                if hasLoaded {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(recentWeeks) { week in
                                ReflectWeekSection(week: week, onTapItem: openEntry)
                                Divider().padding(.leading, 16)
                            }
                            ForEach(months) { month in
                                ReflectMonthRow(month: month, onTapItem: openEntry)
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                    .paperBackground()
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Reflect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
            .accessibilityIdentifier("reflectView")
        }
    }

    private var recentWeeks: [ReflectFeed.WeekRow] {
        ReflectFeed.recentWeeks(recentWeekCount: recentWeekCount, now: .now)
    }

    // Loaded once per appearance: the journal's first entry date decides how far back the feed
    // reaches, and the month list is filtered here (not per-row) so a zero-entry month never
    // renders even for a frame.
    private func load() async {
        guard let earliest = ReflectSource.earliestEntryDate(in: modelContext) else {
            hasLoaded = true
            return
        }
        earliestEntryDate = earliest
        guard let oldestRecentWeekStart = recentWeeks.last?.interval.start else {
            hasLoaded = true
            return
        }
        let candidates = ReflectFeed.months(beforeWeekStart: oldestRecentWeekStart, earliestEntryDate: earliest)
        months = candidates.filter { ReflectSource.hasEntries(in: $0.interval, context: modelContext) }
        hasLoaded = true
    }

    private func openEntry(_ item: ReflectQueueItem) {
        dismiss()
        router.showNewEntry(startingText: item.prompt)
    }
}

#Preview {
    let container = try! ModelContainerFactory.make(.inMemory)
    let settings = SettingsStore(store: UserDefaults(suiteName: "preview")!)
    let graph = GraphServices()
    return ReflectView()
        .modelContainer(container)
        .environment(settings)
        .environment(EntrySaver(context: container.mainContext))
        .environment(graph)
        .environment(ProviderAccountStore(settings: settings))
        .environment(AppRouter(opened: { _ in }, closed: { _ in }))
}
