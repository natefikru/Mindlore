import Foundation
import SwiftData

// Turns the tags, themes, and mentions an entry's insights already hold into entities and
// links. The only thing that writes the graph.
//
// It never saves on the one-entry path: the caller owns that save, because inserting a link
// marks the entry changed and a save that stamped it would move updatedAt for what is not an
// edit to the entry. The sweep saves once itself, excluding every entry it touched.
@MainActor
struct GraphIndexer {
    let diagnostics: DiagnosticsLog

    init(diagnostics: DiagnosticsLog = .shared) {
        self.diagnostics = diagnostics
    }

    // MARK: - Indexing

    // Rebuilds one entry's AI links from its current insights. Caller saves.
    @discardableResult
    func index(_ entry: Entry, in context: ModelContext) -> Int {
        guard let insights = entry.insights else {
            removeGeneratedLinks(for: entry, in: context)
            return 0
        }

        let existing = entry.entityLinks ?? []
        // Read the user's links before deleting anything: a deleted object stays in the
        // relationship array until the next save, so re-reading it here would see ghosts.
        let keptByUser = existing.filter { $0.source == .user }
        let claimed = Set(keptByUser.map { Claim(surface: $0.surface, kind: $0.kind) })
        for link in existing where link.source == .ai { context.delete(link) }

        var candidates = snapshot(in: context)
        var entities = liveEntities(in: context)
        var created = 0
        var linked = 0

        for value in values(of: insights) where !claimed.contains(Claim(surface: value.surface, kind: value.kind)) {
            if EntityResolver.isAmbiguous(value, among: candidates) {
                diagnostics.record("graph.ambiguous", ["id": .id(entry.id), "kind": .string(value.kind.rawValue)])
            }
            let outcome = EntityResolver.resolve(value, among: candidates)
            let target: Entity
            var inferred = false

            switch outcome {
            case .skip:
                continue
            case .existing(let id, let wasInferred, let upgradeKind):
                guard let found = entities[id] else { continue }
                target = found
                inferred = wasInferred
                if let upgradeKind {
                    target.kind = upgradeKind
                    candidates = candidates.map { $0.id == id ? $0.withKind(upgradeKind) : $0 }
                }
            case .create(let key, let kind):
                let entity = Entity(name: value.surface, key: key, kind: kind)
                context.insert(entity)
                entities[entity.id] = entity
                candidates.append(candidate(for: entity))
                target = entity
                created += 1
            }

            let link = EntityLink(surface: value.surface, kind: value.kind, source: .ai, inferred: inferred)
            context.insert(link)
            link.entry = entry
            link.entity = target
            linked += 1
        }

        entry.graphIndexedAt = insights.generatedAt
        diagnostics.record("graph.indexed", [
            "id": .id(entry.id),
            "links": .int(linked),
            "kept": .int(keptByUser.count),
            "created": .int(created),
        ])
        return linked
    }

