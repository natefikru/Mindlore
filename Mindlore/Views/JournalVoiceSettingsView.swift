import SwiftUI

// Who the app calls you in the words it writes: summaries, entity bios, and loose ends.
struct JournalVoiceSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var name = ""

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                ForEach(JournalVoice.allCases, id: \.self) { voice in
                    Button {
                        settings.journalVoice = voice
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                // Concrete colours, not `.primary` and `.secondary`. Inside a Form a
                                // Button tints its label, and the hierarchical styles resolve against
                                // that tint, which drew all three options in Ember and made a choice
                                // read like three links. Only the checkmark carries the accent.
                                Text(voice.settingsName)
                                    .foregroundStyle(Palette.ink)
                                // The sample is a sentence about the user, written the way the app
                                // would write it, so it is shown in the face those sentences use.
                                Text(sample(for: voice))
                                    .journalText(.caption)
                                    .foregroundStyle(Color.secondary)
                            }
                            Spacer()
                            if settings.journalVoice == voice {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .accessibilityIdentifier("journalVoice-\(voice.rawValue)")
                    .accessibilityAddTraits(settings.journalVoice == voice ? .isSelected : [])
                }
            } header: {
                Text("Voice")
            } footer: {
                Text("How summaries, bios, and loose ends talk about you.")
            }

            Section {
                TextField("Your name", text: $name)
                    .journalText(.body)
                    .foregroundStyle(Palette.ink)
                    .textContentType(.givenName)
                    .onChange(of: name) { settings.setUserName(name) }
                    .accessibilityIdentifier("userNameField")
            } header: {
                Text("Name")
            } footer: {
                Text(settings.journalVoice == .name
                     ? "Sent to your AI provider in each request so it can write about you by name."
                     : "Used only when the voice above is set to your name. It is not sent anywhere until then.")
            }
        }
        .sensoryFeedback(Haptics.selected, trigger: settings.journalVoice)
        .paperBackground()
        .navigationTitle("How You're Written About")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { name = settings.userName }
    }

    // The name option reads better with the real name in it once there is one.
    private func sample(for voice: JournalVoice) -> String {
        guard voice == .name else { return voice.sample }
        let typed = settings.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? voice.sample : "\(typed) met Sarah at the coffee place."
    }
}
