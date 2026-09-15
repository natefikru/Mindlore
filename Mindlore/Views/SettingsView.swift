import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section {
                    Picker("New entries start with", selection: $settings.defaultEntryMode) {
                        Text("Voice").tag(EntrySource.voice)
                        Text("Typing").tag(EntrySource.typed)
                    }
                }

                Section {
                    Toggle("Keep recordings", isOn: $settings.keepAudioAfterTranscription)
                } footer: {
                    Text("When this is off, a recording is deleted once its text has been generated and you've closed the entry.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(SettingsStore(store: UserDefaults(suiteName: "preview")!))
}
