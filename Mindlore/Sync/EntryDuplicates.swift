import Foundation
import SwiftData

// Two entries with one id: a restore from the safety copy, then iCloud bringing the same entry
// back once the account returns. CloudKit knows them as two records, so nothing else will ever
// merge them. Keeps the most recently edited one, and deletes the other straight through the
// context rather than `Entry.delete`, which would roll back the survivor's loose ends by id.
enum EntryDuplicates {
    @discardableResult
    static func merge(in context: ModelContext) throws -> Int {
        let entries = try context.fetch(FetchDescriptor<Entry>())
        var removed = 0
        var survivors: [Entry] = []
        for group in Dictionary(grouping: entries, by: \.id).values where group.count > 1 {
            let ordered = group.sorted { ($0.updatedAt, $0.text.count) > ($1.updatedAt, $1.text.count) }
            survivors.append(ordered[0])
            for duplicate in ordered.dropFirst() {
                context.delete(duplicate)
                removed += 1
            }
        }
        guard removed > 0 else { return 0 }
        try context.save()
        // A plain save, so the id's backup file is untouched; it is rewritten from the survivor so
        // it matches the copy that was kept.
        EntryBackups.of(context)?.apply(EntryBackups.Pending(written: survivors.filter(EntryBackups.isWorthKeeping).map(EntryBackups.snapshot)))
        return removed
    }
}
