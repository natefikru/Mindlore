import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var saver: EntrySaver
    @State private var ingestor = RecordingIngestor()
    @State private var transcription = TranscriptionCoordinator()
    private let context: ModelContext

    init(container: ModelContainer) {
        context = container.mainContext
        _saver = State(initialValue: EntrySaver(context: container.mainContext))
    }

    var body: some View {
        EntryListView()
            .environment(saver)
            .environment(ingestor)
            .environment(transcription)
            .task {
                await ingestor.ingestAll(in: .standard, context: context)
                await transcription.processQueue(context: context)
            }
            .onChange(of: scenePhase) { _, phase in
                DiagnosticsLog.shared.record("app.scenePhase", ["phase": .string(String(describing: phase))])
                if phase != .active {
                    saver.flush()
                }
            }
    }
}