    // Every entry whose insights are newer than what the graph has seen. On the first launch
    // after this ships every stamp is nil, so this is the backfill. Saves once at the end.
    @discardableResult
    func sweep(in context: ModelContext) -> Int {
        let started = Date.now
        let stale = ((try? context.fetch(FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.createdAt)]))) ?? [])
            .filter { entry in
                guard let generatedAt = entry.insights?.generatedAt else { return entry.graphIndexedAt != nil }
                return entry.graphIndexedAt != generatedAt
            }
        guard !stale.isEmpty else { return 0 }

        var links = 0
        for entry in stale { links += index(entry, in: context) }
        recount(in: context)

        let touched = Set(stale.map(\.persistentModelID))
        do {
            try context.saveStampingEntries(except: touched)
        } catch {
            diagnostics.record("graph.saveFailed", ["error": .errorCode(error)])
            return 0
        }
        diagnostics.record("graph.sweep", [
            "entries": .int(stale.count),
            "links": .int(links),
            "entities": .int((try? context.fetchCount(FetchDescriptor<Entity>())) ?? -1),
            "ms": .int(Int(Date.now.timeIntervalSince(started) * 1000)),
        ])
        return stale.count
    }

    // MARK: - Counters

    // Recomputes every counter from the links, drops links whose entity or entry is gone, and
    // prunes entities nothing points at any more. Runs at the end of a pass, never in the
    // middle of one: an entity pruned between removing an entry's links and re-adding them
    // would come back with a new id.
    func recount(in context: ModelContext) {
        let links = (try? context.fetch(FetchDescriptor<EntityLink>())) ?? []
        var counts: [UUID: (count: Int, first: Date, last: Date)] = [:]

        for link in links {
            guard let entity = link.entity, let entry = link.entry else {
                context.delete(link)
                continue
            }
            let date = entry.entryDate
            if let existing = counts[entity.id] {
                counts[entity.id] = (existing.count + 1, min(existing.first, date), max(existing.last, date))
            } else {
                counts[entity.id] = (1, date, date)
            }
        }

        for entity in liveAndMergedEntities(in: context) {
            let tally = counts[entity.id]
            entity.linkCount = tally?.count ?? 0
            entity.firstLinkedAt = tally?.first
            entity.lastLinkedAt = tally?.last
            // A merge loser has no links by design and is the undo record, so it stays.
            if entity.linkCount == 0 && !entity.confirmedByUser && !entity.isMerged {
                context.delete(entity)
            }
        }
    }

    // MARK: - Removal

    // Drops the links the AI pass created and forgets the entry was ever indexed, so the next
    // insights run rebuilds it. The user's own links stay.
    func removeGeneratedLinks(for entry: Entry, in context: ModelContext) {
        for link in entry.entityLinks ?? [] where link.source == .ai {
            context.delete(link)
        }
        entry.graphIndexedAt = nil
    }

    // MARK: - Reading the insights

    private struct Claim: Hashable {
        let key: String
        let kind: EntityKind

        init(surface: String, kind: EntityKind) {
            self.key = EntityNormalizer.key(for: surface, kind: kind)
            self.kind = kind
        }
    }

    private func values(of insights: EntryInsights) -> [EntityResolver.Value] {
        var seen: Set<Claim> = []
        var values: [EntityResolver.Value] = []
        func add(_ surface: String, _ kind: EntityKind) {
            let value = EntityResolver.Value(surface: surface, kind: kind)
            guard !value.key.isEmpty, seen.insert(Claim(surface: surface, kind: kind)).inserted else { return }
            values.append(value)
        }
        for mention in insights.mentions { add(mention.name, EntityKind(mention.kind)) }
        for tag in insights.tags { add(tag, .tag) }
        for theme in insights.themes { add(theme, .theme) }
        return values
    }

    // MARK: - Entities

    private func liveEntities(in context: ModelContext) -> [UUID: Entity] {
        let live = (try? context.fetch(FetchDescriptor<Entity>(predicate: #Predicate { $0.mergedIntoID == nil }))) ?? []
        return Dictionary(live.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func liveAndMergedEntities(in context: ModelContext) -> [Entity] {
        (try? context.fetch(FetchDescriptor<Entity>())) ?? []
    }

    private func snapshot(in context: ModelContext) -> [EntityResolver.Candidate] {
        liveEntities(in: context).values.map(candidate(for:))
    }

    private func candidate(for entity: Entity) -> EntityResolver.Candidate {
        EntityResolver.Candidate(
            id: entity.id,
            key: entity.key,
            kind: entity.kind,
            aliasKeys: entity.aliases.map { EntityNormalizer.key(for: $0, kind: entity.kind) },
            hidden: entity.hidden,
            kindEditedByUser: entity.kindEditedByUser,
            linkCount: entity.linkCount,
            confirmedByUser: entity.confirmedByUser
        )
    }
}

private extension EntityResolver.Candidate {
    func withKind(_ kind: EntityKind) -> Self {
        .init(
            id: id, key: key, kind: kind, aliasKeys: aliasKeys, hidden: hidden,
            kindEditedByUser: kindEditedByUser, linkCount: linkCount, confirmedByUser: confirmedByUser
        )
    }
}
