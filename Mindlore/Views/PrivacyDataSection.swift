import SwiftData
import SwiftUI

// Settings' "Privacy and data": the lock, the export, and the one delete with no Undo. Deleting
// the whole journal is the single place a confirmation dialog beats the undo pill, because there is
// nothing left afterwards to bring back.
struct PrivacyDataSection: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settings
    @Environment(AppLock.self) private var lock
    @Environment(EntrySaver.self) private var saver
    @Environment(GraphServices.self) private var graph
    @Environment(RecordingSession.self) private var recording
    @Environment(AskService.self) private var ask
    @Environment(AppRouter.self) private var router

    @State private var exporting = false
    @State private var exportFolder: URL?
    @State private var showingMover = false
    @State private var exportNote: String?
    @State private var confirmingDelete = false
    @State private var deleteNote: String?

    private let method = AppLock.methodName

    // Turning it on asks first, so nobody locks themselves out with a method that doesn't work.
    private var lockToggle: Binding<Bool> {
        Binding(
            get: { settings.appLockEnabled },
            set: { wanted in
                guard wanted else {
                    settings.appLockEnabled = false
                    lock.disabled()
                    return
                }
                Task {
                    if await AppLock.systemAuthenticate("Turn on the lock for your journal") {
                        settings.appLockEnabled = true
                    }
                }
            }
        )
    }

    var body: some View {
        Section {
            Toggle("Require \(method)", isOn: lockToggle)
                .disabled(!AppLock.isAvailable && !settings.appLockEnabled)
                .accessibilityIdentifier("appLockToggle")

            Button {
                export()
            } label: {
                HStack {
                    Text("Export journal")
                    Spacer()
                    if exporting { ProgressView() }
                }
            }
            .disabled(exporting)
            .accessibilityIdentifier("exportJournalButton")

            Button("Delete all data", role: .destructive) { confirmingDelete = true }
                .disabled(recording.status != .idle)
                .accessibilityIdentifier("deleteAllDataButton")
        } header: {
            Text("Privacy and data")
        } footer: {
            Text(footer)
        }
        .fileMover(isPresented: $showingMover, file: exportFolder) { result in
            switch result {
            case .success: exportNote = "Exported."
            case .failure: exportNote = "The export wasn't saved."
            }
            if let exportFolder { try? FileManager.default.removeItem(at: exportFolder.deletingLastPathComponent()) }
            exportFolder = nil
        }
        .confirmationDialog("Delete everything in your journal?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete All Data", role: .destructive) { deleteEverything() }
                .accessibilityIdentifier("confirmDeleteAllDataButton")
        } message: {
            Text("Every entry, recording, page photo, name, and conversation is removed from this iPhone. Settings and your API key stay. This can't be undone, so export first if you might want any of it.")
        }
    }

    private var footer: String {
        var parts: [String] = []
        if !AppLock.isAvailable && !settings.appLockEnabled {
            parts.append("Set a passcode in the Settings app to lock Mindlore.")
        } else {
            parts.append("Mindlore locks when you leave it and asks for \(method) when you come back.")
        }
        parts.append("An export is a folder with every entry as a Markdown file, a journal.json with everything Mindlore knows about each one, and your recordings and page photos.")
        if let exportNote { parts.append(exportNote) }
        if let deleteNote { parts.append(deleteNote) }
        return parts.joined(separator: " ")
    }

    private func export() {
        exporting = true
        exportNote = nil
        saver.flush()
        // Built in a folder of its own inside tmp, so the whole thing can be cleaned up afterwards.
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let summary = try JournalExport.write(from: modelContext, into: staging)
            exportFolder = summary.folder
            showingMover = true
        } catch {
            exportNote = "The export couldn't be written."
            try? FileManager.default.removeItem(at: staging)
        }
        exporting = false
    }

    private func deleteEverything() {
        saver.flush()
        do {
            try JournalWipe.deleteEverything(in: modelContext)
            ask.newConversation()
            router.journalPath = []
            router.mindPath = []
            graph.journalWiped()
            deleteNote = "Your journal was deleted."
        } catch {
            modelContext.rollback()
            deleteNote = "Nothing was deleted: the journal couldn't be changed."
        }
    }
}
