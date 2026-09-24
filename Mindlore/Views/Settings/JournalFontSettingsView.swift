import SwiftUI

// The face the user's own words are set in, each option shown in itself so the choice is made
// by eye rather than by name.
struct JournalFontSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    static let sample = "Walked to the river this morning. The light was strange, and I stayed longer than I meant to."

    var body: some View {
        Form {
            Section {
                ForEach(JournalFont.allCases, id: \.self) { option in
                    Button {
                        settings.journalFont = option
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(option.settingsName)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(Self.sample)
                                    .font(.system(.body, design: option.design))
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(2)
                                Text(option.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if settings.journalFont == option {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Palette.ember)
                                    .fontWeight(.semibold)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(settings.journalFont == option ? .isSelected : [])
                    .accessibilityIdentifier("journalFont-\(option.rawValue)")
                }
            } footer: {
                Text("Your entries, titles, and quoted words take this face. Everything the app itself says stays in the system font.")
            }
        }
        .paperBackground()
        .navigationTitle("Font")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(Haptics.selected, trigger: settings.journalFont)
    }
}
