import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var saver: EntrySaver
    @State private var ingestor = RecordingIngestor()
    @State private var transcription: TranscriptionCoordinator
    @State private var presence = EditorPresence()
    @State private var network = NetworkMonitor()
    private let context: ModelContext

    init(container: ModelContainer, settings: SettingsStore, accounts: ProviderAccountStore) {
        context = container.mainContext
        _saver = State(initialValue: EntrySaver(context: container.mainContext))
        let router = TranscriberRouter(settings: settings, accounts: accounts, http: URLSessionHTTPClient(), onDevice: SpeechAnalyzerTranscriber())
        _transcription = State(initialValue: TranscriptionCoordinator(route: router.route(for:manualRetry:)))
    }

    var body: some View {
        EntryListView()
            .environment(saver)
            .environment(ingestor)
            .environment(transcription)
            .environment(presence)
            .task {
                await ingestor.ingestAll(in: .standard, context: context)
                await transcription.processQueue(context: context)
            }
            .onChange(of: scenePhase) { _, phase in
                DiagnosticsLog.shared.record("app.scenePhase", ["phase": .string(String(describing: phase))])
                if phase != .active {
                    saver.flush()
                } else {
                    Task { await transcription.processQueue(context: context) }
                }
            }
            .onChange(of: network.isConnected) { _, connected in
                guard connected else { return }
                Task { await transcription.networkBecameAvailable(context: context) }
            }
    }
}
