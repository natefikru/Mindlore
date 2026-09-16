import Foundation
import SwiftData
import Observation

// The one graph object the app shares. RootView builds it once and puts it in the environment,
// so views and coordinators use the same indexer, editor, and log instead of building their own.
//
// `revision` moves after every change the graph makes on a view's behalf; screens that show
// entities use it as their refresh key.
@MainActor
@Observable
final class GraphServices {
    let indexer: GraphIndexer
    let editor: GraphEditor
    let drafter: EntityBioDrafter
    let diagnostics: DiagnosticsLog
    private(set) var revision = 0

    // Bio drafts in flight, and what the last attempt for an entity came to this session.
    private(set) var drafting: Set<UUID> = []
    private(set) var bioFailures: [UUID: AIJobFailure] = [:]
    // Nothing in the entries the provider has seen names these; no request was sent.
    private(set) var withoutExcerpts: Set<UUID> = []

    @ObservationIgnored private let resolveText: () -> Result<ResolvedTextGenerator, AIJobFailure>
    @ObservationIgnored private let automaticBiosUsable: () -> Bool
    @ObservationIgnored private var drafts: [UUID: Task<Void, Never>] = [:]

    init(
        diagnostics: DiagnosticsLog = .shared,
        resolveText: @escaping () -> Result<ResolvedTextGenerator, AIJobFailure> = { .failure(AIJobFailure(raw: "settings.aiOff")) },
        automaticBiosUsable: @escaping () -> Bool = { false }
    ) {
        indexer = GraphIndexer(diagnostics: diagnostics)
        editor = GraphEditor(diagnostics: diagnostics)
        drafter = EntityBioDrafter(diagnostics: diagnostics)
        self.diagnostics = diagnostics
        self.resolveText = resolveText
        self.automaticBiosUsable = automaticBiosUsable
    }

    // MARK: - Edits from a page
    //
    // Callers flush EntrySaver first, so no entry has unsaved edits of its own and a plain save
    // can't stamp one by accident.

    func setBio(_ bio: String?, on entityID: UUID, in context: ModelContext) {
        edit(entityID, in: context) {
            editor.setBio(bio, on: $0)
            return .applied
        }
    }

    @discardableResult
    func rename(_ entityID: UUID, to name: String, keepingOldNameAsAlias: Bool = false, force: Bool = false, in context: ModelContext) -> GraphEditor.EditOutcome {
        edit(entityID, in: context) { editor.rename($0, to: name, keepingOldNameAsAlias: keepingOldNameAsAlias, force: force, in: context) }
    }

    @discardableResult
    func setKind(_ kind: EntityKind, on entityID: UUID, in context: ModelContext) -> GraphEditor.EditOutcome {
        edit(entityID, in: context) { editor.setKind(kind, on: $0, in: context) }
    }

    @discardableResult
    func addAlias(_ alias: String, to entityID: UUID, force: Bool = false, in context: ModelContext) -> GraphEditor.EditOutcome {
        edit(entityID, in: context) { editor.addAlias(alias, to: $0, force: force, in: context) }
    }

    func removeAlias(_ alias: String, from entityID: UUID, in context: ModelContext) {
        edit(entityID, in: context) {
            editor.removeAlias(alias, from: $0)
            return .applied
        }
    }

    func setHidden(_ hidden: Bool, on entityID: UUID, in context: ModelContext) {
        edit(entityID, in: context) {
            editor.setHidden(hidden, on: $0)
            return .applied
        }
    }

    // Returns the entity the merged one now stands for, which is where its page should go.
    @discardableResult
    func merge(_ loserID: UUID, into targetID: UUID, in context: ModelContext) -> UUID? {
        guard let loser = editor.entity(withID: loserID, in: context),
              let target = editor.entity(withID: targetID, in: context),
              editor.merge(loser, into: target, in: context) == .merged
        else { return nil }
        revision += 1
        return loser.mergedIntoID
    }

    func unmerge(_ loserID: UUID, in context: ModelContext) {
        guard let loser = editor.entity(withID: loserID, in: context), editor.unmerge(loser, in: context) else { return }
        revision += 1
    }

