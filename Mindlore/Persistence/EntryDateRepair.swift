import Foundation
import SwiftData

// Entries whose date the user never picked must have entryDate == createdAt. The lightweight
// migration that added entryDate gave existing entries one default value instead, so this runs
// at every launch and fixes any entry that breaks the rule. It is a no-op once dates are right.
enum EntryDateRepair {
    @discardableResult
    static func run(in context: ModelContext) throws -> Int {
        let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { !$0.entryDateIsDayOnly })
        var repaired = 0
        for entry in try context.fetch(descriptor) where entry.entryDate != entry.createdAt {
            entry.entryDate = entry.createdAt
            repaired += 1
        }
        if repaired > 0 {
            try context.save()
        }
        return repaired
    }
}
