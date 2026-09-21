import SwiftData
import SwiftUI

#if DEBUG
// The area distribution over a real journal, and the button that re-analyzes every entry. A
// tuning instrument, not a setting: it lived under Life areas because that is what it measures,
// which put a paid, journal-wide AI run one tap from renaming a chip. It sits at the root of
// Settings now, under its own Debug heading, and it has never shipped (this whole file is DEBUG).
struct LifeAreaDebugSection: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(InsightsCoordinator.self) private var insights
    @State private var shares: [(area: LifeArea, percent: Int)] = []
    @State private var filed = 0
    @State private var regenerating = false

    var body: some View {
        Section {
            ForEach(shares, id: \.area) { share in
                LabeledContent(share.area.defaultName, value: "\(share.percent)%")
            }
            Button(regenerating ? "Regenerating…" : "Regenerate insights for every entry") {
                regenerating = true
                Task {
                    await insights.regenerateEverything(context: modelContext)
                    regenerating = false
                    refresh()
                }
            }
            .disabled(regenerating)
        } header: {
            Text("Debug: distribution")
        } footer: {
            Text("Share of \(filed) filed entries per area. Above 40% suggests splitting an area, below 3% merging it. Regenerating sends every entry to the AI provider, oldest first.")
        }
        .task { refresh() }
    }

    private func refresh() {
        let all = (try? modelContext.fetch(FetchDescriptor<EntryInsights>())) ?? []
        let filedInsights = all.filter { !$0.areas.isEmpty }
        filed = filedInsights.count
        shares = LifeAreaDistribution.shares(filedInsights.map(\.areas))
    }
}
#endif
