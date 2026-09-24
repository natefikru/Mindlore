import SwiftUI

// Where the journal is kept, who can open it, how the app looks (light, dark, or the system's;
// owner, 2026-09-24, moved from Your journal), and getting everything out or deleting it.
struct GeneralSettingsView: View {
    var body: some View {
        Form {
            SyncSettingsSection()
            AppLockSection()
            AppearanceSection()
            JournalDataSection()
        }
        .paperBackground()
        .navigationTitle("General")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AppearanceSection: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

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
    }
}
