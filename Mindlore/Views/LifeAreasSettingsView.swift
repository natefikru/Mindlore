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
        }
        .paperBackground()
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
                // What an area is called is the user's own word for it, so it is set in their face,
                // not the app's. Everything around it stays SF.
                //
                // The field holds the name actually shown, not only a rename. It used to start empty
                // with the default name as its placeholder, which drew all nine names in placeholder
                // grey, so an area nobody had renamed looked disabled. `rename` stores nil for the
                // default name and ignores a no-op, so seeding the field writes nothing.
                TextField(area.defaultName, text: $name)
                    .journalText(.body)
                    .foregroundStyle(Palette.ink)
                    .onChange(of: name) { settings.rename(area, to: name) }
                    // A cleared field falls back to the default name, so show that rather than blank.
                    .onSubmit { name = settings.name(of: area) }
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
        .onAppear { name = settings.name(of: area) }
    }
}

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
