import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
#if DEBUG
                Section {
                    NavigationLink("3D spike") { Mind3DSpikeView() }
                        .accessibilityIdentifier("spike3DLink")
                }
#endif

                Section {
                    NavigationLink("AI") { AISettingsView() }
                        .accessibilityIdentifier("aiSettingsLink")
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
    let settings = SettingsStore(store: UserDefaults(suiteName: "preview")!)
    return SettingsView()
        .environment(settings)
        .environment(ProviderAccountStore(settings: settings))
}
