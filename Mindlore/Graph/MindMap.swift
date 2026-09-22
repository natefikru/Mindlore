import Foundation

// Everything Mind's map draws, read from the store in one pass (GraphServices.mapSnapshot) and
// kept as plain values. Merges and hidden entities are already resolved: `links` points at
// browsable roots only. Entries dated in the future stay in; every builder below filters by its
// own `asOf`, so a cached snapshot never goes stale just because the clock moved.
nonisolated struct MindMapSnapshot: Sendable {
    struct EntityInfo: Equatable, Sendable {
        let id: UUID
        let name: String
        let kind: EntityKind
    }

    struct EntryInfo: Equatable, Sendable {
        let id: UUID
        let date: Date
        let areas: [LifeArea]
        let mood: MoodCategory?
    }

    let entities: [UUID: EntityInfo]
    let links: [EntityGraph.LinkInput]
    let entries: [UUID: EntryInfo]

    static let empty = MindMapSnapshot(entities: [:], links: [], entries: [:])

    // Where a replay starts: the first mention that has already happened.
    func earliestLinkDate(onOrBefore date: Date) -> Date? {
        links.lazy.map(\.entryDate).filter { $0 <= date }.min()
    }
}

// Pure builders over a snapshot. None of them takes a ModelContext, so a replay step, which calls
// them ten times a second, can never fetch.
nonisolated enum MindMap {
    struct Graph {
        let nodes: [GraphSimulation.Node]
        let edges: [EntityGraph.Edge]
        let names: [UUID: String]
    }

    static let entryCap = 100
    static let recentDays = 30

    private static func links(_ snapshot: MindMapSnapshot, asOf: Date) -> [EntityGraph.LinkInput] {
        snapshot.links.filter { $0.entryDate <= asOf }
    }

    // Mentions per entity up to `asOf`, each entry counted once.
    static func mentionCounts(_ snapshot: MindMapSnapshot, asOf: Date) -> [UUID: Int] {
        var entries: [UUID: Set<UUID>] = [:]
        for link in links(snapshot, asOf: asOf) {
            entries[link.entityID, default: []].insert(link.entryID)
        }
        return entries.mapValues(\.count)
    }

    // The entity map as of a date. A node's size and the minimum both read its mentions up to
    // `asOf`, so a replay grows nodes and an entity with no mentions yet isn't there. A node
    // appears because a surviving edge touches it, or because it meets the minimum and kinds on
    // its own; the standalone clause checks kinds itself, since `filtered` only constrains edges.
    static func graph(_ snapshot: MindMapSnapshot, kinds: Set<EntityKind>?, minimumLinkCount: Int, asOf: Date) -> Graph {
        let counts = mentionCounts(snapshot, asOf: asOf)
        let nodeMap = Dictionary(uniqueKeysWithValues: counts.compactMap { id, count -> (UUID, EntityGraph.Node)? in
            snapshot.entities[id].map { (id, EntityGraph.Node(kind: $0.kind, linkCount: count)) }
        })
        let edges = EntityGraph.filtered(
            edges: EntityGraph.build(links: snapshot.links, asOf: asOf),
            nodes: nodeMap,
            kinds: kinds,
            minimumLinkCount: minimumLinkCount
        )
        let edgeNodeIDs = Set(edges.flatMap { [$0.a, $0.b] })
        let standaloneIDs = nodeMap.filter { _, node in
            node.linkCount >= minimumLinkCount && (kinds?.contains(node.kind) ?? true)
        }.keys

        let nodes = edgeNodeIDs.union(standaloneIDs).compactMap { id -> GraphSimulation.Node? in
            nodeMap[id].map { GraphSimulation.Node(id: id, kind: $0.kind, linkCount: $0.linkCount) }
        }
        let names = Dictionary(uniqueKeysWithValues: nodes.compactMap { node in
            snapshot.entities[node.id].map { (node.id, $0.name) }
        })
        return Graph(nodes: GraphSimulation.Node.layoutOrdered(nodes), edges: edges, names: names)
    }

    // Each entity's life area (EntityTally) from its entries up to `asOf`.
    static func primaryAreas(_ snapshot: MindMapSnapshot, asOf: Date) -> [UUID: LifeArea] {
        let values = snapshot.entries.compactMapValues { entry -> EntityTally.Entry<LifeArea>? in
            entry.areas.isEmpty ? nil : EntityTally.Entry(values: entry.areas, date: entry.date)
        }
        return EntityTally.primary(links: links(snapshot, asOf: asOf), values: values)
    }

    // "Mood around": the most common primary-mood category among an entity's entries. A mode,
    // not an average, so Anxious and Low never blur into one colour.
    static func moodAround(_ snapshot: MindMapSnapshot, asOf: Date) -> [UUID: MoodCategory] {
        let values = snapshot.entries.compactMapValues { entry -> EntityTally.Entry<MoodCategory>? in
            entry.mood.map { EntityTally.Entry(values: [$0], date: entry.date) }
        }
        return EntityTally.primary(links: links(snapshot, asOf: asOf), values: values)
    }

    // Entries per entity in the `days` up to and including `asOf`.
    static func recentMentions(_ snapshot: MindMapSnapshot, asOf: Date, days: Int = recentDays) -> [UUID: Int] {
        let start = asOf.addingTimeInterval(-Double(days) * 86_400)
        var entries: [UUID: Set<UUID>] = [:]
        for link in snapshot.links where link.entryDate >= start && link.entryDate <= asOf {
            entries[link.entityID, default: []].insert(link.entryID)
        }
        return entries.mapValues(\.count)
    }

    // Nodes that breathe: anything an entry dated within `days` of `asOf` named. Derived from the
    // links rather than from `Entity.lastLinkedAt` so it needs no fetch, so it uses the same
    // `entryDate` the map's own recency weighting does, and so a replay's halo follows the replay
    // instead of sitting on whoever is recent today.
    //
    // Capped, because a busy week on a large journal would ring eighty nodes and read as a target
    // range rather than as news. The cap keeps the most-mentioned, ties broken by id so the same
    // week always rings the same nodes.
    static func haloed(_ snapshot: MindMapSnapshot, asOf: Date, days: Int = haloDays, cap: Int = haloCap) -> Set<UUID> {
        let recent = recentMentions(snapshot, asOf: asOf, days: days)
        guard recent.count > cap else { return Set(recent.keys) }
        let ranked = recent.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key.uuidString < rhs.key.uuidString : lhs.value > rhs.value
        }
        return Set(ranked.prefix(cap).map(\.key))
    }

    static let haloDays = 7
    static let haloCap = 40

    // Entries as small dots: the newest `cap` entries up to `asOf` that mention something on the
    // map, each tied to those entities. An entry with nothing on the map is left out.
    static func entryNodes(_ snapshot: MindMapSnapshot, onMap: Set<UUID>, asOf: Date, cap: Int = entryCap) -> (nodes: [GraphSimulation.Node], edges: [EntityGraph.Edge]) {
        var entities: [UUID: Set<UUID>] = [:]
        var dates: [UUID: Date] = [:]
        for link in links(snapshot, asOf: asOf) where onMap.contains(link.entityID) {
            entities[link.entryID, default: []].insert(link.entityID)
            dates[link.entryID] = link.entryDate
        }
        let kept = entities.keys.sorted { lhs, rhs in
            let l = dates[lhs] ?? .distantPast, r = dates[rhs] ?? .distantPast
            return l != r ? l > r : lhs.uuidString < rhs.uuidString
        }.prefix(max(0, cap))

        var nodes: [GraphSimulation.Node] = []
        var edges: [EntityGraph.Edge] = []
        for entryID in kept {
            let linked = entities[entryID] ?? []
            nodes.append(GraphSimulation.Node(id: entryID, kind: .other, linkCount: linked.count, isEntry: true))
            let age = asOf.timeIntervalSince(dates[entryID] ?? asOf)
            let recency = pow(0.5, age / EntityGraph.defaultHalfLife)
            for entityID in linked.sorted(by: { $0.uuidString < $1.uuidString }) {
                edges.append(EntityGraph.Edge(entryID, entityID, weight: 1, recency: recency))
            }
        }
        return (nodes, edges)
    }
}
