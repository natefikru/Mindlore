import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var saver: EntrySaver

    init(container: ModelContainer) {
        _saver = State(initialValue: EntrySaver(context: container.mainContext))
    }

    var body: some View {
        EntryListView()
            .environment(saver)
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    saver.flush()
                }
            }
    }
}
