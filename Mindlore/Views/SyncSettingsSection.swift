import SwiftUI

// The first section of Settings (owner, 2026-09-23): where the journal is kept, in one row and one
// sentence. Sync has no switch yet; it is on whenever this iPhone is signed in to iCloud.
struct SyncSettingsSection: View {
    @Environment(SyncStatusMonitor.self) private var sync
    @Environment(JournalRecovery.self) private var recovery
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Section {
            LabeledContent("iCloud sync", value: sync.status.summary)
                .accessibilityIdentifier("syncStatusRow")
            if !recovery.missing.isEmpty {
                Button(RestoreCopy.button(count: recovery.missing.count)) {
                    recovery.restoreAll(in: modelContext)
                }
                .accessibilityIdentifier("settingsRestoreMissingEntries")
            }
        } header: {
            Text("iCloud")
        } footer: {
            Text(sync.status.explanation)
                .accessibilityIdentifier("syncStatusExplanation")
        }
    }
}
