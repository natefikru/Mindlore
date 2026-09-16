import Foundation
import SwiftData

// Every change the user makes to the graph. Each one marks the entity as theirs, so an
// entity they have touched survives losing its last link, and each one that changes who
// points at what recounts afterwards.
@MainActor
struct GraphEditor {
    let diagnostics: DiagnosticsLog
    private let indexer: GraphIndexer

    init(diagnostics: DiagnosticsLog = .shared) {
        self.diagnostics = diagnostics
        self.indexer = GraphIndexer(diagnostics: diagnostics)
    }

    // A rename or a new alias can land on a name something else already answers to. Rather
    // than leave two entities the resolver has to choose between, the edit stops and offers
    // the merge that was probably meant.
    enum EditOutcome: Equatable {
        case applied
        case collides(with: UUID)
    }

    // MARK: - Editing one entity

    // `keepingOldNameAsAlias` skips the collision check for the old name: it already belonged to
    // this entity, so nothing else can be answering to it. `force` pushes the edit through a
    // collision with something else on purpose ("a different person also called {name}"), and
    // marks the two `notSameAs` so the Review list doesn't immediately re-suggest merging them.
    @discardableResult
    func rename(_ entity: Entity, to name: String, keepingOldNameAsAlias: Bool = false, force: Bool = false, in context: ModelContext) -> EditOutcome {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .applied }
        let key = EntityNormalizer.key(for: trimmed, kind: entity.kind)
        if let clash = entityAnswering(to: key, kind: entity.kind, excluding: entity, in: context) {
            guard force else { return .collides(with: clash.id) }
            markNotSame(entity, as: clash)
            diagnostics.record("graph.collisionForced", ["id": .id(entity.id), "other": .id(clash.id)])
        }
        let oldName = entity.name
        entity.name = trimmed
        entity.key = key
        if keepingOldNameAsAlias, !oldName.isEmpty, key != EntityNormalizer.key(for: oldName, kind: entity.kind),
           !entity.aliases.contains(oldName) {
            entity.aliases.append(oldName)
        }
        claim(entity)
        diagnostics.record("graph.entityEdited", ["id": .id(entity.id), "field": "name"])
        return .applied
    }

    // A mention stays a mention and a label stays a label: a person can become a place, and a
    // tag a theme, but a person never a tag. Labels match only their own kind, so crossing over
    // would strand the entity's links.
    static func kinds(changeableFrom kind: EntityKind) -> [EntityKind] {
        switch kind {
        case .tag, .theme: [.tag, .theme]
        default: [.person, .place, .organization, .project, .event, .other]
        }
    }

    @discardableResult
    func setKind(_ kind: EntityKind, on entity: Entity, in context: ModelContext) -> EditOutcome {
        guard entity.kind != kind, Self.kinds(changeableFrom: entity.kind).contains(kind) else { return .applied }
        // Keys are kind-sensitive, so every name is checked again under the new kind.
        for surface in [entity.name] + entity.aliases {
            let key = EntityNormalizer.key(for: surface, kind: kind)
            if let clash = entityAnswering(to: key, kind: kind, excluding: entity, in: context) {
                return .collides(with: clash.id)
            }
        }
        entity.kind = kind
        // Keyed again under the new kind, or the resolver and the collision check stop
        // agreeing about what this answers to.
        entity.key = EntityNormalizer.key(for: entity.name, kind: kind)
        // From here on the extraction never changes it back.
        entity.kindEditedByUser = true
        claim(entity)
        diagnostics.record("graph.entityEdited", ["id": .id(entity.id), "field": "kind", "kind": .string(kind.rawValue)])
        return .applied
    }

    @discardableResult
    func addAlias(_ alias: String, to entity: Entity, force: Bool = false, in context: ModelContext) -> EditOutcome {
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .applied }
        let key = EntityNormalizer.key(for: trimmed, kind: entity.kind)
        guard !key.isEmpty else { return .applied }
        // Already answers to it, under this spelling or another.
        guard !keys(of: entity).contains(key) else { return .applied }
        if let clash = entityAnswering(to: key, kind: entity.kind, excluding: entity, in: context) {
            guard force else { return .collides(with: clash.id) }
            markNotSame(entity, as: clash)
            diagnostics.record("graph.collisionForced", ["id": .id(entity.id), "other": .id(clash.id)])
        }
        entity.aliases.append(trimmed)
        claim(entity)
        diagnostics.record("graph.entityEdited", ["id": .id(entity.id), "field": "alias", "aliases": .int(entity.aliases.count)])
        return .applied
    }

    func removeAlias(_ alias: String, from entity: Entity) {
        entity.aliases.removeAll { $0 == alias }
        claim(entity)
        diagnostics.record("graph.entityEdited", ["id": .id(entity.id), "field": "alias", "aliases": .int(entity.aliases.count)])
    }

    // The user's own words. Once they write here, no AI draft replaces it.
    func setBio(_ bio: String?, on entity: Entity) {
        let trimmed = bio?.trimmingCharacters(in: .whitespacesAndNewlines)
        entity.bio = (trimmed?.isEmpty ?? true) ? nil : trimmed
        entity.bioWasGenerated = false
        entity.bioEditedByUser = true
        claim(entity)
        diagnostics.record("graph.entityEdited", ["id": .id(entity.id), "field": "bio"])
    }

    // Hiding keeps the entity resolving, so what was hidden stays hidden instead of coming
    // back under a new id the next time it is mentioned.
    func setHidden(_ hidden: Bool, on entity: Entity) {
        entity.hidden = hidden
        claim(entity)
        diagnostics.record("graph.hidden", ["id": .id(entity.id), "hidden": .bool(hidden)])
    }

    func markNotSame(_ entity: Entity, as other: Entity) {
        if !entity.notSameAs.contains(other.id) { entity.notSameAs.append(other.id) }
        if !other.notSameAs.contains(entity.id) { other.notSameAs.append(entity.id) }
        claim(entity)
        claim(other)
        diagnostics.record("graph.suggestionDismissed", ["id": .id(entity.id), "other": .id(other.id)])
    }

    // MARK: - Merging

    enum MergeOutcome: Equatable {
        case merged
        // Merging something into itself, or into something already merged into it.
        case refused
    }

    @discardableResult
    func merge(_ loser: Entity, into target: Entity, in context: ModelContext) -> MergeOutcome {
        // Merging into a loser means merging into whatever it stands for now.
        let winner = root(of: target, in: context)
        guard winner.id != loser.id, !loser.isMerged else { return .refused }
        guard root(of: winner, in: context).id != loser.id else { return .refused }
        register(winner, in: context)
        // The user chose it, so it is no longer something they want out of sight.
        winner.hidden = false

        // By id, not through the relationship: mid-batch a relationship can read nil, and a
        // predicate that reaches through one is worse.
        let moved = indexer.allLinks(in: context).filter { $0.entityID == loser.id }
        for link in moved { link.moveForMerge(to: winner) }

        // Everything the loser answered to, that the winner does not answer to already, minus
        // anything the loser was itself given by an earlier merge. Those belong to whoever
        // brought them, so unmerging this one does not take away someone else's name.
        let deeper = merged(into: loser, in: context)
        let inherited = Set(deeper.flatMap(\.contributedAliases))
        let existing = Set(keys(of: winner))
        var contributed: [String] = []
        for surface in [loser.name] + loser.aliases where !inherited.contains(surface) {
            let key = EntityNormalizer.key(for: surface, kind: winner.kind)
            guard !key.isEmpty, !existing.contains(key), !contributed.contains(surface) else { continue }
            contributed.append(surface)
        }
        winner.aliases.append(contentsOf: contributed)
        loser.contributedAliases = contributed

        loser.mergedIntoID = winner.id
        loser.mergedAt = .now
        // Anything that pointed at the loser now points at the winner, so no pointer is ever
        // more than one hop from a live entity. Their own links keep their own birthplaces,
        // so unmerging any of them still returns exactly what it brought.
        for entity in deeper {
            entity.mergedIntoID = winner.id
        }
        // Their names move with them, so the loser does not keep answering to a name it is
        // no longer the owner of once it is unmerged.
        loser.aliases.removeAll { inherited.contains($0) }
        claim(winner)
        claim(loser)
        // Made real before counting, so the next merge sees where these links ended up.
        save(context, touchedBy: moved)

        indexer.recount(in: context)
        save(context, touchedBy: moved)
        diagnostics.record("graph.merged", [
            "id": .id(winner.id), "loser": .id(loser.id), "links": .int(moved.count), "aliases": .int(contributed.count),
        ])
        return .merged
    }

    @discardableResult
    func unmerge(_ loser: Entity, in context: ModelContext) -> Bool {
        guard let winnerID = loser.mergedIntoID else { return false }
        let winner = entity(withID: winnerID, in: context)

        // Exactly the links that were born on this entity, wherever they have ended up since.
        // Filtered in memory: a predicate comparing an optional UUID is not dependable.
        let born = indexer.allLinks(in: context).filter { $0.originalEntityID == loser.id }
        for link in born { link.restore(to: loser) }

        // Exactly the aliases it brought, and nothing the winner already had.
        if let winner {
            winner.aliases.removeAll { loser.contributedAliases.contains($0) }
        }
        loser.contributedAliases = []
        loser.mergedIntoID = nil
        loser.mergedAt = nil
        claim(loser)
        save(context, touchedBy: born)

        indexer.recount(in: context)
        save(context, touchedBy: born)
        diagnostics.record("graph.unmerged", ["id": .id(loser.id), "links": .int(born.count)])
        return true
    }

    // MARK: - One mention at a time

    // "This is someone else." The link becomes the user's, so reindexing leaves it alone, and
    // the entity it now points at is theirs too. Adding the alias fixes every future mention
    // of the same name; without it, only this one moves.
    // Returns what happened to the alias, so the screen can say why a name it offered to fix
    // for good could not be: something else still answers to it.
    @discardableResult
    func repoint(_ link: EntityLink, to entity: Entity, addingAlias: Bool, in context: ModelContext) -> EditOutcome {
        register(entity, in: context)

        let surface = link.surface
        link.repoint(to: entity)
        claim(entity)
        // Recount before the alias, not after: the entity this was taken off may have nothing
        // left and be gone, and a name nobody answers to any more is not a collision.
        save(context, touchedBy: [link])
        indexer.recount(in: context)
        let outcome = addingAlias ? addAlias(surface, to: entity, in: context) : .applied
        save(context, touchedBy: [link])

        diagnostics.record("graph.repointed", ["id": .id(entity.id), "alias": .bool(addingAlias)])
        return outcome
    }

    // MARK: - Lookups

    // What a merged entity stands for now. Pointers are flattened on merge, so this is one
    // step, but it follows a chain defensively rather than trusting that forever.
    func root(of entity: Entity, in context: ModelContext) -> Entity {
        var current = entity
        var seen: Set<UUID> = [entity.id]
        while let nextID = current.mergedIntoID, let next = self.entity(withID: nextID, in: context) {
            guard seen.insert(next.id).inserted else { break }
            current = next
        }
        return current
    }

    func suggestions(in context: ModelContext) -> [EntityMatcher.Suggestion] {
        let browsable = ((try? context.fetch(FetchDescriptor<Entity>())) ?? []).filter(\.isBrowsable)
        return EntityMatcher.suggestions(among: browsable.map {
            .init(id: $0.id, key: $0.key, kind: $0.kind, linkCount: $0.linkCount, notSameAs: $0.notSameAs)
        })
    }

    // The live entity a typed name would land on, so a new name never duplicates one.
    func entity(answering name: String, kind: EntityKind, in context: ModelContext) -> Entity? {
        let key = EntityNormalizer.key(for: name, kind: kind)
        return entityAnswering(to: key, kind: kind, excluding: nil, in: context)
    }

    func entity(withID id: UUID, in context: ModelContext) -> Entity? {
        var descriptor = FetchDescriptor<Entity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    // MARK: - Private

    private func claim(_ entity: Entity) {
        entity.confirmedByUser = true
    }

    // A plain save, which stamps nothing it shouldn't only because every caller has flushed the
    // entry saver first; the only unsaved change here is the new entity.
    //
    // An existing link silently refuses an entity the store has never seen, leaving it with
    // no entity at all, which the next recount cleans up as garbage. Anything about to
    // receive links has to be in the store first.
    private func register(_ entity: Entity, in context: ModelContext) {
        guard entity.modelContext == nil else { return }
        context.insert(entity)
        try? context.save()
    }

    // Moving a link marks its entry as changed, but moving a link is not an edit to the entry.
    // Every save here exempts the entries whose links moved, the same rule the sweep follows.
    private func save(_ context: ModelContext, touchedBy links: [EntityLink]) {
        let ids = Set(links.compactMap(\.entryID))
        let touched = ids.isEmpty ? [] : Set(
            ((try? context.fetch(FetchDescriptor<Entry>())) ?? [])
                .filter { ids.contains($0.id) }
                .map(\.persistentModelID)
        )
        try? context.saveStampingEntries(except: touched)
    }

    private func keys(of entity: Entity) -> [String] {
        ([entity.name] + entity.aliases).map { EntityNormalizer.key(for: $0, kind: entity.kind) }
    }

    private func entityAnswering(to key: String, kind: EntityKind, excluding entity: Entity?, in context: ModelContext) -> Entity? {
        guard !key.isEmpty else { return nil }
        let live = ((try? context.fetch(FetchDescriptor<Entity>(
            predicate: #Predicate { $0.mergedIntoID == nil },
            sortBy: [SortDescriptor(\.createdAt), SortDescriptor(\.name)]
        ))) ?? [])
        return live.first { other in
            other.id != entity?.id
                && Self.sameFamily(other.kind, kind)
                && keys(of: other).contains(key)
        }
    }

    // In memory: comparing the optional mergedIntoID with a plain UUID inside a predicate can
    // quietly return the wrong set (tasks/lessons.md).
    // The resolver's rule: a kind meets itself, and `other` meets any named kind, never a label.
    private static func sameFamily(_ a: EntityKind, _ b: EntityKind) -> Bool {
        if a == b { return true }
        if EntityResolver.isLabel(a) || EntityResolver.isLabel(b) { return false }
        return a == .other || b == .other
    }

    private func merged(into entity: Entity, in context: ModelContext) -> [Entity] {
        let id = entity.id
        return ((try? context.fetch(FetchDescriptor<Entity>())) ?? []).filter { $0.mergedIntoID == id && !$0.isDeleted }
    }
}