    // The Review list's "Not the same": takes two entities out of each other's suggestions for
    // good, since `EntityMatcher` would otherwise keep finding the same pair.
    func markNotSame(_ oneID: UUID, _ otherID: UUID, in context: ModelContext) {
        guard let one = editor.entity(withID: oneID, in: context), let other = editor.entity(withID: otherID, in: context) else { return }
        editor.markNotSame(one, as: other)
        save(context)
    }

    // The Review list's "Which one?": links the resolver couldn't tell apart between two or
    // more live, unhidden candidates (5c.4). Each candidate id is resolved through `root(of:)`
    // in case it was merged since the tie was recorded, and a link left with one or zero live
    // candidates that way is quietly cleared, since the tie already answered itself.
    struct UnsureMention: Identifiable {
        struct Candidate: Identifiable {
            let id: UUID
            let name: String
        }
        let mention: MentionRef
        let candidates: [Candidate]
        var id: MentionRef { mention }
    }

    func unsureLinks(in context: ModelContext) -> [UnsureMention] {
        let links = indexer.allLinks(in: context).filter { !$0.unsureAmong.isEmpty }
        guard !links.isEmpty else { return [] }
        var result: [UnsureMention] = []
        var resolvedAutomatically = false
        for link in links {
            guard let entryID = link.entryID else { continue }
            var seen: Set<UUID> = []
            var candidates: [UnsureMention.Candidate] = []
            for id in link.unsureAmong {
                guard let found = editor.entity(withID: id, in: context) else { continue }
                let root = editor.root(of: found, in: context)
                guard !root.hidden, seen.insert(root.id).inserted else { continue }
                candidates.append(.init(id: root.id, name: root.name))
            }
            if candidates.count > 1 {
                result.append(UnsureMention(mention: MentionRef(entryID: entryID, surface: link.surface, kind: link.kind), candidates: candidates))
            } else {
                link.unsureAmong = []
                resolvedAutomatically = true
            }
        }
        if resolvedAutomatically { try? context.save() }
        return result
    }

    // "This is someone else", for one mention. The mention is found again by what it says,
    // because Generate again may have replaced the link since the sheet opened.
    enum RepointTarget: Equatable {
        case existing(UUID)
        case new(name: String)
    }

    enum RepointOutcome: Equatable {
        case applied(UUID)
        // Moved, but a third entity already answers to the name: probably the same one.
        case aliasCollides(entityID: UUID, with: UUID)
        // Moved, and the entity it came from keeps the name for its other mentions. The user
        // just said these are different, so this is never a merge offer.
        case aliasStaysWith(entityID: UUID, owner: UUID)
        case mentionChanged
    }

    func repoint(_ mention: MentionRef, to target: RepointTarget, addingAlias: Bool, in context: ModelContext) -> RepointOutcome {
        guard let link = indexer.allLinks(in: context).first(where: {
            $0.entryID == mention.entryID && $0.surface == mention.surface && $0.kind == mention.kind
        }) else { return .mentionChanged }

        let entity: Entity
        switch target {
        case .existing(let id):
            guard let found = editor.entity(withID: id, in: context) else { return .mentionChanged }
            entity = editor.root(of: found, in: context)
        case .new(let name):
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return .mentionChanged }
            if let existing = editor.entity(answering: trimmed, kind: mention.kind, in: context) {
                entity = existing
            } else {
                entity = Entity(name: trimmed, key: EntityNormalizer.key(for: trimmed, kind: mention.kind), kind: mention.kind)
            }
        }
        // Already pointing there isn't a no-op when the link was unsure (5c.4): the user just
        // confirmed the resolver's own guess, and that still needs to clear unsureAmong and mark
        // the link theirs, or "Which one?" keeps asking about a mention that's already answered.
        guard link.entityID != entity.id || addingAlias || !link.unsureAmong.isEmpty else { return .applied(entity.id) }
        let previous = link.entityID

