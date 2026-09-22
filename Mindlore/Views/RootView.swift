import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var saver: EntrySaver
    @State private var ingestor: RecordingIngestor
    @State private var recording: RecordingSession
    @State private var transcription: TranscriptionCoordinator
    @State private var presence: EditorPresence
    @State private var aiPass: AIPassTrigger
    @State private var titles: TitleCoordinator
    @State private var pageTranscription: PageTranscriptionCoordinator
    @State private var insights: InsightsCoordinator
    @State private var network = NetworkMonitor()
    @State private var indexing: GraphIndexingProgress?
    @State private var graph: GraphServices
    private let contacts: any ContactDirectory = CNContactDirectory()
    private let places: any PlaceDirectory = MKPlaceDirectory()
    @State private var ask: AskService
    @State private var router: AppRouter
    // Siri, Shortcuts, and the Action button leave their requests here, even before this view exists.
    @State private var intents = IntentRequests.shared
    @State private var reminder = DailyReminder()
    @Environment(SettingsStore.self) private var settings
    @Environment(ProviderAccountStore.self) private var accounts
    @State private var confirmingDiscard = false
    private let context: ModelContext

    init(container: ModelContainer, settings: SettingsStore, accounts: ProviderAccountStore) {
        let context = container.mainContext
        self.context = context
        let saver = EntrySaver(context: context)
        _saver = State(initialValue: saver)
        let http = accounts.http
        let presence = EditorPresence()
        let router = TranscriberRouter(settings: settings, accounts: accounts, http: http, onDevice: SpeechAnalyzerTranscriber())
        let transcription = TranscriptionCoordinator(route: router.route(for:manualRetry:))
        let aiPass = AIPassTrigger(
            settings: settings,
            presence: presence,
            titleUsable: { AIServices.titleGenerator(settings: settings, accounts: accounts, http: http).isSuccess },
            insightsUsable: { AIServices.automaticInsightsUsable(settings: settings, accounts: accounts) }
        )
        let titles = TitleCoordinator(resolve: { AIServices.titleGenerator(settings: settings, accounts: accounts, http: http) }, presence: presence)

        let graph = GraphServices(
            resolveText: { AIServices.textGenerator(settings: settings, accounts: accounts) },
            automaticBiosUsable: { AIServices.automaticInsightsUsable(settings: settings, accounts: accounts) },
            promptVoice: { settings.promptVoice }
        )
        _graph = State(initialValue: graph)
        let insights = InsightsCoordinator(
            resolve: { AIServices.insightsGenerator(settings: settings, accounts: accounts) },
            sections: { AIServices.insightSections(settings) },
            promptVoice: { settings.promptVoice },
            autoApplyCleanedText: { settings.autoApplyCleanedText },
            autoApplyEntryDate: { settings.autoApplySuggestedEntryDate },
            presence: presence,
            // Indexing rides along in the coordinator's own save, which already knows not to
            // stamp the entry for insights it didn't ask for.
            onInsightsWritten: { entry, context in
                graph.insightsWritten(for: entry, in: context)
            },
            vocabulary: { graph.indexer.vocabulary(in: $0, sections: $1) }
        )

        // A short delay lets a cancelled back swipe re-open the entry before any job looks at it.
        aiPass.onFlagged = {
            Task {
                try? await Task.sleep(for: .seconds(1))
                await titles.processQueue(context: context)
                await insights.processQueue(context: context)
            }
        }
        transcription.onTextReady = { id in
            guard let entry = context.model(for: id) as? Entry, !presence.isOpen(entry.id) else { return }
            if aiPass.fire(for: entry, at: .textReady) {
                try? context.saveStampingEntries()
                aiPass.onFlagged?()
            }
        }

        let pageTranscription = PageTranscriptionCoordinator(
            resolve: { AIServices.pageTranscriber(settings: settings, accounts: accounts) },
            suggestEntryDates: { settings.suggestEntryDates },
            autoApplyEntryDate: { settings.autoApplySuggestedEntryDate }
        )

        let lifecycle = EditorLifecycle(
            context: context,
            saver: saver,
            presence: presence,
            aiPass: aiPass,
            keepAudio: { settings.keepAudioAfterTranscription }
        )
        let appRouter = AppRouter(opened: lifecycle.opened, closed: lifecycle.closed)
        _router = State(initialValue: appRouter)
        // The index is rebuilt when any of the three counters moves: the saver for the editor's own
        // writes, the graph for insights and entity edits, and JournalSaves for every other save
        // path, which is what catches a recording's transcribed text.
        _ask = State(initialValue: AskService(
            resolve: { AIServices.askGenerator(settings: settings, accounts: accounts) },
            revisions: { .init(saver: saver.revision, graph: graph.revision, stamped: JournalSaves.revision) },
            store: AskStore(flush: { saver.flush() })
        ))
        let ingestor = RecordingIngestor()
        _ingestor = State(initialValue: ingestor)
        let fakeRecorder = UITestingRecorder.isEnabled
        _recording = State(initialValue: RecordingSession(
            context: context,
            ingestor: ingestor,
            makeRecorder: { fakeRecorder ? UITestingRecorder() as any AudioRecording : AudioRecorder() },
            makeLiveSession: { SpeechAnalyzerLiveSession(locale: $0) },
            speechEngine: { settings.speechEngine },
            afterIngest: { await transcription.processQueue(context: context) },
            // A recording ends in the Keep card, not the editor. Nothing opens, so nothing closes to
            // start the entry's automatic pass: the card's arrival is that moment.
            onFinished: { entry in
                aiPass.recordingKept(entry, in: context)
                appRouter.showKeep(entry.id)
            },
            takePrompt: {
                let text = RecordingSession.takePrompt(in: context)
                if text != nil { saver.noteChange() }
                return text
            }
        ))

        _presence = State(initialValue: presence)
        _pageTranscription = State(initialValue: pageTranscription)
        _transcription = State(initialValue: transcription)
        _aiPass = State(initialValue: aiPass)
        _titles = State(initialValue: titles)
        _insights = State(initialValue: insights)
    }

    var body: some View {
        TabView(selection: $router.tab) {
            Tab("Journal", systemImage: "book", value: AppTab.journal) {
                EntryListView()
            }
            Tab("Mind", systemImage: "circle.hexagongrid", value: AppTab.mind) {
                MindView()
            }
            Tab("Ask", systemImage: "bubble.left.and.text.bubble.right", value: AppTab.ask) {
                AskView()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        // The accessory and the recorder are handed the session directly rather than relying on
        // the environment below reaching their separate hosting.
        // Only while a recording runs, so it follows the user across tabs. Record itself sits in
        // Journal's toolbar.
        .tabViewBottomAccessory(isEnabled: recording.status != .idle) {
            RecordAccessory(session: recording) { confirmingDiscard = true }
        }
        .fullScreenCover(isPresented: Binding(get: { recording.isExpanded }, set: { if !$0 { recording.close() } })) {
            RecordingView()
                .environment(recording)
        }
        .confirmationDialog("Discard this recording?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard Recording", role: .destructive) { recording.discard() }
                .accessibilityIdentifier("confirmDiscardRecordingButton")
        }
        .environment(saver)
        .environment(transcription)
        .environment(presence)
        .environment(aiPass)
        .environment(titles)
        .environment(pageTranscription)
        .environment(insights)
        .environment(graph)
        .environment(ask)
        .environment(router)
        .environment(recording)
        .environment(reminder)
        // The address book, injected like every other boundary: nothing asks for permission
        // until the user taps a row on a person's page.
        .environment(\.contactDirectory, contacts)
        .environment(\.placeDirectory, places)
        .overlay {
            if let kept = router.keptEntryID {
                KeepCard(entryID: kept)
                    .id(kept)
                    .environment(graph)
                    .environment(insights)
                    .environment(router)
            }
        }
        .overlay {
            if let indexing {
                GraphIndexingOverlay(progress: indexing)
            }
        }
        .task {
            await ingestor.ingestAll(in: .standard, context: context)
            await transcription.processQueue(context: context)
        }
        .task {
            await pageTranscription.processQueue(context: context)
        }
        // Titles and insights run in their own lane so a long transcription doesn't hold them up.
        .task {
            if aiPass.sweep(context: context) > 0 {
                try? context.saveStampingEntries()
            }
            // Before the AI queues, so the first request already carries the names the
            // journal knows. On the first launch after the graph shipped this is the backfill,
            // which a large journal is shown progress for rather than a frozen screen.
            await graph.indexer.sweep(in: context) { done, total in
                indexing = GraphIndexingProgress.visible(done: done, total: total)
            }
            withAnimation { indexing = nil }
            graph.sweepFinished()
            if LooseEnd.fade(in: context) > 0 {
                try? context.saveStampingEntries()
            }
            // Non-blocking: the most recent week and month either already have a cached summary
            // (an instant return) or are worth one request each, neither of which titles and
            // insights below should wait on.
            Task {
                await ReflectSummaryStore.sweepMostRecentlyCompleted(
                    resolve: { AIServices.askGenerator(settings: settings, accounts: accounts) },
                    voice: settings.promptVoice,
                    in: context
                )
            }
            await titles.processQueue(context: context)
            await insights.processQueue(context: context)
        }
        .onChange(of: scenePhase) { _, phase in
            DiagnosticsLog.shared.record("app.scenePhase", ["phase": .string(String(describing: phase))])
            if phase != .active {
                saver.flush()
                // Leaving is the moment that matters: if the user wrote today, today's reminder goes.
                if phase == .background {
                    Task { await rescheduleReminder() }
                }
            } else {
                Task { await transcription.processQueue(context: context) }
                Task {
                    await titles.processQueue(context: context)
                    await insights.processQueue(context: context)
                }
                Task { await pageTranscription.processQueue(context: context) }
                // Coming back is when a permission change made in the Settings app shows up, and it
                // rolls the week forward.
                Task { await rescheduleReminder() }
            }
        }
        // At launch and whenever the switch or the time changes.
        .task(id: ReminderSetting(enabled: settings.reminderEnabled, minutes: settings.reminderMinutes)) {
            await rescheduleReminder()
        }
        // Taken on appear as well as on change: an intent that launched the app left its request
        // before this view was built.
        .onChange(of: intents.token, initial: true) {
            guard let action = intents.take() else { return }
            IntentHandler.handle(action, recording: recording, router: router)
        }
        .onChange(of: network.isConnected) { _, connected in
            guard connected else { return }
            Task { await transcription.networkBecameAvailable(context: context) }
            Task { await pageTranscription.networkBecameAvailable(context: context) }
            Task {
                await titles.networkBecameAvailable(context: context)
                await insights.networkBecameAvailable(context: context)
            }
        }
    }

    private struct ReminderSetting: Equatable {
        let enabled: Bool
        let minutes: Int
    }

    // A reminder iOS won't show is switched off rather than left looking on. Settings says why.
    private func rescheduleReminder() async {
        let outcome = await reminder.reschedule(
            enabled: settings.reminderEnabled,
            minutesAfterMidnight: settings.reminderMinutes,
            todayHasEntry: DailyReminder.todayHasEntry(in: context)
        )
        if outcome == .notAllowed {
            settings.reminderEnabled = false
        }
    }
}
