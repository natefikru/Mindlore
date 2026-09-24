import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// General's lock: Face ID (or whatever this phone has) when coming back to the app.
struct AppLockSection: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AppLock.self) private var lock

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
        } header: {
            Text("Lock")
        } footer: {
            Text(!AppLock.isAvailable && !settings.appLockEnabled
                 ? "Set a passcode in the Settings app to lock Mindlore."
                 : "Mindlore locks when you leave it and asks for \(method) when you come back.")
        }
    }
}

// General's data tools: the export, putting an export back, and the one delete with no Undo. Deleting the whole journal is
// the single place a confirmation dialog beats the undo pill, because there is nothing left
// afterwards to bring back.
struct JournalDataSection: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncStatusMonitor.self) private var sync
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
    @State private var pickingImport = false
    @State private var importing = false
    @State private var pendingImport: (prepared: JournalImport.Prepared, preview: JournalImport.Preview)?
    @State private var importNote: String?
    // Only a folder whose access was actually granted is handed back; stopping one that wasn't
    // started is unbalanced.
    @State private var accessingFolder = false

    var body: some View {
        Section {
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

            Button {
                pickingImport = true
            } label: {
                HStack {
                    Text("Import journal")
                    Spacer()
                    if importing { ProgressView() }
                }
            }
            .disabled(importing || recording.status != .idle)
            .accessibilityIdentifier("importJournalButton")

            Button("Delete all data", role: .destructive) { confirmingDelete = true }
                .disabled(recording.status != .idle)
                .accessibilityIdentifier("deleteAllDataButton")
        } header: {
            Text("Your data")
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
        .fileImporter(isPresented: $pickingImport, allowedContentTypes: [.folder]) { result in
            guard case .success(let folder) = result else { return }
            Task { await prepareImport(folder) }
        }
        // The folder travels into the button's action rather than being read back from state:
        // tapping a button also dismisses the dialog, and the dismissal must not be what releases
        // the folder the import is about to read media from.
        .confirmationDialog(
            importTitle,
            isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
            titleVisibility: .visible,
            presenting: pendingImport?.prepared
        ) { prepared in
            Button("Import") { Task { await runImport(prepared) } }
                .accessibilityIdentifier("confirmImportJournalButton")
            Button("Cancel", role: .cancel) { releaseFolder(prepared.folder) }
        } message: { _ in
            Text(importMessage)
        }
        .confirmationDialog("Delete everything in your journal?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete All Data", role: .destructive) { deleteEverything() }
                .accessibilityIdentifier("confirmDeleteAllDataButton")
        } message: {
            Text(sync.status.reachesICloud
                 ? "Every entry, recording, page photo, name, and conversation is removed from this iPhone, from iCloud, and from your other devices. Settings and your API key stay. This can't be undone, so export first if you might want any of it."
                 : "Every entry, recording, page photo, name, and conversation is removed from this iPhone. Settings and your API key stay. This can't be undone, so export first if you might want any of it.")
        }
    }

    private var footer: String {
        var parts: [String] = []
        parts.append("An export is a folder with every entry as a Markdown file, a journal.json with everything Mindlore knows about each one, and your recordings and page photos.")
        parts.append("Import puts an export back. Anything already in this journal stays as it is.")
        if let exportNote { parts.append(exportNote) }
        if let importNote { parts.append(importNote) }
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

    private var importTitle: String {
        guard let preview = pendingImport?.preview else { return "" }
        return preview.newEntries == 0 ? "Everything in this export is already here." : "Import \(Self.entries(preview.newEntries))?"
    }

    private var importMessage: String {
        guard let preview = pendingImport?.preview else { return "" }
        var parts: [String] = []
        if preview.newNames > 0 { parts.append("\(preview.newNames) people, places, and more come with them.") }
        if preview.existingEntries > 0 {
            parts.append("\(Self.entries(preview.existingEntries)) \(preview.existingEntries == 1 ? "is" : "are") already here and stay as \(preview.existingEntries == 1 ? "it is" : "they are").")
        }
        parts.append("Nothing is sent anywhere, and no AI runs.")
        return parts.joined(separator: " ")
    }

    private static func entries(_ count: Int) -> String {
        count == 1 ? "1 entry" : "\(count) entries"
    }

    // The folder the picker hands back is only readable while its access is held, and the media is
    // read entry by entry during the import, so access runs from here until the import is done.
    private func prepareImport(_ folder: URL) async {
        importNote = nil
        accessingFolder = folder.startAccessingSecurityScopedResource()
        do {
            let prepared = try await Task.detached { try JournalImport.read(folder: folder) }.value
            pendingImport = (prepared, JournalImport.preview(prepared, in: modelContext))
        } catch {
            releaseFolder(folder)
            importNote = error as? JournalImport.Failure == .olderExport
                ? "That export was made before Mindlore could import. Export again from the phone the journal is on, then import that."
                : "That folder isn't a Mindlore export."
        }
    }

    private func releaseFolder(_ folder: URL) {
        if accessingFolder { folder.stopAccessingSecurityScopedResource() }
        accessingFolder = false
    }

    private func runImport(_ prepared: JournalImport.Prepared) async {
        importing = true
        saver.flush()
        do {
            let summary = try await JournalImport.apply(prepared, into: modelContext)
            graph.journalImported()
            var note = "Imported \(Self.entries(summary.entries))."
            if summary.missingMedia > 0 { note += " \(summary.missingMedia) recordings or photos were missing from the folder." }
            importNote = note
        } catch {
            modelContext.rollback()
            importNote = "The import stopped partway. What was saved stays; importing again adds the rest."
        }
        importing = false
        releaseFolder(prepared.folder)
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
