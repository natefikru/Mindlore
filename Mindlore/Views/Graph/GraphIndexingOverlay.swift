import SwiftUI

// Where a large first index stands, if it is worth telling the user about at all.
struct GraphIndexingProgress: Equatable {
    // Below this the pass is over in well under a second, and a screen that flashes up and away
    // is worse than none.
    static let threshold = 200

    let done: Int
    let total: Int

    var fraction: Double { total == 0 ? 1 : Double(done) / Double(total) }

    static func visible(done: Int, total: Int) -> GraphIndexingProgress? {
        total >= threshold && done < total ? .init(done: done, total: total) : nil
    }
}

// Shown over the journal while an existing journal's entries are organized for the first time.
struct GraphIndexingOverlay: View {
    let progress: GraphIndexingProgress

    var body: some View {
        ZStack {
            // Opaque: the journal behind is not usable yet, and text over a list is unreadable.
            Color(.systemBackground)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text("Organizing your journal")
                    .font(.headline)
                ProgressView(value: progress.fraction)
                    .frame(maxWidth: 240)
                Text("\(progress.done) of \(progress.total) entries")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(32)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("graphIndexingOverlay")
        // Appears at once: a fade-in would stall half-drawn behind the first chunk of work.
        .transition(.asymmetric(insertion: .identity, removal: .opacity))
    }
}

#Preview {
    GraphIndexingOverlay(progress: .init(done: 1_200, total: 3_000))
}
