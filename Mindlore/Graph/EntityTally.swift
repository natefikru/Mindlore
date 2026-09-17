import Foundation

// The life area an entity belongs to on the map: the area most of its entries are filed under.
// A tie goes to the tied area of its most recent entry, then to LifeArea's own order. Entities
// whose entries have no areas get none.
nonisolated enum EntityAreas {
    struct EntryAreas: Sendable {
        let areas: [LifeArea]
        let date: Date
    }

    static func primaryAreas(links: [EntityGraph.LinkInput], areasByEntry: [UUID: EntryAreas]) -> [UUID: LifeArea] {
        var entriesByEntity: [UUID: Set<UUID>] = [:]
        for link in links {
            entriesByEntity[link.entityID, default: []].insert(link.entryID)
        }
        var result: [UUID: LifeArea] = [:]
        for (entityID, entryIDs) in entriesByEntity {
            var counts: [LifeArea: Int] = [:]
            var latest: [LifeArea: Date] = [:]
            for entryID in entryIDs {
                guard let entry = areasByEntry[entryID] else { continue }
                for area in Set(entry.areas) {
                    counts[area, default: 0] += 1
                    latest[area] = max(latest[area] ?? .distantPast, entry.date)
                }
            }
            guard let top = counts.values.max() else { continue }
            let tied = LifeArea.allCases.filter { counts[$0] == top }
            // max(by:) keeps the first of equal elements, so equal dates fall back to LifeArea's order.
            result[entityID] = tied.max { (latest[$0] ?? .distantPast) < (latest[$1] ?? .distantPast) }
        }
        return result
    }
}
