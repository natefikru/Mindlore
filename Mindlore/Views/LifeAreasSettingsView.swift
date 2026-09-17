import SwiftData
import SwiftUI

// Renaming and hiding the fixed life areas. The model and storage keep using the built-in names.
struct LifeAreasSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Form {
            Section {
                ForEach(LifeArea.allCases, id: \.self) { area in
                    LifeAreaRow(area: area)
                }
            } footer: {
                Text("Each entry is filed under one or two of these. Renaming changes what you see, and hiding an area removes it from the journal's chips and filters without changing any entry.")
            }
            #if DEBUG
            LifeAreaDebugSection()
            #endif
        }
        .navigationTitle("Life areas")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LifeAreaRow: View {
    @Environment(SettingsStore.self) private var settings
    let area: LifeArea
    @State private var name = ""

    var body: some View {
        HStack {
            Image(systemName: area.symbol)
                .foregroundStyle(area.color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                TextField(area.defaultName, text: $name)
                    .onChange(of: name) { settings.rename(area, to: name) }
                    .onSubmit { name = settings.lifeAreaNames[area.rawValue] ?? "" }
                    .accessibilityIdentifier("lifeAreaName-\(area.rawValue)")
                Text(area.meaning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Toggle("Show", isOn: Binding(
                get: { !settings.isHidden(area) },
                set: { settings.setHidden(area, !$0) }
            ))
            .labelsHidden()
            .accessibilityLabel("Show \(settings.name(of: area))")
            .accessibilityIdentifier("lifeAreaShown-\(area.rawValue)")
        }
        .onAppear { name = settings.lifeAreaNames[area.rawValue] ?? "" }
    }
}

#if DEBUG
private struct LifeAreaDebugSection: View {
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

nonisolated enum LifeAreaDistribution {
    // Percent of filed entries that carry each area. An entry with two areas counts for both,
    // so the column can add up to more than 100.
    static func shares(_ entries: [[LifeArea]]) -> [(area: LifeArea, percent: Int)] {
        guard !entries.isEmpty else { return LifeArea.allCases.map { ($0, 0) } }
        return LifeArea.allCases.map { area in
            let count = entries.filter { $0.contains(area) }.count
            return (area, Int((Double(count) / Double(entries.count) * 100).rounded()))
        }
    }
}
