import SwiftUI

// Lets the user set an entry's moods themselves. The choice lives on the insights, like the rest of
// what this screen shows, and a later run replaces it (with a warning first).
struct MoodPickerView: View {
    let insights: EntryInsights
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var primary: Mood?
    @State private var secondary: [Mood]

    init(insights: EntryInsights, onSave: @escaping () -> Void) {
        self.insights = insights
        self.onSave = onSave
        _primary = State(initialValue: insights.primaryMood)
        _secondary = State(initialValue: insights.secondaryMoods)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let primary {
                        LabeledContent("Primary", value: primary.name)
                    } else {
                        Text("Pick a primary mood")
                            .foregroundStyle(.secondary)
                    }
                    if !secondary.isEmpty {
                        LabeledContent("Also", value: secondary.map(\.name).joined(separator: ", "))
                    }
                } footer: {
                    Text("Tap a mood to make it the primary one. Tap and hold, or tap it again, to list it under Also (up to two).")
                }

                ForEach(MoodCategory.allCases, id: \.self) { category in
                    Section("\(category.name)") {
                        ForEach(Mood.allCases.filter { $0.category == category }, id: \.self) { mood in
                            Button {
                                choose(mood)
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Image(systemName: symbol(for: mood))
                                        .foregroundStyle(mood.category.color)
                                    VStack(alignment: .leading) {
                                        Text(mood.name).foregroundStyle(.primary)
                                        Text(mood.meaning).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .accessibilityIdentifier("mood-\(mood.rawValue)")
                        }
                    }
                }
            }
            .navigationTitle("Moods")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        insights.setMoods(primary: primary, secondary: secondary)
                        onSave()
                        dismiss()
                    }
                    .disabled(primary == nil)
                    .accessibilityIdentifier("saveMoodsButton")
                }
            }
        }
    }

    private func symbol(for mood: Mood) -> String {
        if mood == primary { return "circle.fill" }
        return secondary.contains(mood) ? "circle.lefthalf.filled" : "circle"
    }

    // Tapping cycles: primary, then also, then off.
    private func choose(_ mood: Mood) {
        if primary == mood {
            primary = nil
            if secondary.count < 2 { secondary.append(mood) }
        } else if secondary.contains(mood) {
            secondary.removeAll { $0 == mood }
        } else if primary == nil {
            primary = mood
        } else if secondary.count < 2 {
            secondary.append(mood)
        } else {
            primary = mood
        }
        secondary.removeAll { $0 == primary }
    }
}
