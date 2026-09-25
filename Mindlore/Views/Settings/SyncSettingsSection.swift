import SwiftUI

// The first section of General (owner, 2026-09-23): where the journal is kept, in one row and one
// sentence, and the switch (owner, 2026-09-25). The switch only records the choice; the journal
// reopens the other way when Settings closes (`SettingsView`), since reopening it rebuilds
// everything under this sheet.
struct SyncSettingsSection: View {
    @Environment(SyncStatusMonitor.self) private var sync
    @Environment(JournalRecovery.self) private var recovery
    @Environment(JournalHost.self) private var host
    @Environment(RecordingSession.self) private var recording
    @Environment(\.modelContext) private var modelContext
    @State private var confirmingOff = false

    var body: some View {
        Section {
            if host.isJournal {
                Toggle("Sync with iCloud", isOn: Binding(
                    get: { host.requestedSyncOn },
                    set: { on in
                        if on { host.requestSync(true) } else { confirmingOff = true }
                    }
                ))
                // Reopening the journal would cut a recording off.
                .disabled(recording.showsAccessory)
                .accessibilityIdentifier("syncSwitch")
            }
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
            Text(footer)
                .accessibilityIdentifier("syncStatusExplanation")
        }
        .confirmationDialog("Turn off iCloud sync on this iPhone?", isPresented: $confirmingOff, titleVisibility: .visible) {
            Button("Turn Off Sync", role: .destructive) { host.requestSync(false) }
                .accessibilityIdentifier("confirmSyncOff")
        } message: {
            Text("Your journal stays on this iPhone. Changes you make here won't reach your other devices, and theirs won't arrive, until you turn it back on.")
        }
    }

    private var footer: String {
        if host.hasPendingSwitch {
            return host.requestedSyncOn ? "Sync turns on when you close Settings." : "Sync turns off when you close Settings."
        }
        if host.isJournal, recording.showsAccessory {
            return sync.status.explanation + " You can change this once the recording ends."
        }
        return sync.status.explanation
    }
}
