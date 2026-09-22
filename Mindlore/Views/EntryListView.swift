import SwiftUI
import SwiftData

struct EntryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(EntrySaver.self) private var saver
    @Environment(GraphServices.self) private var graph
    @Environment(SettingsStore.self) private var settings
    // Backdated entries share noon of their day, so createdAt keeps their order stable.
    @Query(sort: [SortDescriptor(\Entry.entryDate, order: .reverse), SortDescriptor(\Entry.createdAt, order: .reverse)])
    private var entries: [Entry]
    @Environment(AppRouter.self) private var router
    @State private var pageOrder: PageOrderTarget?
    @State private var insightsEntry: Entry?
    @State private var pickedAreas: Set<LifeArea> = []
    @State private var today = Today()
    @State private var showingReflect = false
    @Environment(RecordingSession.self) private var recording
    @Environment(InsightsCoordinator.self) private var insightsCoordinator

    enum PageOrderTarget: Identifiable {
        case new
        case existing(Entry)

        var id: String {
            switch self {
            case .new: "new"
            case .existing(let entry): entry.id.uuidString
            }
        }
    }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.journalPath) {
            List {
                if !today.isEmpty {
                    TodayHeader(today: today, dismiss: dismissTodayCard, mute: muteFromToday, openReflect: { showingReflect = true })
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                if !offeredAreas.isEmpty {
                    areaFilterRow
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                ForEach(groupedEntries, id: \.group) { section in
                    Section(JournalGroups.title(section.group)) {
                        ForEach(section.entries) { entry in
                            row(entry, in: section.group)
                                .listRowBackground(rowCard)
                                .listRowSeparator(.hidden)
                        }
                        // A section's swipe gives an offset into that section, not the flat list.
                        .onDelete { offsets in delete(offsets, in: section.entries) }
                    }
                }
            }
            .paperBackground()
            // The three monotonic counters AskIndexStore keys off, plus the day. Never a count:
            // an add and a delete return one to where it was, and the header would miss the change.
            .task(id: todayFingerprint) { refreshToday() }
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No entries yet",
                        systemImage: "book.closed",
                        description: Text("Tap the microphone to speak an entry, or the pencil to write one.")
                    )
                } else if shownEntries.isEmpty, !activeAreas.isEmpty {
                    ContentUnavailableView {
                        Label(
                            JournalFilter.emptyStateTitle(orderedActiveAreas.map { settings.name(of: $0) }),
                            systemImage: orderedActiveAreas.first?.symbol ?? "line.3.horizontal.decrease"
                        )
                    } actions: {
                        Button("Show all entries") { pickedAreas = [] }
                    }
                }
            }
            .navigationTitle("Mindlore")
            .navigationDestination(for: JournalRoute.self) { route in
                JournalEntryDestination(route: route)
            }
            .toolbar {
                // Voice sits outermost, in the easiest-to-reach position. A running recording shows in
                // the tab bar's accessory.
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if DocumentCameraView.isSupported || FakePages.isEnabled {
                        Button("Photograph Pages", systemImage: "camera") { pageOrder = .new }
                            .accessibilityIdentifier("newPhotoEntryButton")
                    }
                    newTypedEntryButton
                    Button("New Voice Entry", systemImage: "mic") { recording.begin() }
                        .disabled(recording.status != .idle)
                        .accessibilityIdentifier("newVoiceEntryButton")
                }
            }
            .sheet(item: $insightsEntry) { entry in
                EntryInsightsView(entry: entry)
            }
            .sheet(isPresented: $showingReflect) {
                ReflectView()
            }
            .fullScreenCover(item: $pageOrder) { target in
                switch target {
                case .new:
                    PageOrderView(entry: nil) { entry in router.showEntry(entry.id) }
                case .existing(let entry):
                    PageOrderView(entry: entry) { entry in router.showEntry(entry.id) }
                }
            }
            .onChange(of: pageOrder != nil) { _, open in
                router.setCover("pageOrder", open: open)
            }
            .onChange(of: settings.hiddenLifeAreas) {
                pickedAreas = JournalFilter.active(pickedAreas, hidden: settings.hiddenLifeAreas)
            }
            .onChange(of: router.dismissPresentationsToken) {
                insightsEntry = nil
                showingReflect = false
            }
        }
    }

    @ViewBuilder
    private func row(_ entry: Entry, in group: JournalGroup) -> some View {
        // Pages still being gathered reopen the page screen, not the editor.
        if entry.isAwaitingPageConfirmation {
            Button {
                pageOrder = .existing(entry)
            } label: {
                EntryRow(entry: entry, isAnalyzing: isAnalyzing(entry), group: group)
            }
            .foregroundStyle(.primary)
        } else {
            NavigationLink(value: JournalRoute(
                entryID: entry.id,
                opensForReading: EntryReadMode.opensForReading(entry, automationStartedAt: settings.automationStartedAt)
            )) {
                EntryRow(entry: entry, isAnalyzing: isAnalyzing(entry), group: group)
            }
            .contextMenu {
                Button("Insights", systemImage: "sparkles") { insightsEntry = entry }
                if InsightsCoordinator.canRunAI(on: entry) {
                    Button("Run AI", systemImage: "arrow.clockwise") {
                        Task { await insightsCoordinator.runAI(for: entry, context: modelContext) }
                    }
                }
            }
        }
    }

    private struct TodayFingerprint: Equatable {
        let saver: Int
        let graph: Int
        let stamped: Int
        let day: String
        let resurfacing: Bool
        let name: String
    }

    // The three counters, the day, and the two settings the composer reads. Without the settings
    // in here, turning resurfacing off in the sheet leaves the card it forbids on the screen until
    // something unrelated saves.
    private var todayFingerprint: TodayFingerprint {
        TodayFingerprint(
            saver: saver.revision, graph: graph.revision,
            stamped: JournalSaves.revision, day: TodayDismissal.stamp(.now),
            resurfacing: settings.resurfacingEnabled, name: settings.userName
        )
    }

    private func refreshToday() {
        let started = Date.now
        today = TodaySource.today(in: modelContext, settings: settings)
        DiagnosticsLog.shared.record(
            "today.shown",
            TodayCopy.shownFields(today, milliseconds: Date.now.timeIntervalSince(started) * 1000)
        )
    }

    private func dismissTodayCard(_ card: TodayCard) {
        let rank = today.cards.firstIndex(of: card) ?? 0
        settings.dismissTodayCard(card.id, on: TodayDismissal.stamp(.now))
        DiagnosticsLog.shared.record("today.dismissed", TodayCopy.dismissedFields(card, rank: rank))
        refreshToday()
    }

    // No refresh here: the edit bumps graph.revision, which is already in the fingerprint, and
    // refreshing as well would fetch twice and log two today.shown events for one tap. A dismissal
    // is the other way round, because a settings write moves no counter.
    private func muteFromToday(_ who: EntityFacts) {
        graph.setResurfacingMuted(true, on: who.id, in: modelContext)
    }

    // One card per row over Paper. The card is the row's background rather than a wrapper around its
    // content, so the row stays a cell and the swipe-to-delete offsets are untouched.
    private var rowCard: some View {
        RoundedRectangle(cornerRadius: Corner.card, style: .continuous)
            .fill(Palette.card)
            .overlay(
                RoundedRectangle(cornerRadius: Corner.card, style: .continuous)
                    .strokeBorder(Palette.hairline)
            )
            .padding(.vertical, 3)
    }

    private var newTypedEntryButton: some View {
        Button("New Written Entry", systemImage: "square.and.pencil") { router.journalPath.append(.new()) }
            .accessibilityIdentifier("newEntryButton")
    }

    private var activeAreas: Set<LifeArea> {
        JournalFilter.active(pickedAreas, hidden: settings.hiddenLifeAreas)
    }

    // In the fixed case order, so the empty state reads the same way twice.
    private var orderedActiveAreas: [LifeArea] {
        LifeArea.allCases.filter { activeAreas.contains($0) }
    }

    private var shownEntries: [Entry] {
        let areas = activeAreas
        guard !areas.isEmpty else { return entries }
        return entries.filter { JournalFilter.matches(areasRaw: $0.insights?.areasRaw ?? [], areas: areas) }
    }

    // The query is already newest first, so the groups come out in order with no re-sorting.
    private var groupedEntries: [(group: JournalGroup, entries: [Entry])] {
        let shown = shownEntries
        let byID = Dictionary(shown.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let dated = shown.map { JournalGroups.Dated(id: $0.id, date: $0.entryDate) }
        return JournalGroups.build(dated, now: .now).map { section in
            (section.group, section.ids.compactMap { byID[$0] })
        }
    }

    private var offeredAreas: [LifeArea] {
        JournalFilter.offered(entryAreas: entries.map { $0.insights?.areasRaw ?? [] }, hidden: settings.hiddenLifeAreas)
    }

    private var areaFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(offeredAreas, id: \.self) { area in
                    let selected = activeAreas.contains(area)
                    Button {
                        if selected { pickedAreas.remove(area) } else { pickedAreas.insert(area) }
                    } label: {
                        Label(settings.name(of: area), systemImage: area.symbol)
                            .lineLimit(1)
                            .chip(tint: area.color, selected: selected)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("areaFilter-\(area.rawValue)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .sensoryFeedback(Haptics.selected, trigger: pickedAreas)
    }

    // AI work the user should be able to see from the list, without opening the entry.
    private func isAnalyzing(_ entry: Entry) -> Bool {
        insightsCoordinator.isRunning(entry) || entry.insightsPending || entry.titlePending
    }

    private func delete(_ offsets: IndexSet, in sectionEntries: [Entry]) {
        let byID = Dictionary(sectionEntries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ids = JournalGroups.ids(at: offsets, in: sectionEntries.map(\.id))
        for entry in ids.compactMap({ byID[$0] }) {
            DiagnosticsLog.shared.record("entry.deleted", ["id": .id(entry.id), "reason": "swipe"])
            Entry.delete(entry, in: modelContext)
        }
        // Flush first so the cascade is real, then recount over what is left: the entry took
        // its links with it, and anything nobody mentions any more goes too.
        saver.flush()
        graph.entriesDeleted(in: modelContext)
        saver.flush()
    }
}

// Resolves a route to its entry each time it's shown, so a deleted entry never reaches the editor.
private struct JournalEntryDestination: View {
    let route: JournalRoute
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        // One branch for new and existing routes: JournalRoute compares by id alone, so SwiftUI may
        // hand this view either form of the same route, and the editor's identity must not flip.
        let entry = EditorLifecycle.entry(route.entryID, in: modelContext)
        if route.isNew || entry != nil {
            EntryEditorView(
                entry: entry,
                newEntryID: route.entryID,
                opensForReading: route.opensForReading && entry != nil,
                startingText: route.startingText
            )
        } else {
            ContentUnavailableView("This entry was deleted", systemImage: "trash")
        }
    }
}

private struct EntryRow: View {
    let entry: Entry
    var isAnalyzing = false
    // The section header already says roughly when this was, so the row's date says only what
    // the header leaves out.
    var group: JournalGroup?

    var body: some View {
        // Two lines, down from five: the title with its badges, then everything else in one
        // secondary line.
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if entry.source == .voice {
                    Image(systemName: "mic.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Voice entry")
                } else if entry.source == .photo {
                    Image(systemName: "doc.text.image")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Journal pages")
                }
                Text(entry.text.isEmpty && entry.title.isEmpty ? "No text yet" : entry.displayTitle)
                    .font(.system(.headline, design: .serif))
                    .lineLimit(1)
                    .foregroundStyle(entry.text.isEmpty && entry.title.isEmpty ? .secondary : .primary)
                Spacer(minLength: 4)
                if let status = statusBadge {
                    Text(status)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                if isAnalyzing {
                    Label {
                        Text("Analyzing")
                    } icon: {
                        ProgressView().controlSize(.mini)
                    }
                    .font(.caption)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("analyzingBadge")
                }
            }
            HStack(spacing: 6) {
                // Dots rather than a chip row: the areas are worth a glance, not a line.
                if let areas = entry.insights?.areas, !areas.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(areas.prefix(2), id: \.self) { area in
                            Circle()
                                .fill(area.color)
                                .frame(width: 6, height: 6)
                                .accessibilityLabel(area.defaultName)
                        }
                    }
                }
                let date = EntryDateText.rowText(entry.entryDate, dayOnly: entry.entryDateIsDayOnly, group: group)
                if !date.isEmpty {
                    Text(date)
                }
                if let preview, preview != entry.displayTitle {
                    Text(preview)
                        .lineLimit(1)
                }
                if entry.entryDateDiffersFromCreation() {
                    EntryAddedText(entry: entry)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("entryRow")
    }

    private var statusBadge: String? {
        if entry.isAwaitingPageConfirmation { return "Pages not confirmed" }
        if entry.isDraft { return "Draft" }
        guard entry.awaitingText else { return nil }
        return entry.source == .photo ? "Transcribing pages" : "Getting text"
    }

    private var preview: String? {
        let lines = entry.text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let first = lines.first else { return nil }
        // Without a title the first line is already the headline, so preview what follows it.
        if entry.title.isEmpty {
            return lines.count > 1 && first.count <= Entry.derivedTitleLength ? lines[1] : (first.count > Entry.derivedTitleLength ? first : nil)
        }
        return first
    }
}

#Preview {
    let container = try! ModelContainerFactory.make(.inMemory)
    container.mainContext.insert(Entry(text: "Walked to the river this morning.\nThe light was strange."))
    container.mainContext.insert(Entry(source: .voice, awaitingText: true, audioData: Data([0])))
    return EntryListView()
        .modelContainer(container)
        .environment(EntrySaver(context: container.mainContext))
        .environment(GraphServices())
        .environment(TranscriptionCoordinator())
        .environment(EditorPresence())
        .environment(AppRouter(opened: { _ in }, closed: { _ in }))
        .environment(RecordingSession(
            context: container.mainContext,
            ingestor: RecordingIngestor(),
            makeRecorder: { AudioRecorder() },
            makeLiveSession: { SpeechAnalyzerLiveSession(locale: $0) },
            speechEngine: { .onDevice },
            afterIngest: {},
            onFinished: { _ in }
        ))
        .environment(ProviderAccountStore(settings: SettingsStore(store: UserDefaults(suiteName: "preview")!)))
        .environment(PageTranscriptionCoordinator(resolve: { .failure(AIJobFailure(raw: "settings.aiOff")) }))
        .environment(AIPassTrigger(settings: SettingsStore(store: UserDefaults(suiteName: "preview")!), presence: EditorPresence(), titleUsable: { false }))
        .environment(SettingsStore(store: UserDefaults(suiteName: "preview")!))
}
