import Foundation

// The value an entity leans toward across its entries: its life area on the map, or its mood
// around. Each linked entry counts each of its values once and the most common value wins. A
// tie goes to the tied value seen in the most recent entry, then to the type's case order.
// Entities whose entries carry no values get none.
nonisolated enum EntityTally {
    struct Entry<Value: Hashable & Sendable>: Sendable {
        let values: [Value]
        let date: Date

        init(values: [Value], date: Date) {
            self.values = values
            self.date = date
        }
    }

    static func primary<Value: CaseIterable & Hashable & Sendable>(
        links: [EntityGraph.LinkInput],
        values: [UUID: Entry<Value>]
    ) -> [UUID: Value] {
        var entriesByEntity: [UUID: Set<UUID>] = [:]
        for link in links {
            entriesByEntity[link.entityID, default: []].insert(link.entryID)
        }
        var result: [UUID: Value] = [:]
        for (entityID, entryIDs) in entriesByEntity {
            var counts: [Value: Int] = [:]
            var latest: [Value: Date] = [:]
            for entryID in entryIDs {
                guard let entry = values[entryID] else { continue }
                for value in Set(entry.values) {
                    counts[value, default: 0] += 1
                    latest[value] = max(latest[value] ?? .distantPast, entry.date)
                }
            }
            guard let top = counts.values.max() else { continue }
            let tied = Value.allCases.filter { counts[$0] == top }
            // max(by:) keeps the first of equal elements, so equal dates fall back to case order.
            result[entityID] = tied.max { (latest[$0] ?? .distantPast) < (latest[$1] ?? .distantPast) }
        }
        return result
    }
}
