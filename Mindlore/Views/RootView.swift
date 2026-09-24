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
    @State private var lock: AppLock
    @Environment(SettingsStore.self) private var settings
    @Environment(JournalRecovery.self) private var recovery
    @Environment(SyncStatusMonitor.self) private var sync
    @Environment(ProviderAccountStore.self) private var accounts
    @State private var confirmingDiscard = false
    @State private var showingWelcome = false
    // The welcome screen's Add a key.
    @State private var showingAISettings = false
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
            automaticBiosUsable: { AIServices.automaticBiosUsable(settings: settings, accounts: accounts) },
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
        let appRouter = AppRouter(opened: lifecycle.opened, closed: lifecycle.closed, closedForDeletion: lifecycle.closedForDeletion)
        _router = State(initialValue: appRouter)
        // The index is rebuilt when any of the three counters moves: the saver for the editor's own
        // writes, the graph for insights and entity edits, and JournalSaves for every other save
        // path, which is what catches a recording's transcribed text.
        let ask = AskService(
            resolve: { AIServices.askGenerator(settings: settings, accounts: accounts) },
            revisions: { .init(saver: saver.revision, graph: graph.revision, stamped: JournalSaves.revision) },
            store: AskStore(flush: { saver.flush() })
        )
        // A note Chat made is finished the moment it exists, so it gets its automatic pass then.
        ask.onNoteCreated = { note in
            guard aiPass.fire(for: note, at: .chatNote) else { return }
            try? context.saveStampingEntries()
            aiPass.onFlagged?()
        }
        _ask = State(initialValue: ask)
        let ingestor = RecordingIngestor()
        _ingestor = State(initialValue: ingestor)
        let fakeRecorder = UITestingRecorder.isEnabled
        _recording = State(initialValue: RecordingSession(
            context: context,
            ingestor: ingestor,
            makeRecorder: { fakeRecorder ? UITestingRecorder() as any AudioRecording : AudioRecorder() },
            makeLiveSession: { SpeechAnalyzerLiveSession(locale: $0) },
            speechEngine: { settings.speechEngine },
            recordOnOpen: { settings.recordOnOpen },
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
            },
            // The fake recorder under UI tests needs neither, and a system prompt would block them.
            askPermissions: { if !fakeRecorder { await RecordingPermissions.askIfNeeded(speechEngine: settings.speechEngine) } }
        ))

        _lock = State(initialValue: AppLock(isEnabled: { settings.appLockEnabled }))
        _presence = State(initialValue: presence)
        _pageTranscription = State(initialValue: pageTranscription)
        _transcription = State(initialValue: transcription)
        _aiPass = State(initialValue: aiPass)
        _titles = State(initialValue: titles)
        _insights = State(initialValue: insights)
    }

    var body: some View {
        // The + never becomes the selected tab: picking it opens the fan (`AppRouter.select`).
        TabView(selection: Binding(get: { router.tab }, set: { router.select($0) })) {
            Tab("Journal", systemImage: "book", value: AppTab.journal) {
                EntryListView()
            }
            Tab("Mind", systemImage: "circle.hexagongrid", value: AppTab.mind) {
                MindView()
            }
            // Drawn over by NewEntryFan's own +; this tab is its slot and its VoiceOver button.
            Tab("New", systemImage: "plus", value: AppTab.newEntry) {
                Color.clear
            }
            Tab("Reflect", systemImage: "leaf", value: AppTab.reflect) {
                ReflectView()
            }
            Tab("Chat", systemImage: "bubble.left.and.bubble.right", value: AppTab.ask) {
                AskView()
            }
        }
        .overlay {
            NewEntryFan()
                .environment(router)
                .environment(recording)
        }
        // The accessory and the recorder are handed the session directly rather than relying on
        // the environment below reaching their separate hosting.
        // Only while a recording runs, so it follows the user across tabs. Record itself is in the
        // tab bar's + fan.
        .tabViewBottomAccessory(isEnabled: recording.showsAccessory) {
            RecordAccessory(session: recording) { confirmingDiscard = true }
        }
        .fullScreenCover(isPresented: Binding(get: { recording.isExpanded }, set: { if !$0 { recording.close() } })) {
            RecordingView()
                .environment(recording)
        }
        // Recording starts from the accessory, the recorder, empty states, and Siri, so the tap back
        // lives here, on the session every one of them drives.
        .sensoryFeedback(trigger: recording.status) { old, new in
            switch new {
            case .active where old != .active: Haptics.recordStart
            case .permissionDenied, .startFailed: Haptics.failed
            default: nil
            }
        }
        .sensoryFeedback(Haptics.recordStop, trigger: recording.isFinishing) { _, finishing in finishing }
        .sheet(isPresented: $showingAISettings) {
            AISettingsSheet()
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
        .environment(lock)
        // The address book, injected like every other boundary: nothing asks for permission
        // until the user taps a row on a person's page.
        .environment(\.contactDirectory, contacts)
        .environment(\.placeDirectory, places)
        .environment(\.journalFont, settings.journalFont)
        .overlay {
            if let kept = router.keptEntryID {
                KeepCard(entryID: kept)
                    .id(kept)
                    .environment(\.journalFont, settings.journalFont)
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
            refreshThisWeek()
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
            // "loose ends" as a tag, from before parsing refused it (owner, 2026-09-24).
            if BlockedTagSweep.run(in: context) > 0 {
                graph.indexer.recount(in: context)
                try? context.saveStampingEntries()
                graph.sweepFinished()
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
            refreshThisWeek()
        }
        .overlay {
            if showingWelcome {
                WelcomeView(
                    onStart: { closeWelcome() },
                    onAddKey: {
                        closeWelcome()
                        showingAISettings = true
                    }
                )
                .transition(.opacity)
            }
        }
        // Whether to offer the safety copy back: at launch, and each time sync settles.
        .task(id: sync.status.diagnosticName) {
            recovery.check(in: context, status: sync.status)
        }
        .onAppear {
            lock.lockAtLaunch()
            showingWelcome = Self.showsWelcome(seen: settings.welcomeSeen, arguments: ProcessInfo.processInfo.arguments, entries: (try? context.fetchCount(FetchDescriptor<Entry>())) ?? 0)
            // A journal that already has entries never needs it, so it's marked seen rather than
            // asked about again on every launch.
            if !showingWelcome { settings.welcomeSeen = true }
        }
        // Every edit, a recording's text arriving, and a title landing move the running week, so its
        // summary is rewritten in the background once things go quiet.
        .onChange(of: saver.revision) { refreshThisWeek() }
        .onChange(of: scenePhase) { _, phase in
            DiagnosticsLog.shared.record("app.scenePhase", ["phase": .string(String(describing: phase))])
            lock.sceneChanged(to: phase)
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
    private func refreshThisWeek() {
        ReflectSummaryStore.scheduleCurrentWeekRefresh(
            resolve: { AIServices.askGenerator(settings: settings, accounts: accounts) },
            voice: { settings.promptVoice },
            isEditing: { presence.anyOpen },
            in: context
        )
    }

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

extension RootView {
    // Only a new install sees the welcome: not a journal with entries in it, and never a UI test
    // unless it asks with -showWelcome.
    static func showsWelcome(seen: Bool, arguments: [String], entries: Int) -> Bool {
        if arguments.contains("-showWelcome") { return true }
        return !seen && entries == 0 && !arguments.contains(StoreLocation.uiTestingArgument)
    }

    fileprivate func closeWelcome() {
        settings.welcomeSeen = true
        withAnimation(Motion.resolve(Motion.settle, reduceMotion: false)) { showingWelcome = false }
    }
}
