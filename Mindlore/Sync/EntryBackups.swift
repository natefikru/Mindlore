import Foundation
import SwiftData

// A copy of every entry's words kept outside the CloudKit store, one JSON file per entry.
//
// Core Data's CloudKit mirroring deletes the local store's synced data when the iCloud account
// signs out, changes, or (reported with full iCloud storage) sends a false access-revoked signal,
// and anything not yet uploaded is gone for good. These files are what a restore brings back:
// text, title, dates, and kind. Not audio or page photos, which are too large to keep twice, and
// not insights, which a rerun rebuilds.
//
// Written at the one place every save passes through (`ModelContext.saveStampingEntries` and
// `EntrySaver`), removed when the user deletes the entry, so a restore never resurrects a delete.
// Only the journal's own store has backups: they belong to a container, registered when it opens,
// so a test's store or a demo journal never writes into them.
nonisolated struct EntryBackup: Codable, Equatable, Sendable {
    var id: UUID
    var createdAt: Date
    var entryDate: Date
    var entryDateIsDayOnly: Bool
    var updatedAt: Date
    var title: String
    var text: String
    var sourceRaw: String
    var isCreative: Bool
    var isNote: Bool
}

final class EntryBackups {
    // What one save changes: entries to write, ids to remove. Read before the save clears them.
    struct Pending {
        var written: [EntryBackup] = []
        var removed: [UUID] = []
        var isEmpty: Bool { written.isEmpty && removed.isEmpty }
    }

    // Weak, and checked by identity: an address a released container leaves behind can be reused
    // by the next one, which must not inherit its backups.
    private struct Registration {
        weak var container: ModelContainer?
        let backups: EntryBackups
    }

    private static var registry: [ObjectIdentifier: Registration] = [:]

    static func register(_ backups: EntryBackups?, for container: ModelContainer) {
        registry[ObjectIdentifier(container)] = backups.map { Registration(container: container, backups: $0) }
    }

    static func of(_ context: ModelContext) -> EntryBackups? {
        let container = context.container
        guard let registration = registry[ObjectIdentifier(container)], registration.container === container else { return nil }
        return registration.backups
    }

    let folder: URL
    private let diagnostics: DiagnosticsLog

    init(folder: URL, diagnostics: DiagnosticsLog = .shared) {
        self.folder = folder
        self.diagnostics = diagnostics
    }

    static var standardFolder: URL {
        URL.applicationSupportDirectory.appendingPathComponent("EntryBackups", isDirectory: true)
    }

    static func snapshot(_ entry: Entry) -> EntryBackup {
        EntryBackup(
            id: entry.id,
            createdAt: entry.createdAt,
            entryDate: entry.entryDate,
            entryDateIsDayOnly: entry.entryDateIsDayOnly,
            updatedAt: entry.updatedAt,
            title: entry.title,
            text: entry.text,
            sourceRaw: entry.sourceRaw,
            isCreative: entry.isCreative,
            isNote: entry.isNote
        )
    }

    // Nothing worth restoring: an entry with no words yet is a recording still waiting for text,
    // or a blank the editor is about to delete.
    static func isWorthKeeping(_ entry: Entry) -> Bool {
        !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func pending(in context: ModelContext) -> Pending {
        guard of(context) != nil else { return Pending() }
        var pending = Pending()
        for case let entry as Entry in context.insertedModelsArray + context.changedModelsArray where isWorthKeeping(entry) {
            pending.written.append(snapshot(entry))
        }
        for case let entry as Entry in context.deletedModelsArray {
            pending.removed.append(entry.id)
        }
        return pending
    }

    func apply(_ pending: Pending) {
        guard !pending.isEmpty else { return }
        do {
            try prepare()
            let encoder = Self.encoder
            for backup in pending.written {
                try encoder.encode(backup).write(to: url(for: backup.id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            for id in pending.removed {
                try? FileManager.default.removeItem(at: url(for: id))
            }
        } catch {
            diagnostics.record("backup.writeFailed", ["error": .errorCode(error)])
        }
    }

    // Launch: every entry already in the store gets a backup if it has none, so a journal from
    // before this existed, or one that arrived from another device, is covered too.
    @discardableResult
    func fillIn(from context: ModelContext) throws -> Int {
        let existing = storedIDs()
        var added = Pending()
        for entry in try context.fetch(FetchDescriptor<Entry>()) where !existing.contains(entry.id) && Self.isWorthKeeping(entry) {
            added.written.append(Self.snapshot(entry))
        }
        apply(added)
        return added.written.count
    }

    func storedIDs() -> Set<UUID> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return Set(names.compactMap { name in
            name.hasSuffix(".json") ? UUID(uuidString: String(name.dropLast(5))) : nil
        })
    }

    func all() -> [EntryBackup] {
        let decoder = Self.decoder
        return storedIDs().compactMap { id in
            (try? Data(contentsOf: url(for: id))).flatMap { try? decoder.decode(EntryBackup.self, from: $0) }
        }
    }

    // Backups whose entry is not in the store: what a restore would bring back.
    func missing(from context: ModelContext) throws -> [EntryBackup] {
        let present = Set(try context.fetch(FetchDescriptor<Entry>()).map(\.id))
        return all().filter { !present.contains($0.id) }.sorted { $0.entryDate > $1.entryDate }
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: folder)
    }

    private func url(for id: UUID) -> URL {
        folder.appendingPathComponent("\(id.uuidString).json")
    }

    // Like Recordings/, kept out of the phone's own backup: the store is backed up already.
    private func prepare() throws {
        guard !FileManager.default.fileExists(atPath: folder.path) else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var root = folder
        try root.setResourceValues(values)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension Entry {
    // A restored entry keeps its original id, so if iCloud later brings the same entry back too,
    // `EntryDuplicates` recognizes the pair and keeps one.
    static func restored(from backup: EntryBackup) -> Entry {
        let entry = Entry(id: backup.id, createdAt: backup.createdAt, source: EntrySource(rawValue: backup.sourceRaw) ?? .typed, text: backup.text)
        entry.entryDate = backup.entryDate
        entry.entryDateIsDayOnly = backup.entryDateIsDayOnly
        entry.updatedAt = backup.updatedAt
        entry.title = backup.title
        entry.isCreative = backup.isCreative
        entry.isNote = backup.isNote
        return entry
    }
}
