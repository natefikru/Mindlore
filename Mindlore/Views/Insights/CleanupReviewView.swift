import SwiftUI

// Shows what a cleanup would change before it replaces the user's own words.
struct CleanupReviewView: View {
    let entry: Entry
    let cleaned: String
    let onReplace: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let runs = TextDiff.runs(original: entry.text, cleaned: cleaned)

        NavigationStack {
            Form {
                Section {
                    Text(TextDiff.summary(original: entry.text, cleaned: cleaned))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Your text") {
                    highlighted(runs.original, color: .red.opacity(0.25))
                }
                Section("Cleaned up") {
                    highlighted(runs.cleaned, color: .green.opacity(0.25))
                }
                Section {
                    Button("Replace my text") {
                        onReplace()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("replaceWithCleanedTextButton")
                } footer: {
                    Text("Your original is kept. You can go back to it any time from the entry's menu.")
                }
            }
            .navigationTitle("Cleaned-up text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // Changed words are marked with background and, for VoiceOver, described as a count.
    private func highlighted(_ runs: [TextDiff.Run], color: Color) -> some View {
        runs.reduce(Text("")) { result, run in
            result + Text(run.text).foregroundStyle(run.changed ? Color.primary : .secondary)
        }
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }
}
