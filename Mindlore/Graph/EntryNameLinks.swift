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
            guard let entityID = link.entityID, let root = root(of: entityID), root.isBrowsable else { continue }
            // Tags are ordinary words ("river"); linking them would turn prose into links. The one
            // exception is a tag the user typed as "#river", which is linked as written.
            if link.kind == .tag || root.kind == .tag {
                guard link.source == .user, let written = link.writtenSurface, written.hasPrefix("#") else { continue }
                if names[root.id] == nil {
                    order.append(root.id)
                    names[root.id] = []
                }
                names[root.id]?.append(written)
                continue
            }
            if names[root.id] == nil {
                order.append(root.id)
                names[root.id] = []
            }
            names[root.id]?.append(contentsOf: [link.writtenSurface, link.surface].compactMap { $0 })
        }
        return order.compactMap { id in
            guard let root = byID[id] else { return nil }
            let extra = root.kind == .tag ? [] : [root.name] + root.aliases
            return EntityNameRanges.Candidate(entityID: id, kind: root.kind, names: (names[id] ?? []) + extra)
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

    // One linked name in the text: where it is (UTF-16, the text view's unit), what it opens,
    // and the colour of its kind.
    struct Link: Equatable {
        let range: NSRange
        let entityID: UUID
        let kind: EntityKind
    }

    static func links(in text: String, candidates: [EntityNameRanges.Candidate]) -> [Link] {
        let kinds = Dictionary(candidates.map { ($0.entityID, $0.kind) }, uniquingKeysWith: { first, _ in first })
        return EntityNameRanges.matches(in: text, candidates: candidates).map { match in
            Link(range: NSRange(match.range, in: text), entityID: match.entityID, kind: kinds[match.entityID] ?? .other)
        }
    }
}
