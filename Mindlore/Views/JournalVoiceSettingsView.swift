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
                                Text(voice.settingsName)
                                    .foregroundStyle(.primary)
                                Text(sample(for: voice))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
