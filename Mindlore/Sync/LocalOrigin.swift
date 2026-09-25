import Foundation
import SwiftData

// The entries this phone made, so automatic AI runs only where an entry was made.
//
// Two phones on one synced journal would otherwise each transcribe the same recording and each run
// insights on the same entry: two OpenAI bills, and duplicate loose ends and names. The set lives in
// UserDefaults, which never syncs, and `Entry` gains nothing. The manual buttons (Retry, Transcribe
// here, Run AI, Redo insights) work on any entry and claim it, so the phone that ran a job by hand
// owns it afterwards.
//
// Claimed at the two places every save passes through (`ModelContext.saveStampingEntries` and
// `EntrySaver`) from the context's inserted entries, which is every entry made here, typed,
// recorded, photographed, written by Chat, imported, or restored. An entry CloudKit brings in
// arrives through the mirroring's own context and is never inserted into this one.
//
// Registered to the journal's container only, like `EntryBackups`: a context with none registered
// (a test's store, a demo journal) treats every entry as local, so nothing changes off the synced
// journal.
final class LocalOrigin {
    private struct Registration {
        weak var container: ModelContainer?
        let origin: LocalOrigin
    }

    private static var registry: [ObjectIdentifier: Registration] = [:]

    static func register(_ origin: LocalOrigin?, for container: ModelContainer) {
        registry[ObjectIdentifier(container)] = origin.map { Registration(container: container, origin: $0) }
    }

    static func of(_ context: ModelContext) -> LocalOrigin? {
        let container = context.container
        guard let registration = registry[ObjectIdentifier(container)], registration.container === container else { return nil }
        return registration.origin
    }

    // Whether this phone's automatic jobs may run on the entry. One not yet saved was made here.
    static func isLocal(_ entry: Entry) -> Bool {
        guard let context = entry.modelContext, let origin = of(context) else { return true }
        return origin.contains(entry.id) || context.insertedModelsArray.contains { $0 === entry }
    }

    // A manual run: this phone owns the entry from now on.
    static func claim(_ entry: Entry) {
        guard let context = entry.modelContext else { return }
        of(context)?.claim([entry.id])
    }

    // Read before a save clears them.
    static func inserted(in context: ModelContext) -> [UUID] {
        guard of(context) != nil else { return [] }
        return context.insertedModelsArray.compactMap { ($0 as? Entry)?.id }
    }

    static func claimInserted(_ ids: [UUID], in context: ModelContext) {
        guard !ids.isEmpty else { return }
        of(context)?.claim(ids)
    }

    static let idsKey = "localOrigin.entryIDs"
    static let seededKey = "localOrigin.seeded"

    private let store: KeyValueStore
    private let diagnostics: DiagnosticsLog
    private var ids: Set<UUID>

    init(store: KeyValueStore = UserDefaults.standard, diagnostics: DiagnosticsLog = .shared) {
        self.store = store
        self.diagnostics = diagnostics
        let raw = (store.object(forKey: Self.idsKey) as? Data).flatMap { try? JSONDecoder().decode([UUID].self, from: $0) } ?? []
        ids = Set(raw)
    }

    func contains(_ id: UUID) -> Bool {
        ids.contains(id)
    }

    func claim(_ new: [UUID]) {
        let before = ids.count
        ids.formUnion(new)
        guard ids.count != before else { return }
        store.set(try? JSONEncoder().encode(Array(ids)), forKey: Self.idsKey)
    }

    // The journal this phone already had is its own: every entry in the store when the set first
    // exists joins it, once. After that only saves and manual runs add to it.
    @discardableResult
    func seedIfNeeded(from context: ModelContext) throws -> Int {
        guard store.object(forKey: Self.seededKey) == nil else { return 0 }
        let existing = try context.fetch(FetchDescriptor<Entry>()).map(\.id)
        claim(existing)
        store.set(true, forKey: Self.seededKey)
        diagnostics.record("sync.originSeeded", ["count": .int(existing.count)])
        return existing.count
    }
}
