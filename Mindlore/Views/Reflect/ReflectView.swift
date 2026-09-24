import SwiftData
import SwiftUI

// The Reflect tab (owner, 2026-09-24): a segmented control over its sides. Life (`LifeView`) is
// what keeps happening and how it has felt; it is the side Reflect opens on once it has enough
// journal to read, and Recaps until then. Recaps is a scroll of
// weeks and months, newest first: the last `recentWeekCount` weeks in full, then every month before
// that back to the journal's first entry, collapsed. Loose ends (`ReflectLooseEndsView`) is every
// loose end the journal has raised, open ones pinned on top. Today's week strip jumps here on
// Recaps through `AppRouter.showReflect`.
struct ReflectView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Environment(SettingsStore.self) private var settings
    @Environment(ProviderAccountStore.self) private var accounts
    @State private var earliestEntryDate: Date?
    @State private var recentWeeks: [ReflectFeed.WeekRow] = []
    @State private var months: [ReflectFeed.MonthRow] = []
    @State private var hasLoaded = false
    // Rows that loaded and found no summary, by period start. When every row is in here, the feed
    // says there is nothing to look back on rather than showing a blank sheet.
    @State private var emptyRows: Set<Date> = []
    @State private var page: ReflectPage = .recaps
    // Decided once, at the first load: Life when it has a reading, else Recaps. A jump that names a
    // side wins over it.
    @State private var pageDecided = false
    @State private var lifeWindow: MindWindow = .quarter
    @State private var path: [LifeAreaRoute] = []

    var recentWeekCount = ReflectFeed.defaultRecentWeekCount

    private var pages: [ReflectPage] { ReflectPage.allCases }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch page {
                case .life:
                    LifeView(window: $lifeWindow, openArea: { path.append($0) }, showLooseEnds: { page = .looseEnds })
                case .recaps: summaries
                case .looseEnds: ReflectLooseEndsView()
                }
            }
            .navigationDestination(for: LifeAreaRoute.self) { LifeAreaView(route: $0) }
            .navigationTitle("Reflect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Reflect", selection: $page) {
                        ForEach(pages) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .accessibilityIdentifier("reflectPagePicker")
                }
            }
            // On the stack, not on the summaries: switching to Loose ends and back must not
            // reload the feed.
            .task { await load() }
            .onChange(of: router.reflectPageRequest, initial: true) {
                if let requested = router.consumeReflectPage() {
                    page = requested
                    pageDecided = true
                    path = []
                }
            }
            .sensoryFeedback(Haptics.selected, trigger: page)
        }
    }

    private var summaries: some View {
        Group {
            if hasLoaded, allRowsEmpty {
                ContentUnavailableView(
                    "Nothing to look back on yet",
                    systemImage: "calendar",
                    description: Text("A week shows up here once there's something to sum up.")
                )
                .paperBackground()
                .accessibilityIdentifier("reflectEmpty")
            } else if hasLoaded {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(recentWeeks) { week in
                            ReflectWeekSection(week: week, onTapItem: openEntry) { markEmpty(week.id, $0) }
                        }
                        ForEach(months) { month in
                            ReflectMonthRow(month: month, onTapItem: openEntry) { markEmpty(month.id, $0) }
                        }
                    }
                }
                .paperBackground()
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityIdentifier("reflectView")
    }

    // Loaded once per appearance: the journal's first entry date decides how far back the feed
    // reaches, and weeks and months are filtered here (not per-row) so a period with no entries
    // never renders, not even for a frame. A row with nothing in it is clutter, not a finding.
    private func load() async {
        // The same check AskView runs on its own open (Checked on every open, so adding a key
        // moves questions without a trip to Settings): otherwise a key saved just now sits unused
        // until the user happens to visit Ask first, and Reflect looked broken for no reason a
        // relaunch could fix either, since nothing here depended on app state.
        settings.refreshAskGeneratorDefault(
            textUsable: AIServices.textUsable(settings: settings, accounts: accounts),
            onDeviceAvailable: FoundationModelsAvailability.isAvailable
        )
        if !pageDecided {
            pageDecided = true
            page = LifeSignals.progress(LifeSource.facts(in: modelContext).entries).isEnough ? .life : .recaps
        }
        guard let earliest = ReflectSource.earliestEntryDate(in: modelContext) else {
            hasLoaded = true
            return
        }
        earliestEntryDate = earliest
        let weeks = ReflectFeed.recentWeeks(recentWeekCount: recentWeekCount, now: .now)
        recentWeeks = weeks.filter { ReflectSource.hasEntries(in: $0.interval, context: modelContext) }
        // The cut-off comes from the unfiltered weeks, or an empty recent week would pull its days
        // into a month row as well.
        guard let oldestRecentWeekStart = weeks.last?.interval.start else {
            hasLoaded = true
            return
        }
        let candidates = ReflectFeed.months(beforeWeekStart: oldestRecentWeekStart, earliestEntryDate: earliest)
        months = candidates.filter { ReflectSource.hasEntries(in: $0.interval, context: modelContext) }
        hasLoaded = true
    }

    private var allRowsEmpty: Bool {
        let ids = Set(recentWeeks.map(\.id) + months.map(\.id))
        return ids.isSubset(of: emptyRows)
    }

    private func markEmpty(_ id: Date, _ empty: Bool) {
        if empty { emptyRows.insert(id) } else { emptyRows.remove(id) }
    }

    // The recap's question, as a hint in a new entry; closing it comes back here.
    private func openEntry(_ item: ReflectQueueItem) {
        router.showNewEntry(startingText: item.prompt, returningTo: .reflect)
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
