import SwiftUI

// Holds Ask's place until A7 builds it.
struct AskPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Ask your journal",
                systemImage: "bubble.left.and.text.bubble.right",
                description: Text("Questions about what you've written will go here.")
            )
            .navigationTitle("Ask")
        }
    }
}
