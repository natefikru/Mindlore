import Foundation
import SwiftData

// A link whose relationship is empty but whose id names an entity gets the relationship back.
// `EntityLink.entity` became `linkedEntity` as a new relationship (a CloudKit store can't rename
// one), so every link that existed before starts out empty. The id is the truth; the relationship
// only carries the delete rules. Runs at every launch and is a no-op once every link is filled.
enum EntityLinkRepair {
    @discardableResult
    static func run(in context: ModelContext) throws -> Int {
        // The emptiness is checked here, not in a predicate: `linkedEntity == nil` in #Predicate
        // matched every link on the phone, so each launch rewrote all of them and re-uploaded
        // them to iCloud.
        let empty = try context.fetch(FetchDescriptor<EntityLink>(predicate: #Predicate { $0.entityID != nil }))
            .filter { $0.linkedEntity == nil }
        guard !empty.isEmpty else { return 0 }
        let entities = Dictionary(try context.fetch(FetchDescriptor<Entity>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var repaired = 0
        for link in empty {
            guard let id = link.entityID, let entity = entities[id] else { continue }
            link.linkedEntity = entity
            repaired += 1
        }
        // A plain save, like EntryDateRepair: this runs in MindloreApp.init before any index or
        // screen exists, so there is no JournalSaves.revision reader to tell.
        if repaired > 0 {
            try context.save()
        }
        return repaired
    }
}
