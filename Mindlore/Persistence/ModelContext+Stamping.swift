import Foundation
import SwiftData

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
    }
}
