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
        // The parts of the entry this mention sits in (EntryParts), or nil for the whole entry.
        let parts: Set<Int>?

        init(entryID: UUID, entityID: UUID, entryDate: Date, parts: Set<Int>? = nil) {
            self.entryID = entryID
            self.entityID = entityID
            self.entryDate = entryDate
            self.parts = parts
        }
    }

    struct Edge: Hashable, Sendable {
        let a: UUID
        let b: UUID
        // How much the pair shares: the sum of every shared entry's decayed weight.
        let weight: Double
        // How lately they shared one: the decayed weight of the most recent shared entry alone,
        // 0...1, so a drawing can tell "often, long ago" from "once, yesterday".
        let recency: Double

        // Canonical order so the same pair is never emitted twice under swapped ids.
        init(_ first: UUID, _ second: UUID, weight: Double, recency: Double = 1) {
            if first.uuidString < second.uuidString {
                a = first
                b = second
            } else {
                a = second
                b = first
            }
            self.weight = weight
            self.recency = recency
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
        var latest: [Edge.Key: Double] = [:]
        for (_, entryLinks) in byEntry {
            guard let entryDate = entryLinks.first?.entryDate else { continue }
            // One entity can arrive through several links (a merge, a tag and a name); its parts
            // are all of theirs, and any link placed nowhere makes it the whole entry's.
            var partsByEntity: [UUID: Set<Int>?] = [:]
            for link in entryLinks {
                switch (partsByEntity[link.entityID], link.parts) {
                case (nil, let parts):
                    partsByEntity[link.entityID] = .some(parts)
                case (.some(.some(let existing)), .some(let parts)):
                    partsByEntity[link.entityID] = .some(existing.union(parts))
                default:
                    partsByEntity[link.entityID] = .some(nil)
                }
            }
            let distinctIDs = Array(partsByEntity.keys)
            guard distinctIDs.count >= 2 else { continue }

            let age = asOf.timeIntervalSince(entryDate)
            let weight = pow(0.5, age / halfLife)

            for i in 0..<distinctIDs.count {
                for j in (i + 1)..<distinctIDs.count {
                    // Two names in the same entry connect only when they share a part. A name
                    // with no part is the whole entry's and connects as it always did.
                    if let first = partsByEntity[distinctIDs[i]] ?? nil, let second = partsByEntity[distinctIDs[j]] ?? nil,
                       first.isDisjoint(with: second) {
                        continue
                    }
                    let edge = Edge(distinctIDs[i], distinctIDs[j], weight: 0)
                    totals[edge.key, default: 0] += weight
                    latest[edge.key] = max(latest[edge.key] ?? 0, weight)
                }
            }
        }

        return totals.map { key, weight in Edge(key.a, key.b, weight: weight, recency: latest[key] ?? 0) }
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
