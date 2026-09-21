import SwiftUI

// The Settings tab. Organised by what a setting touches, not by which subsystem owns it: life areas
// and the name you are written by are journal concepts that work with AI off, so they sit at the
// top level rather than three levels down inside AI.
struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(EntrySaver.self) private var saver
    @Environment(GraphServices.self) private var graph
    @State private var totals = JournalTotals()

    // Today's fingerprint, minus the day: `saver` and `graph` are observable and redraw this view
    // when they move, and `JournalSaves.revision` rides along for the coordinators that save
    // straight through `saveStampingEntries`. Never a count, which an add and a delete can return
    // to where it was.
    private struct TotalsFingerprint: Equatable {
        let saver: Int
        let graph: Int
        let stamped: Int
    }

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
                        LabeledContent("How you're written about", value: voiceSummary)
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

                Section {
                    LabeledContent("Entries", value: "\(totals.entries)")
                        .accessibilityIdentifier("totalEntries")
                    LabeledContent("People, places, and more", value: "\(totals.names)")
                        .accessibilityIdentifier("totalNames")
                } header: {
                    Text("About")
                }
                .task(id: TotalsFingerprint(saver: saver.revision, graph: graph.revision, stamped: JournalSaves.revision)) {
                    totals = JournalTotals.count(in: modelContext)
                }

                #if DEBUG
                LifeAreaDebugSection()
                #endif
            }
            .paperBackground()
            .navigationTitle("Settings")
        }
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

// No #Preview. The root now carries the Debug distribution section, which needs an
// InsightsCoordinator and a live ModelContext, and a preview that has to build half the app to
// render one Form is worth less than the screenshot test that drives the real thing.