        let outcome = editor.repoint(link, to: entity, addingAlias: addingAlias, in: context)
        revision += 1
        switch outcome {
        case .applied: return .applied(entity.id)
        case .collides(let other) where other == previous: return .aliasStaysWith(entityID: entity.id, owner: other)
        case .collides(let other): return .aliasCollides(entityID: entity.id, with: other)
        }
    }

    private func edit(_ entityID: UUID, in context: ModelContext, _ change: (Entity) -> GraphEditor.EditOutcome) -> GraphEditor.EditOutcome {
        guard let entity = editor.entity(withID: entityID, in: context) else { return .applied }
        let outcome = change(entity)
        if outcome == .applied { save(context) }
        return outcome
    }

    private func save(_ context: ModelContext) {
        do {
            try context.saveStampingEntries()
        } catch {
            diagnostics.record("graph.saveFailed", ["error": .errorCode(error)])
        }
        revision += 1
    }

    // MARK: - Chips

    // This entry's links by id, one fetch filtered in memory, never through the relationship.
    func chipIndex(for entryID: UUID, in context: ModelContext) -> EntityChipIndex {
        let links = indexer.allLinks(in: context).filter { $0.entryID == entryID }
        let entityIDs = Set(links.compactMap(\.entityID))
        guard !entityIDs.isEmpty else { return .empty }
        let hidden = Set(((try? context.fetch(FetchDescriptor<Entity>(predicate: #Predicate { entityIDs.contains($0.id) }))) ?? [])
            .filter(\.hidden).map(\.id))
        return EntityChipIndex(links: links.compactMap { link in
            link.entityID.map {
                .init(surface: link.surface, kind: link.kind, entityID: $0, inferred: link.inferred, entityHidden: hidden.contains($0), unsure: !link.unsureAmong.isEmpty)
            }
        })
    }

    // MARK: - The picture

    struct GraphData {
        let nodes: [GraphSimulation.Node]
        let edges: [EntityGraph.Edge]
    }

    private struct ResolvedGraph {
        let byID: [UUID: Entity]
        let links: [EntityGraph.LinkInput]
    }

    // One Entity fetch, one link fetch, one Entry fetch for dates, merges and hidden entities
    // resolved through the same in-memory root(of:) walk mentionedWith already uses. localGraph
    // and globalGraph share this so the fetch-once discipline isn't duplicated a third time;
    // mentionedWith is left as its own method, since its "touching id, sorted, capped" step is a
    // different shape from either graph method's output.
    private func resolvedLinks(in context: ModelContext) -> ResolvedGraph {
        let entities = ((try? context.fetch(FetchDescriptor<Entity>())) ?? []).filter { !$0.isDeleted }
        let byID = Dictionary(uniqueKeysWithValues: entities.map { ($0.id, $0) })

        func root(of id: UUID) -> Entity? {
            guard var current = byID[id] else { return nil }
            var seen: Set<UUID> = [current.id]
            while let nextID = current.mergedIntoID, let next = byID[nextID], seen.insert(next.id).inserted {
                current = next
            }
            return current
        }

        let links = indexer.allLinks(in: context)
        let entryIDs = Set(links.compactMap(\.entryID))
        let entryDates = Dictionary(uniqueKeysWithValues:
            (((try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { entryIDs.contains($0.id) }))) ?? [])
                .filter { !$0.isDeleted }
                .map { ($0.id, $0.entryDate) }))

        let inputs: [EntityGraph.LinkInput] = links.compactMap { link in
            guard let linkEntityID = link.entityID, let entryID = link.entryID,
                  let entryDate = entryDates[entryID],
                  let root = root(of: linkEntityID), root.isBrowsable
            else { return nil }
            return .init(entryID: entryID, entityID: root.id, entryDate: entryDate)
        }

        return ResolvedGraph(byID: byID, links: inputs)
    }

    // Depth 1 (direct co-mentions) or 2 (their partners too) around one entity, for the entity
    // page's "Graph" sheet. A subject with no co-occurrence still returns a single-node,
    // zero-edge GraphData, so the view can show the lone subject rather than an error.
    func localGraph(around id: UUID, depth: Int, in context: ModelContext) -> GraphData {
        let resolved = resolvedLinks(in: context)
        let edges = EntityGraph.build(links: resolved.links)
        let nodeIDs = EntityGraph.neighbourhood(of: id, in: edges, depth: depth).union([id])
        let filteredEdges = edges.filter { nodeIDs.contains($0.a) && nodeIDs.contains($0.b) }
        let nodes = nodeIDs.compactMap { nodeID -> GraphSimulation.Node? in
            resolved.byID[nodeID].map { GraphSimulation.Node(id: nodeID, kind: $0.kind, linkCount: $0.linkCount) }
        }
        return GraphData(nodes: nodes, edges: filteredEdges)
    }

    // Every browsable entity as of a given date, for Connections' "Graph" screen. A node appears
    // either because a surviving edge touches it, or because it meets both minimumLinkCount and
    // kinds on its own: the standalone clause's own kind check isn't redundant with `filtered`'s,
    // since `filtered` only constrains edges, and without it a kind toggle would still leave that
    // kind's edgeless nodes on screen.
    func globalGraph(asOf: Date = .now, kinds: Set<EntityKind>?, minimumLinkCount: Int, in context: ModelContext) -> GraphData {
        let resolved = resolvedLinks(in: context)
        let edges = EntityGraph.build(links: resolved.links, asOf: asOf)
        let browsable = resolved.byID.values.filter(\.isBrowsable)
        let nodeMap = Dictionary(uniqueKeysWithValues: browsable.map { ($0.id, EntityGraph.Node(kind: $0.kind, linkCount: $0.linkCount)) })
        let filteredEdges = EntityGraph.filtered(edges: edges, nodes: nodeMap, kinds: kinds, minimumLinkCount: minimumLinkCount)

        // The standalone check reads Entity.linkCount, a persisted, all-time count, the same
        // field the edges' own node map above uses: asOf only ever excludes an edge (build's own
        // date filter), never this count. An entity whose lifetime mentions already clear
        // minimumLinkCount still shows as a dot at any asOf, even one before all of them
        // happened; scrubbing further back can only ever remove edges, never a standalone node
        // that way. Recomputing an asOf-scoped count here would fix that, at the cost of a second
        // pass over every link per scrub; not done without a product call on whether it matters.
        let edgeNodeIDs = Set(filteredEdges.flatMap { [$0.a, $0.b] })
        let standaloneIDs = Set(browsable
            .filter { $0.linkCount >= minimumLinkCount && (kinds?.contains($0.kind) ?? true) }
            .map(\.id))

        let nodes = edgeNodeIDs.union(standaloneIDs).compactMap { nodeID -> GraphSimulation.Node? in
            resolved.byID[nodeID].map { GraphSimulation.Node(id: nodeID, kind: $0.kind, linkCount: $0.linkCount) }
        }
        return GraphData(nodes: nodes, edges: filteredEdges)
    }

    // Logged once per graph screen appearance and once per control change that rebuilds the
    // simulation, never once per frame: settle time over hundreds of ticks is the expected,
    // useful signal, and per-frame draw cost stays a manual, on-device observation instead.
    func recordGraphRendered(nodes: Int, edges: Int, settleMilliseconds: Double) {
        diagnostics.record("graph.rendered", ["nodes": .int(nodes), "edges": .int(edges), "settleMilliseconds": .double(settleMilliseconds)])
    }

    // MARK: - Co-occurrence

    struct CoOccurrence: Identifiable {
        let id: UUID
        let name: String
        let kind: EntityKind
        let weight: Double
    }

    // "Mentioned with" on an entity page. Resolves merges and hidden entities against one
    // in-memory map of every entity, never per-link, since this reads every link in the store:
    // a `root(of:)`/`entity(withID:)` call per link would be a fetch per link, the way `recount`
    // avoids by fetching each table exactly once.
    func mentionedWith(of entityID: UUID, in context: ModelContext, limit: Int = 8) -> [CoOccurrence] {
        let entities = ((try? context.fetch(FetchDescriptor<Entity>())) ?? []).filter { !$0.isDeleted }
        let byID = Dictionary(uniqueKeysWithValues: entities.map { ($0.id, $0) })

        func root(of id: UUID) -> Entity? {
            guard var current = byID[id] else { return nil }
            var seen: Set<UUID> = [current.id]
            while let nextID = current.mergedIntoID, let next = byID[nextID], seen.insert(next.id).inserted {
                current = next
            }
            return current
        }

        guard let subjectRoot = root(of: entityID), subjectRoot.isBrowsable else { return [] }

        let links = indexer.allLinks(in: context)
        let entryIDs = Set(links.compactMap(\.entryID))
        guard !entryIDs.isEmpty else { return [] }
        let entryDates = Dictionary(uniqueKeysWithValues:
            (((try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { entryIDs.contains($0.id) }))) ?? [])
                .filter { !$0.isDeleted }
                .map { ($0.id, $0.entryDate) }))

        let inputs: [EntityGraph.LinkInput] = links.compactMap { link in
            guard let linkEntityID = link.entityID, let entryID = link.entryID,
                  let entryDate = entryDates[entryID],
                  let root = root(of: linkEntityID), root.isBrowsable
            else { return nil }
            return .init(entryID: entryID, entityID: root.id, entryDate: entryDate)
        }

        let edges = EntityGraph.build(links: inputs)
        let touching = edges.compactMap { edge -> (UUID, Double)? in
            if edge.a == subjectRoot.id { return (edge.b, edge.weight) }
            if edge.b == subjectRoot.id { return (edge.a, edge.weight) }
            return nil
        }

        return touching
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .compactMap { id, weight in byID[id].map { CoOccurrence(id: $0.id, name: $0.name, kind: $0.kind, weight: weight) } }
    }

    // MARK: - Bios

    // An entity page appeared. Drafts once, for the kinds that are named word for word, while
    // automatic insights are on: this sends text, so it follows the same switch.
    func pageOpened(_ entityID: UUID, in context: ModelContext) {
        // A failure that retrying can't fix waits for the user's Try again.
        if let failure = bioFailures[entityID], !failure.isRetryable { return }
        guard automaticBiosUsable(), drafts[entityID] == nil,
              let entity = editor.entity(withID: entityID, in: context),
              EntityBioDrafter.automaticKinds.contains(entity.kind),
              entity.bio == nil, entity.bioDraftedAt == nil, EntityBioDrafter.mayWrite(entity),
              let generator = resolveGenerator(for: entityID)
        else { return }
        startDraft(entityID, using: generator, in: context)
    }

    // The user asked. Works for any kind, and brings back AI for a bio they had cleared.
    func draftBio(_ entityID: UUID, in context: ModelContext) {
        guard drafts[entityID] == nil, let entity = editor.entity(withID: entityID, in: context), !entity.isMerged else { return }
        let bringingBack = entity.bioEditedByUser && entity.bio == nil
        guard bringingBack || EntityBioDrafter.mayWrite(entity) else { return }
        // The flag only changes once a request can actually go out.
        guard let generator = resolveGenerator(for: entityID) else { return }
        if bringingBack { entity.bioEditedByUser = false }
        startDraft(entityID, using: generator, in: context)
    }

    // Leaving a page doesn't cancel its draft: the answer is already paid for, and the app
    // never cancels one. This exists so tests can reach the drafter's cancellation path.
    func cancelDrafts() {
        drafts.values.forEach { $0.cancel() }
    }

    // For tests: waits for a running draft to finish.
    func draftFinished(_ entityID: UUID) async {
        await drafts[entityID]?.value
    }

    private func resolveGenerator(for entityID: UUID) -> ResolvedTextGenerator? {
        switch resolveText() {
        case .success(let resolved):
            bioFailures[entityID] = nil
            return resolved
        case .failure(let failure):
            bioFailures[entityID] = failure
            return nil
        }
    }

    private func startDraft(_ entityID: UUID, using generator: ResolvedTextGenerator, in context: ModelContext) {
        drafting.insert(entityID)
        drafts[entityID] = Task {
            let outcome = await drafter.draft(entityID: entityID, using: generator, in: context)
            switch outcome {
            case .failed(let failure): bioFailures[entityID] = failure
            case .noExcerpts: withoutExcerpts.insert(entityID)
            case .drafted, .notEnough: withoutExcerpts.remove(entityID)
            case .skipped, .cancelled: break
            }
            if outcome == .drafted || outcome == .notEnough { revision += 1 }
            drafting.remove(entityID)
            drafts[entityID] = nil
        }
    }

    // Call after the deletion is saved, so the cascade has taken the entries' links with it.
    // Whatever nobody mentions any more goes too.
    func entriesDeleted(in context: ModelContext) {
        indexer.recount(in: context)
        revision += 1
    }

    func insightsDeleted(for entry: Entry, in context: ModelContext) {
        entry.removeInsights(in: context)
        indexer.recount(in: context)
        revision += 1
    }

    // The counters are dated by the entry, so moving one moves them.
    func entryDateChanged(in context: ModelContext) {
        indexer.recount(in: context)
        revision += 1
    }

    // After an insights run wrote this entry. The coordinator saves afterwards, and the bump
    // lets an open sheet pick up the new links.
    func insightsWritten(for entry: Entry, in context: ModelContext) {
        indexer.index(entry, in: context)
        indexer.recount(in: context)
        revision += 1
    }
}
