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
        var aliases: [String] = []
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
    // The date of every non-draft entry, linked or not: the "of your last M entries" a share is
    // measured against. `entries` only holds the ones something links to.
    let entryDates: [Date]

    init(entities: [UUID: EntityInfo], links: [EntityGraph.LinkInput], entries: [UUID: EntryInfo], entryDates: [Date] = []) {
        self.entities = entities
        self.links = links
        self.entries = entries
        self.entryDates = entryDates
    }

    static let empty = MindMapSnapshot(entities: [:], links: [], entries: [:])

    // Where a replay starts: the first mention that has already happened.
    func earliestLinkDate(onOrBefore date: Date) -> Date? {
        links.lazy.map(\.entryDate).filter { $0 <= date }.min()
    }
}

// Pure builders over a snapshot. None of them takes a ModelContext, so a window or kind change
// never fetches.
nonisolated enum MindMap {
    struct Graph {
        let nodes: [GraphSimulation.Node]
        let edges: [EntityGraph.Edge]
        let names: [UUID: String]
    }

    // A young journal has few names mentioned twice, so every mention draws; from `largeJournal`
    // browsable names on a node needs two in the window, which keeps a busy map readable. The
    // drawer's list still shows everyone (owner, 2026-09-23).
    static let largeJournal = 60

    static func minimumMentions(browsableCount: Int) -> Int {
        browsableCount < largeJournal ? 1 : 2
    }

    // The entity map for a window ending at `asOf`. A node's size and the minimum both read its
    // mentions inside the window, and its edges come from the entries inside it, so a name with
    // nothing in the window isn't there. A node appears because a surviving edge touches it, or
    // because it meets the minimum and kinds on its own; the standalone clause checks kinds
    // itself, since `filtered` only constrains edges.
    static func graph(_ snapshot: MindMapSnapshot, window: MindWindow = .all, kinds: Set<EntityKind>?, minimumLinkCount: Int, asOf: Date) -> Graph {
        let counts = MindStats.counts(snapshot, window: window, asOf: asOf)
        let nodeMap = Dictionary(uniqueKeysWithValues: counts.compactMap { id, count -> (UUID, EntityGraph.Node)? in
            snapshot.entities[id].map { (id, EntityGraph.Node(kind: $0.kind, linkCount: count)) }
        })
        let edges = EntityGraph.filtered(
            edges: EntityGraph.build(links: MindStats.links(snapshot, window: window, asOf: asOf), asOf: asOf),
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
        MindStats.areas(snapshot, window: .all, asOf: asOf)
    }
}
