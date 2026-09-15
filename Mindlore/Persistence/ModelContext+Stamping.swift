import Foundation
import SwiftData

extension ModelContext {
    // A save writes every pending change in the context, including edits made elsewhere,
    // so every save path must stamp them or updatedAt falls behind the real last edit.
    func stampChangedEntries(at date: Date) {
        for case let entry as Entry in changedModelsArray {
            entry.updatedAt = date
        }
    }

    func saveStampingEntries(at date: Date = .now) throws {
        stampChangedEntries(at: date)
        try save()
    }
}
