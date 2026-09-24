import SwiftUI

// Where the journal is kept, who can open it, and getting everything out or deleting it. Import
// will sit beside export when it exists.
struct GeneralSettingsView: View {
    var body: some View {
        Form {
            SyncSettingsSection()
            AppLockSection()
            JournalDataSection()
        }
        .paperBackground()
        .navigationTitle("General")
        .navigationBarTitleDisplayMode(.inline)
    }
}
