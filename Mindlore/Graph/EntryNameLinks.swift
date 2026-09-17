import SwiftData
import SwiftUI

// The names one entry's links give read mode, each resolved to the entity a tap should open.
enum EntryNameLinks {
    // One link fetch filtered in memory and one entity fetch, never the relationships.
    static func candidates(forEntry entryID: UUID, links: [EntityLink], entities: [Entity]) -> [EntityNameRanges.Candidate] {
        let byID = Dictionary(entities.filter { !$0.isDeleted }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        func root(of id: UUID) -> Entity? {
            guard var current = byID[id] else { return nil }
            var seen: Set<UUID> = [current.id]
            while let nextID = current.mergedIntoID, let next = byID[nextID], seen.insert(next.id).inserted {
                current = next
            }
            return current
        }

        var order: [UUID] = []
        var names: [UUID: [String]] = [:]
        for link in links where link.entryID == entryID && !link.isDeleted {
            // Tags are ordinary words ("river"); linking them would turn prose into links.
            guard link.kind != .tag, let entityID = link.entityID,
                  let root = root(of: entityID), root.isBrowsable, root.kind != .tag
            else { continue }
            if names[root.id] == nil {
                order.append(root.id)
                names[root.id] = []
            }
            names[root.id]?.append(contentsOf: [link.writtenSurface, link.surface].compactMap { $0 })
        }
        return order.compactMap { id in
            guard let root = byID[id] else { return nil }
            return EntityNameRanges.Candidate(entityID: id, kind: root.kind, names: (names[id] ?? []) + [root.name] + root.aliases)
        }
    }

    static func candidates(forEntry entryID: UUID, graph: GraphServices, in context: ModelContext) -> [EntityNameRanges.Candidate] {
        let links = graph.indexer.allLinks(in: context).filter { $0.entryID == entryID }
        guard !links.isEmpty else { return [] }
        let entities = (try? context.fetch(FetchDescriptor<Entity>())) ?? []
        return candidates(forEntry: entryID, links: links, entities: entities)
    }

    static let scheme = "mindlore-entity"

    static func url(for entityID: UUID) -> URL {
        URL(string: "\(scheme)://\(entityID.uuidString)")!
    }

    static func entityID(from url: URL) -> UUID? {
        guard url.scheme == scheme, let host = url.host() else { return nil }
        return UUID(uuidString: host)
    }

    // The entry's text with each name linked and tinted in its entity's colour.
    static func attributed(_ text: String, candidates: [EntityNameRanges.Candidate]) -> AttributedString {
        let kinds = Dictionary(candidates.map { ($0.entityID, $0.kind) }, uniquingKeysWith: { first, _ in first })
        let matches = EntityNameRanges.matches(in: text, candidates: candidates)
        var attributed = AttributedString(text)
        for match in matches {
            guard let range = Range<AttributedString.Index>(match.range, in: attributed) else { continue }
            attributed[range].link = url(for: match.entityID)
            if let kind = kinds[match.entityID] {
                attributed[range].foregroundColor = kind.color
            }
        }
        return attributed
    }
}
