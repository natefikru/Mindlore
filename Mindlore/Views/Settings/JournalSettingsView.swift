import SwiftUI

// What the journal is made of and how it looks: areas, the voice summaries are written in, the
// font, light or dark, and what the microphone does.
struct JournalSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                NavigationLink {
                    LifeAreasSettingsView()
                } label: {
                    LabeledContent("Life areas", value: areasSummary)
                }
                .accessibilityIdentifier("lifeAreasSettingsLink")

                NavigationLink {
                    JournalVoiceSettingsView()
                } label: {
                    LabeledContent("How you're written about", value: voiceSummary)
                }
                .accessibilityIdentifier("journalVoiceSettingsLink")

                NavigationLink {
                    JournalFontSettingsView()
                } label: {
                    LabeledContent("Font", value: settings.journalFont.settingsName)
                }
                .accessibilityIdentifier("journalFontSettingsLink")
            }

            Section {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppearancePreference.allCases, id: \.self) { option in
                        Text(option.settingsName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("appearancePicker")
            } header: {
                Text("Appearance")
            }

            Section {
                Toggle("Keep recordings", isOn: $settings.keepAudioAfterTranscription)
                    .accessibilityIdentifier("keepRecordingsToggle")
                Toggle("Start recording right away", isOn: $settings.recordOnOpen)
                    .accessibilityIdentifier("recordOnOpenToggle")
            } header: {
                Text("Recording")
            } footer: {
                Text((settings.recordOnOpen
                      ? "The microphone button starts recording the moment it's tapped. "
                      : "The microphone button opens the recorder, and recording starts when you tap the button on it. ")
                     + "When Keep recordings is off, a recording is deleted once its text has been generated and you've closed the entry.")
            }
        }
        .paperBackground()
        .navigationTitle("Your Journal")
        .navigationBarTitleDisplayMode(.inline)
    }

    // Not `settingsName`. Those are option titles ("I", "You", "My name") that read well above their
    // sample sentence on the voice screen, and as a lone value on the right a bare "I" looked like a
    // stray cursor in the screenshot.
    private var voiceSummary: String {
        switch settings.journalVoice {
        case .first: "First person"
        case .second: "Second person"
        case .name:
            settings.userName.isEmpty ? "By name" : settings.userName
        }
    }

    private var areasSummary: String {
        let shown = settings.visibleLifeAreas.count
        let all = LifeArea.allCases.count
        return shown == all ? "\(all) shown" : "\(shown) of \(all) shown"
    }
}
