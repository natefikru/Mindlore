import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var saver: EntrySaver
    @State private var ingestor = RecordingIngestor()
    private let context: ModelContext

    init(container: ModelContainer) {
        context = container.mainContext
        _saver = State(initialValue: EntrySaver(context: container.mainContext))
    }

    var body: some View {
        EntryListView()
            .environment(saver)
            .environment(ingestor)
            .task {
                await ingestor.ingestAll(in: .standard, context: context)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    saver.flush()
                }
            }
    }
}
