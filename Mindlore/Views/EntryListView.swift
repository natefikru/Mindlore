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
    @State private var showingSettings = false
    @State private var pageOrder: PageOrderTarget?
    @State private var insightsEntry: Entry?
    @State private var pickedArea: LifeArea?
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
                if !offeredAreas.isEmpty {
                    areaFilterRow
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                ForEach(shownEntries) { entry in
                    // Pages still being gathered reopen the page screen, not the editor.
                    if entry.isAwaitingPageConfirmation {
                        Button {
                            pageOrder = .existing(entry)
                        } label: {
                            EntryRow(entry: entry, isAnalyzing: isAnalyzing(entry))
                        }
                        .foregroundStyle(.primary)
                    } else {
                        NavigationLink(value: JournalRoute(entryID: entry.id)) {
                            EntryRow(entry: entry, isAnalyzing: isAnalyzing(entry))
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
                .onDelete(perform: delete)
            }
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No entries yet",
                        systemImage: "book.closed",
                        description: Text("Tap Record to speak an entry, or the pencil to write one.")
                    )
                } else if shownEntries.isEmpty, let area = activeArea {
                    ContentUnavailableView {
                        Label("Nothing in \(settings.name(of: area))", systemImage: area.symbol)
                    } actions: {
                        Button("Show all entries") { pickedArea = nil }
                    }
                }
            }
            .navigationTitle("Mindlore")
            .navigationDestination(for: JournalRoute.self) { route in
                JournalEntryDestination(route: route)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") { showingSettings = true }
                }
                // Recording lives in the tab bar's accessory, reachable from every tab.
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if DocumentCameraView.isSupported || FakePages.isEnabled {
                        Button("Photograph Pages", systemImage: "camera") { pageOrder = .new }
                            .accessibilityIdentifier("newPhotoEntryButton")
                    }
                    newTypedEntryButton
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(item: $insightsEntry) { entry in
                EntryInsightsView(entry: entry)
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
                if JournalFilter.active(pickedArea, hidden: settings.hiddenLifeAreas) == nil { pickedArea = nil }
            }
            .onChange(of: router.dismissPresentationsToken) {
                showingSettings = false
                insightsEntry = nil
            }
        }
    }

    private var newTypedEntryButton: some View {
        Button("New Written Entry", systemImage: "square.and.pencil") { router.journalPath.append(.new()) }
            .accessibilityIdentifier("newEntryButton")
    }

    private var activeArea: LifeArea? {
        JournalFilter.active(pickedArea, hidden: settings.hiddenLifeAreas)
    }

    private var shownEntries: [Entry] {
        guard let area = activeArea else { return entries }
        return entries.filter { JournalFilter.matches(areasRaw: $0.insights?.areasRaw ?? [], area: area) }
    }

    private var offeredAreas: [LifeArea] {
        JournalFilter.offered(entryAreas: entries.map { $0.insights?.areasRaw ?? [] }, hidden: settings.hiddenLifeAreas)
    }

    private var areaFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(offeredAreas, id: \.self) { area in
                    let selected = activeArea == area
                    Button {
                        pickedArea = selected ? nil : area
                    } label: {
                        Label {
                            Text(settings.name(of: area))
                        } icon: {
                            Image(systemName: area.symbol)
                                .foregroundStyle(selected ? Color.white : area.color)
                        }
                            .font(.subheadline)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .background(selected ? area.color : Color(.secondarySystemFill), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("areaFilter-\(area.rawValue)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    // AI work the user should be able to see from the list, without opening the entry.
    private func isAnalyzing(_ entry: Entry) -> Bool {
        insightsCoordinator.isRunning(entry) || entry.insightsPending || entry.titlePending
    }

    private func delete(at offsets: IndexSet) {
        let shown = shownEntries
        for index in offsets {
            DiagnosticsLog.shared.record("entry.deleted", ["id": .id(shown[index].id), "reason": "swipe"])
            Entry.delete(shown[index], in: modelContext)
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
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        // One branch for new and existing routes: JournalRoute compares by id alone, so SwiftUI may
        // hand this view either form of the same route, and the editor's identity must not flip.
        let entry = EditorLifecycle.entry(route.entryID, in: modelContext)
        if route.isNew || entry != nil {
            EntryEditorView(
                entry: entry,
                newEntryID: route.entryID,
                opensForReading: EntryReadMode.opensForReading(entry, routeWantsTyping: route.opensForTyping, automationStartedAt: settings.automationStartedAt)
            )
        } else {
            ContentUnavailableView("This entry was deleted", systemImage: "trash")
        }
    }
}

private struct EntryRow: View {
    let entry: Entry
    var isAnalyzing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if entry.source == .voice {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Voice entry")
                } else if entry.source == .photo {
                    Image(systemName: "doc.text.image")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Journal pages")
                }
                EntryDateText(entry: entry)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("analyzingBadge")
                } else if let insights = entry.insights {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(insights.isCurrent(for: entry) ? Color.secondary : Color.orange)
                        .accessibilityLabel(insights.isCurrent(for: entry) ? "Has insights" : "Insights out of date")
                }
            }
            EntryAddedText(entry: entry)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(entry.text.isEmpty && entry.title.isEmpty ? "No text yet" : entry.displayTitle)
                .font(.headline)
                .lineLimit(1)
                .foregroundStyle(entry.text.isEmpty && entry.title.isEmpty ? .secondary : .primary)
            // The preview is skipped when it would just repeat the headline.
            if let preview, preview != entry.displayTitle {
                Text(preview)
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
            }
            if let areas = entry.insights?.areas, !areas.isEmpty {
                LifeAreaChips(areas: areas)
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
        .environment(ProviderAccountStore(settings: SettingsStore(store: UserDefaults(suiteName: "preview")!)))
        .environment(PageTranscriptionCoordinator(resolve: { .failure(AIJobFailure(raw: "settings.aiOff")) }))
        .environment(AIPassTrigger(settings: SettingsStore(store: UserDefaults(suiteName: "preview")!), presence: EditorPresence(), titleUsable: { false }))
        .environment(SettingsStore(store: UserDefaults(suiteName: "preview")!))
}
