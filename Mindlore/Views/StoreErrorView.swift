import SwiftUI

struct StoreErrorView: View {
    let error: any Error

    var body: some View {
        ContentUnavailableView {
            Label("Mindlore couldn't open your journal", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Your entries have not been changed. Restart the app, and if this keeps happening, share the details below.")
            Text(String(describing: error))
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
    }
}

#Preview {
    StoreErrorView(error: CocoaError(.fileReadCorruptFile))
}
