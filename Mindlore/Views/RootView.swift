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
    @State private var network = NetworkMonitor()
    private let context: ModelContext

    init(container: ModelContainer, settings: SettingsStore, accounts: ProviderAccountStore) {
        let context = container.mainContext
        self.context = context
        _saver = State(initialValue: EntrySaver(context: context))
        let http = URLSessionHTTPClient()
        let presence = EditorPresence()
        let router = TranscriberRouter(settings: settings, accounts: accounts, http: http, onDevice: SpeechAnalyzerTranscriber())
        let transcription = TranscriptionCoordinator(route: router.route(for:manualRetry:))
        let aiPass = AIPassTrigger(settings: settings, presence: presence, titleUsable: { AIServices.titleGenerator(settings: settings, accounts: accounts, http: http).isSuccess })
        let titles = TitleCoordinator(resolve: { AIServices.titleGenerator(settings: settings, accounts: accounts, http: http) }, presence: presence)

        // A short delay lets a cancelled back swipe re-open the entry before any job looks at it.
        aiPass.onFlagged = {
            Task {
                try? await Task.sleep(for: .seconds(1))
                await titles.processQueue(context: context)
            }
        }
        transcription.onTextReady = { id in
            guard let entry = context.model(for: id) as? Entry, !presence.isOpen(entry.id) else { return }
            if aiPass.fire(for: entry, at: .textReady) {
                try? context.saveStampingEntries()
                aiPass.onFlagged?()
            }
        }

        _presence = State(initialValue: presence)
        _transcription = State(initialValue: transcription)
        _aiPass = State(initialValue: aiPass)
        _titles = State(initialValue: titles)
    }

    var body: some View {
        EntryListView()
            .environment(saver)
            .environment(ingestor)
            .environment(transcription)
            .environment(presence)
            .environment(aiPass)
            .environment(titles)
            .task {
                await ingestor.ingestAll(in: .standard, context: context)
                await transcription.processQueue(context: context)
            }
            // Titles and insights run in their own lane so a long transcription doesn't hold them up.
            .task {
                if aiPass.sweep(context: context) > 0 {
                    try? context.saveStampingEntries()
                }
                await titles.processQueue(context: context)
            }
            .onChange(of: scenePhase) { _, phase in
                DiagnosticsLog.shared.record("app.scenePhase", ["phase": .string(String(describing: phase))])
                if phase != .active {
                    saver.flush()
                } else {
                    Task { await transcription.processQueue(context: context) }
                    Task { await titles.processQueue(context: context) }
                }
            }
            .onChange(of: network.isConnected) { _, connected in
                guard connected else { return }
                Task { await transcription.networkBecameAvailable(context: context) }
            }
    }
}
