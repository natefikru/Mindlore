import Foundation
import SwiftData

// Every save that stamps entries bumps this. Anything holding a derived copy of the journal reads
// it to tell whether that copy is stale, and putting it here means a new save path is covered by
// construction rather than by whoever adds it remembering to say so. Ask's index went blind to a
// recording's transcribed text exactly because three coordinators save straight through here,
// touching neither EntrySaver nor GraphServices.
//
// Monotonic, never a date: a clock that steps back must not be able to hide a change, which is why
// Entry.graphIndexedAt is an exact-equality stamp too.
enum JournalSaves {
    private(set) static var revision = 0

    static func recordSave() {
        revision += 1
    }
}

extension ModelContext {
    // A save writes every pending change in the context, including edits made elsewhere,
    // so every save path must stamp them or updatedAt falls behind the real last edit.
    // Entries in `unstamped` are skipped: writing AI insights marks the entry changed through
    // the relationship, but it isn't an edit to the entry itself.
    func stampChangedEntries(at date: Date, except unstamped: Set<PersistentIdentifier> = []) {
        for case let entry as Entry in changedModelsArray where !unstamped.contains(entry.persistentModelID) {
            entry.updatedAt = date
        }
    }

    func saveStampingEntries(at date: Date = .now, except unstamped: Set<PersistentIdentifier> = []) throws {
        stampChangedEntries(at: date, except: unstamped)
        try save()
        JournalSaves.recordSave()
    }
}
