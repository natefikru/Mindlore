import Foundation
import SwiftData

// Mind's panel rows: every entity with when it was last mentioned and how many loose ends about
// it are still open, counted through merges. One entity fetch and one loose-end fetch.
enum MindDirectory {
    struct Rows: Equatable {
        var visible: [EntitySearch.Row] = []
        var hidden: [EntitySearch.Row] = []
    }

    // What the panel refreshes on besides graph.revision: marking a loose end Done changes its
    // status without changing how many there are, and doesn't bump the revision.
    nonisolated struct RefreshKey: Hashable {
        let revision: Int
        let looseEnds: [String]
    }

    nonisolated static func looseEndKey(_ pairs: [(id: UUID, status: String)]) -> [String] {
        pairs.map { "\($0.id.uuidString):\($0.status)" }.sorted()
    }

    static func rows(in context: ModelContext) -> Rows {
        let directory = EntityDirectory(in: context)
        let entities = ((try? context.fetch(FetchDescriptor<Entity>())) ?? []).filter { !$0.isDeleted }

        var openCounts: [UUID: Int] = [:]
        for looseEnd in LooseEnd.all(in: context) where looseEnd.isOpen {
            for root in Set(looseEnd.entityIDs.map(directory.root(of:))) {
                openCounts[root, default: 0] += 1
            }
        }

        func row(_ entity: Entity) -> EntitySearch.Row {
            EntitySearch.Row(
                id: entity.id,
                name: entity.name,
                aliases: entity.aliases,
                kind: entity.kind,
                linkCount: entity.linkCount,
                lastMentioned: entity.lastLinkedAt,
                openLooseEnds: openCounts[entity.id] ?? 0
            )
        }

        return Rows(
            visible: entities.filter(\.isBrowsable).map(row),
            hidden: entities.filter { $0.hidden && !$0.isMerged }.map(row)
        )
    }
}
