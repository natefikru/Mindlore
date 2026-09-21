import SwiftUI

// The Settings tab. Organised by what a setting touches, not by which subsystem owns it: life areas
// and the name you are written by are journal concepts that work with AI off, so they sit at the
// top level rather than three levels down inside AI.
struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
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
                        LabeledContent("How you're written about", value: settings.journalVoice.settingsName)
                    }
                    .accessibilityIdentifier("journalVoiceSettingsLink")

                    Toggle("Keep recordings", isOn: $settings.keepAudioAfterTranscription)
                        .accessibilityIdentifier("keepRecordingsToggle")
                } header: {
                    Text("Your journal")
                } footer: {
                    Text("When Keep recordings is off, a recording is deleted once its text has been generated and you've closed the entry.")
                }

                Section {
                    Toggle("Names you haven't written about", isOn: $settings.resurfacingEnabled)
                        .accessibilityIdentifier("resurfacingToggle")
                } header: {
                    Text("Today")
                } footer: {
                    Text("Today can mention a person, a place, or a project that hasn't appeared in your journal for a while. You can also turn off a single one from its card.")
                }

                AISettingsSection()

                #if DEBUG
                LifeAreaDebugSection()
                #endif
            }
            .paperBackground()
            .navigationTitle("Settings")
        }
    }

    private var areasSummary: String {
        let shown = settings.visibleLifeAreas.count
        let all = LifeArea.allCases.count
        return shown == all ? "\(all) shown" : "\(shown) of \(all) shown"
    }
}

// No #Preview. The root now carries the Debug distribution section, which needs an
// InsightsCoordinator and a live ModelContext, and a preview that has to build half the app to
// render one Form is worth less than the screenshot test that drives the real thing.
