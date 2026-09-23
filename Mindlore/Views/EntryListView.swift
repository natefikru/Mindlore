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
    // Notes and creative pieces each get a chip of their own, apart from the areas: picking one
    // clears the areas, and picking an area clears it. Journal is what the list is, so it has none.
    @State private var shownKind: EntryKind?
    @State private var today = Today()
    @State private var showingReflect = false
    // Set right before a Reflect card jumps to a new entry, so leaving that entry (back or Done)
    // returns to Reflect instead of dumping the user on the Journal list they never asked for.
    @State private var returnToReflectAfterEntry = false
    @Environment(RecordingSession.self) private var recording
    @Environment(InsightsCoordinator.self) private var insightsCoordinator
    @State private var undo = UndoQueue()

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
                    TodayHeader(
                        today: today,
                        dismiss: dismissTodayCard,
                        mute: muteFromToday,
                        act: actOnThread,
                        openEntry: { router.showEntry($0, forReading: true) },
                        openReflect: { showingReflect = true }
                    )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                if !offeredAreas.isEmpty || !offeredKinds.isEmpty {
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
            .undoPill(undo)
            .overlay {
                if visibleEntries.isEmpty {
                    // The toolbar's glyphs carry no words, so the empty state names what they do
                    // and offers the two that start an entry.
                    ContentUnavailableView {
                        Label("No entries yet", systemImage: "book.closed")
                    } description: {
                        Text("Speak an entry, write one, or photograph pages from a paper journal.")
                    } actions: {
                        Button("Record", systemImage: "mic") { recording.begin() }
                            .buttonStyle(.borderedProminent)
                            .disabled(recording.status != .idle)
                            .accessibilityIdentifier("journalEmptyRecord")
                        Button("Write", systemImage: "square.and.pencil") { router.journalPath.append(.new()) }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("journalEmptyWrite")
                    }
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
                ReflectView(onOpenEntry: { prompt in
                    returnToReflectAfterEntry = true
                    router.showNewEntry(startingText: prompt)
                })
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
            // Deleted from the editor's menu: the editor has already left the path, and the
            // delete waits here behind the same Undo a swipe gets.
            .onChange(of: router.entryDeletionRequest, initial: true) {
                guard let id = router.consumeEntryDeletion() else { return }
                scheduleDelete([id], reason: "editor")
            }
            // The entry a Reflect card opened has closed (back or Done): return to Reflect rather
            // than leaving the user on the plain Journal list.
            .onChange(of: router.journalPath) { _, path in
                guard path.isEmpty, returnToReflectAfterEntry else { return }
                returnToReflectAfterEntry = false
                showingReflect = true
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

    // Done and Let it go are the same two choices the insights sheet offers, made from the row.
    // Both stop the thread for good; Done also counts it as closed. Writing about it opens a new
    // entry with the thread as the prompt and changes nothing until the user writes.
    private func actOnThread(_ action: TodayThreadAction, _ end: LooseEndFacts) {
        switch action {
        case .writeAbout:
            router.showNewEntry(startingText: end.text)
        case .done, .letGo:
            guard let looseEnd = LooseEnd.fetch(end.id, in: modelContext) else { return }
            saver.flush()
            looseEnd.setByUser(action == .done ? .resolved : .dismissed)
            try? modelContext.saveStampingEntries()
            // Refreshed here, not left to the fingerprint: JournalSaves.revision is a plain static
            // that SwiftUI doesn't observe, so the save alone left the card on the row until
            // something else happened to redraw the list.
            DiagnosticsLog.shared.record("today.thread", ["action": .string(String(describing: action))])
            refreshToday()
            return
        }
        DiagnosticsLog.shared.record("today.thread", ["action": .string(String(describing: action))])
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

    // Everything but an entry whose delete is still waiting on its Undo.
    private var visibleEntries: [Entry] {
        let hidden = undo.hiddenIDs
        return hidden.isEmpty ? entries : entries.filter { !hidden.contains($0.id) }
    }

    // The kinds worth a chip: the ones some entry is, journal aside.
    private var offeredKinds: [EntryKind] {
        let present = Set(entries.map(\.kind))
        return [EntryKind.note, .creative].filter { present.contains($0) }
    }

    // A kind chip that went away (its last entry changed kind or was deleted) stops filtering,
    // or the list would sit empty with nothing left to unpick.
    private var activeKind: EntryKind? {
        shownKind.flatMap { offeredKinds.contains($0) ? $0 : nil }
    }

    private var shownEntries: [Entry] {
        if let activeKind { return visibleEntries.filter { $0.kind == activeKind } }
        let areas = activeAreas
        guard !areas.isEmpty else { return visibleEntries }
        return visibleEntries.filter { JournalFilter.matches(areasRaw: $0.insights?.areasRaw ?? [], areas: areas) }
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
                        shownKind = nil
                    } label: {
                        Label(settings.name(of: area), systemImage: area.symbol)
                            .lineLimit(1)
                            .chip(tint: area.color, selected: selected)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("areaFilter-\(area.rawValue)")
                }
                ForEach(offeredKinds, id: \.self) { kind in
                    let selected = activeKind == kind
                    Button {
                        shownKind = selected ? nil : kind
                        pickedAreas = []
                    } label: {
                        Label(kind == .note ? "Notes" : kind.name, systemImage: kind.symbol)
                            .lineLimit(1)
                            .chip(tint: kind.color, selected: selected)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier(kind == .creative ? "creativeFilter" : "kindFilter-\(kind.rawValue)")
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

    // The row goes at once and the delete waits for Undo's window. An entry takes its insights,
    // links, and loose ends with it, which is a lot for one stray swipe.
    private func delete(_ offsets: IndexSet, in sectionEntries: [Entry]) {
        scheduleDelete(JournalGroups.ids(at: offsets, in: sectionEntries.map(\.id)), reason: "swipe")
    }

    private func scheduleDelete(_ ids: [UUID], reason: String) {
        guard !ids.isEmpty else { return }
        let context = modelContext
        let saver = saver
        let graph = graph
        undo.schedule(Set(ids), message: ids.count == 1 ? "Entry deleted" : "\(ids.count) entries deleted") {
            let doomed = (try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { ids.contains($0.id) }))) ?? []
            for entry in doomed {
                DiagnosticsLog.shared.record("entry.deleted", ["id": .id(entry.id), "reason": .string(reason)])
                Entry.delete(entry, in: context)
            }
            // Flush first so the cascade is real, then recount over what is left: the entry took
            // its links with it, and anything nobody mentions any more goes too.
            saver.flush()
            graph.entriesDeleted(in: context)
            saver.flush()
        }
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
        // Three lines: the title with its badges, one secondary line of what the header leaves
        // out, then two lines of the entry's own words. The date the entry was added is not one
        // of them: once its day has been changed, the day it belongs to is the only date that
        // matters, and it is already in the header and the line below (owner, 2026-09-23).
        VStack(alignment: .leading, spacing: 3) {
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
                    .journalText(.headline)
                    .lineLimit(1)
                    .foregroundStyle(entry.text.isEmpty && entry.title.isEmpty ? .secondary : .primary)
                Spacer(minLength: 4)
                EntryKindBadge(kind: entry.kind)
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
            let date = EntryDateText.rowText(entry.entryDate, dayOnly: entry.entryDateIsDayOnly, group: group)
            let areas = entry.insights?.areas ?? []
            if !date.isEmpty || !areas.isEmpty {
                HStack(spacing: 6) {
                    // Dots rather than a chip row: the areas are worth a glance, not a line.
                    if !areas.isEmpty {
                        HStack(spacing: 3) {
                            ForEach(areas.prefix(2), id: \.self) { area in
                                Circle()
                                    .fill(area.color)
                                    .frame(width: 6, height: 6)
                                    .accessibilityLabel(area.defaultName)
                            }
                        }
                    }
                    if !date.isEmpty {
                        Text(date)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if let preview = entry.previewText {
                Text(preview)
                    .journalText(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .accessibilityIdentifier("entryPreview")
            }
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
