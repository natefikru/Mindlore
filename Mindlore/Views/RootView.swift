import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var saver: EntrySaver
    @State private var ingestor = RecordingIngestor()
    @State private var transcription: TranscriptionCoordinator
    @State private var presence: EditorPresence
    @State private var aiPass: AIPassTrigger
    @State private var titles: TitleCoordinator
    @State private var pageTranscription: PageTranscriptionCoordinator
    @State private var insights: InsightsCoordinator
    @State private var network = NetworkMonitor()
    @State private var indexing: GraphIndexingProgress?
    @State private var graph: GraphServices
    @State private var router: AppRouter
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
            automaticBiosUsable: { AIServices.automaticInsightsUsable(settings: settings, accounts: accounts) }
        )
        _graph = State(initialValue: graph)
        let insights = InsightsCoordinator(
            resolve: { AIServices.insightsGenerator(settings: settings, accounts: accounts) },
            sections: { AIServices.insightSections(settings) },
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
        _router = State(initialValue: AppRouter(opened: lifecycle.opened, closed: lifecycle.closed))

        _presence = State(initialValue: presence)
        _pageTranscription = State(initialValue: pageTranscription)
        _transcription = State(initialValue: transcription)
        _aiPass = State(initialValue: aiPass)
        _titles = State(initialValue: titles)
        _insights = State(initialValue: insights)
    }

    var body: some View {
        EntryListView()
            .environment(saver)
            .environment(ingestor)
            .environment(transcription)
            .environment(presence)
            .environment(aiPass)
            .environment(titles)
            .environment(pageTranscription)
            .environment(insights)
            .environment(graph)
            .environment(router)
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
                await titles.processQueue(context: context)
                await insights.processQueue(context: context)
            }
            .onChange(of: scenePhase) { _, phase in
                DiagnosticsLog.shared.record("app.scenePhase", ["phase": .string(String(describing: phase))])
                if phase != .active {
                    saver.flush()
                } else {
                    Task { await transcription.processQueue(context: context) }
                    Task {
                        await titles.processQueue(context: context)
                        await insights.processQueue(context: context)
                    }
                    Task { await pageTranscription.processQueue(context: context) }
                }
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
}
