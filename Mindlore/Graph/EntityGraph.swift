import Foundation

// Entity-to-entity edges are never stored: two entities are connected because a caller-resolved
// set of links says they share an entry, weighted so a recent shared entry counts for more than
// an old one. Nothing here reads SwiftData; the caller (GraphServices) resolves merges and hidden
// entities into plain values first, the same way EntityMatcher never touches an Entity directly.
nonisolated enum EntityGraph {
    struct LinkInput: Equatable, Sendable {
        let entryID: UUID
        let entityID: UUID
        let entryDate: Date

        init(entryID: UUID, entityID: UUID, entryDate: Date) {
            self.entryID = entryID
            self.entityID = entityID
            self.entryDate = entryDate
        }
    }

    struct Edge: Hashable, Sendable {
        let a: UUID
        let b: UUID
        let weight: Double

        // Canonical order so the same pair is never emitted twice under swapped ids.
        init(_ first: UUID, _ second: UUID, weight: Double) {
            if first.uuidString < second.uuidString {
                a = first
                b = second
            } else {
                a = second
                b = first
            }
            self.weight = weight
        }

        struct Key: Hashable {
            let a: UUID
            let b: UUID
        }

        var key: Key { Key(a: a, b: b) }
    }

    // Phase 7's local and global graphs both weight by a 90-day half-life.
    static let defaultHalfLife: TimeInterval = 90 * 86400

    static func build(links: [LinkInput], asOf: Date = .now, halfLife: TimeInterval = defaultHalfLife) -> [Edge] {
        let byEntry = Dictionary(grouping: links.filter { $0.entryDate <= asOf }, by: \.entryID)

        var totals: [Edge.Key: Double] = [:]
        for (_, entryLinks) in byEntry {
            guard let entryDate = entryLinks.first?.entryDate else { continue }
            let distinctIDs = Array(Set(entryLinks.map(\.entityID)))
            guard distinctIDs.count >= 2 else { continue }

            let age = asOf.timeIntervalSince(entryDate)
            let weight = pow(0.5, age / halfLife)

            for i in 0..<distinctIDs.count {
                for j in (i + 1)..<distinctIDs.count {
                    let edge = Edge(distinctIDs[i], distinctIDs[j], weight: 0)
                    totals[edge.key, default: 0] += weight
                }
            }
        }

        return totals.map { key, weight in Edge(key.a, key.b, weight: weight) }
    }

    static func neighbourhood(of id: UUID, in edges: [Edge], depth: Int) -> Set<UUID> {
        guard depth > 0 else { return [] }

        var adjacency: [UUID: [UUID]] = [:]
        for edge in edges {
            adjacency[edge.a, default: []].append(edge.b)
            adjacency[edge.b, default: []].append(edge.a)
        }

        var found: Set<UUID> = []
        var frontier: Set<UUID> = [id]
        for _ in 0..<depth {
            let next = Set(frontier.flatMap { adjacency[$0] ?? [] }).subtracting(found).subtracting([id])
            guard !next.isEmpty else { break }
            found.formUnion(next)
            frontier = next
        }
        return found
    }

    struct Node: Sendable {
        let kind: EntityKind
        let linkCount: Int

        init(kind: EntityKind, linkCount: Int) {
            self.kind = kind
            self.linkCount = linkCount
        }
    }

    static func filtered(edges: [Edge], nodes: [UUID: Node], kinds: Set<EntityKind>?, minimumLinkCount: Int) -> [Edge] {
        func keeps(_ id: UUID) -> Bool {
            guard let node = nodes[id] else { return false }
            guard node.linkCount >= minimumLinkCount else { return false }
            guard let kinds else { return true }
            return kinds.contains(node.kind)
        }
        return edges.filter { keeps($0.a) && keeps($0.b) }
    }
}
