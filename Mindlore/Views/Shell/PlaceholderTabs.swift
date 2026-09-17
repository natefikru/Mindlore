import SwiftUI

// Holds Mind's place until A5 builds it. Connections stays reachable from here until then.
struct MindPlaceholderView: View {
    @Environment(AppRouter.self) private var router
    @State private var showingConnections = false

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Mind", systemImage: "circle.hexagongrid")
            } description: {
                Text("The people, places, and threads in your journal will live here.")
            } actions: {
                Button("Connections", systemImage: "person.2") { showingConnections = true }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("connectionsButton")
            }
            .navigationTitle("Mind")
        }
        .sheet(isPresented: $showingConnections) {
            ConnectionsView()
        }
        .onChange(of: router.dismissPresentationsToken) {
            showingConnections = false
        }
    }
}

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
