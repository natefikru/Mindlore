import Foundation
import SwiftData

// Turns the tags and mentions an entry's insights already hold into entities and
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

    // What indexing needs to know about the store, read once. The sweep shares one across every
    // entry: fetching all links and entities per entry made a first launch grow with the square
    // of the journal, two minutes for three thousand entries.
    final class Batch {
        var linksByEntry: [UUID: [EntityLink]]
        var candidates: [EntityResolver.Candidate]
        var entities: [UUID: Entity]
        var created = 0

        init(linksByEntry: [UUID: [EntityLink]], candidates: [EntityResolver.Candidate], entities: [UUID: Entity]) {
            self.linksByEntry = linksByEntry
            self.candidates = candidates
            self.entities = entities
        }
    }

    func batch(in context: ModelContext) -> Batch {
        let entities = liveEntities(in: context)
        return Batch(
            linksByEntry: Dictionary(grouping: allLinks(in: context).filter { $0.entryID != nil }, by: { $0.entryID! }),
            candidates: entities.values.map(candidate(for:)),
            entities: entities
        )
    }

    // Rebuilds one entry's AI links from its current insights. Caller saves.
    @discardableResult
    func index(_ entry: Entry, in context: ModelContext) -> Int {
        index(entry, in: context, batch: batch(in: context), recordEach: true)
    }

    // The sweep reports one summary instead of a line per entry: a first launch over a large
    // journal would otherwise bury the device log in thousands of them.
    private func index(_ entry: Entry, in context: ModelContext, batch: Batch, recordEach: Bool) -> Int {
        guard let insights = entry.insights else {
            removeGeneratedLinks(for: entry, in: context)
            batch.linksByEntry[entry.id] = batch.linksByEntry[entry.id]?.filter { $0.source != .ai }
            return 0
        }

        let existing = batch.linksByEntry[entry.id] ?? []
        // Read the user's links before deleting anything: a deleted object stays in the
        // relationship array until the next save, so re-reading it here would see ghosts.
        let keptByUser = existing.filter { $0.source == .user }
        let claimed = Set(keptByUser.map { Claim(surface: $0.surface, kind: $0.kind) })
        // Where a merge took each link from, kept across the rebuild. Without this, running AI
        // again on a merged entry quietly makes the merge permanent: the new link has no
        // birthplace, so unmerging finds nothing to give back.
        var origins: [Claim: UUID] = [:]
        for link in existing where link.source == .ai {
            if let origin = link.originalEntityID {
                origins[Claim(surface: link.surface, kind: link.kind)] = origin
            }
            context.delete(link)
        }
        var kept = keptByUser
        let writtenSurfaces: [Claim: String] = Dictionary(
            insights.mentions.compactMap { mention in
                mention.writtenSurface.map { (Claim(surface: mention.name, kind: EntityKind(mention.kind)), $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )

        var created = 0
        var linked = 0

        for value in values(of: insights) where !isClaimed(Claim(surface: value.surface, kind: value.kind), by: claimed) {
            if EntityResolver.isAmbiguous(value, among: batch.candidates) {
                diagnostics.record("graph.ambiguous", ["id": .id(entry.id), "kind": .string(value.kind.rawValue)])
            }
            let tiedAmong = EntityResolver.tied(value, among: batch.candidates)
            let outcome = EntityResolver.resolve(value, among: batch.candidates)
            let target: Entity
            var inferred = false

            switch outcome {
            case .skip:
                continue
            case .existing(let id, let wasInferred, let upgradeKind):
                guard let found = batch.entities[id] else { continue }
                target = found
                inferred = wasInferred
                if let upgradeKind {
                    target.kind = upgradeKind
                    // Keys are kind-sensitive: honorifics only come off a person's name.
                    target.key = EntityNormalizer.key(for: target.name, kind: upgradeKind)
                    batch.candidates = batch.candidates.map { $0.id == id ? candidate(for: found) : $0 }
                }
            case .create(let key, let kind):
                let entity = Entity(name: value.surface, key: key, kind: kind)
                context.insert(entity)
                batch.entities[entity.id] = entity
                batch.candidates.append(candidate(for: entity))
                target = entity
                created += 1
            }

            let link = EntityLink(surface: value.surface, kind: value.kind, source: .ai, inferred: inferred)
            context.insert(link)
            link.attach(to: entry, entity: target)
            link.originalEntityID = origins[Claim(surface: value.surface, kind: value.kind)]
            link.writtenSurface = writtenSurfaces[Claim(surface: value.surface, kind: value.kind)]
            link.unsureAmong = tiedAmong
            kept.append(link)
            linked += 1
        }
        batch.linksByEntry[entry.id] = kept

        entry.graphIndexedAt = insights.generatedAt
        batch.created += created
        guard recordEach else { return linked }
        diagnostics.record("graph.indexed", [
            "id": .id(entry.id),
            "links": .int(linked),
            "kept": .int(keptByUser.count),
            "created": .int(created),
        ])
        return linked
    }

    // Every entry whose insights are newer than what the graph has seen. On the first launch
    // after this ships every stamp is nil, so this is the backfill.
    @discardableResult
    func sweep(in context: ModelContext) -> Int {
        let started = Date.now
        let stale = staleEntries(in: context)
        guard let indexed = indexAndSave(stale, in: context), repair(in: context) else { return 0 }
        recordSweep(stale.count, indexed, chunks: 1, since: started, in: context)
        return stale.count
    }

    // The same pass for launch, a chunk at a time with a pause between, so the screen can
    // animate while a large journal is indexed instead of freezing. Each chunk reads the store
    // afresh and saves, so a sweep that is interrupted, or that something else writes to
    // between chunks, picks up where it left off.
    @discardableResult
    func sweep(in context: ModelContext, chunkSize: Int = 100, onProgress: (_ done: Int, _ total: Int) -> Void) async -> Int {
        let started = Date.now
        let ids = staleEntries(in: context).map(\.id)
        var total = Indexed()
        var done = 0
        var chunks = 0
        onProgress(0, ids.count)
        // Let the screen draw its progress before the first chunk holds the main thread.
        if !ids.isEmpty { await Task.yield() }
        while done < ids.count {
            // By id, fetched afresh: an entry deleted and saved while this sweep waited is
            // detached, not marked deleted, and reading its insights would crash.
            let chunk = Set(ids[done..<min(done + chunkSize, ids.count)])
            let entries = (try? context.fetch(FetchDescriptor<Entry>(
                predicate: #Predicate { chunk.contains($0.id) },
                sortBy: [SortDescriptor(\.createdAt)]
            ))) ?? []
            guard let indexed = indexAndSave(entries, in: context) else { return done }
            total.links += indexed.links
            total.created += indexed.created
            done += chunk.count
            chunks += 1
            onProgress(done, ids.count)
            await Task.yield()
        }
        guard repair(in: context) else { return done }
        recordSweep(ids.count, total, chunks: chunks, since: started, in: context)
        return ids.count
    }

    private struct Indexed {
        var links = 0
        var created = 0
    }

    private func staleEntries(in context: ModelContext) -> [Entry] {
        ((try? context.fetch(FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []).filter { entry in
            guard let generatedAt = entry.insights?.generatedAt else { return entry.graphIndexedAt != nil }
            return entry.graphIndexedAt != generatedAt
        }
    }

    // Indexes these entries against one read of the store and saves without stamping them.
    private func indexAndSave(_ entries: [Entry], in context: ModelContext) -> Indexed? {
        let live = entries.filter { !$0.isDeleted }
        guard !live.isEmpty else { return Indexed() }
        let shared = batch(in: context)
        var indexed = Indexed()
        for entry in live { indexed.links += index(entry, in: context, batch: shared, recordEach: false) }
        indexed.created = shared.created
        return save(context, exempting: Set(live.map(\.id))) ? indexed : nil
    }

    // Always runs, even with nothing stale: this is the only place counters are repaired and
    // links stranded by an interrupted edit are cleared, and in steady state nothing is stale.
    private func repair(in context: ModelContext) -> Bool {
        recount(in: context)
        let stranded = removeOrphanedLinks(in: context)
        return save(context, exempting: stranded)
    }

    // Removing a stranded link marks its entry changed too, and that is no edit either.
    private func save(_ context: ModelContext, exempting entryIDs: Set<UUID>) -> Bool {
        let touched = entryIDs.isEmpty ? [] : Set(
            ((try? context.fetch(FetchDescriptor<Entry>())) ?? []).filter { entryIDs.contains($0.id) }.map(\.persistentModelID)
        )
        do {
            try context.saveStampingEntries(except: touched)
            return true
        } catch {
            diagnostics.record("graph.saveFailed", ["error": .errorCode(error)])
            return false
        }
    }

    private func recordSweep(_ entries: Int, _ indexed: Indexed, chunks: Int, since started: Date, in context: ModelContext) {
        guard entries > 0 else { return }
        diagnostics.record("graph.sweep", [
            "entries": .int(entries),
            "links": .int(indexed.links),
            "created": .int(indexed.created),
            "chunks": .int(chunks),
            "entities": .int((try? context.fetchCount(FetchDescriptor<Entity>())) ?? -1),
            "ms": .int(Int(Date.now.timeIntervalSince(started) * 1000)),
        ])
    }

    // What this journal already calls things, for the next insights request. Nil when the graph
    // has not been built yet, which is different from a graph with nothing worth sending: only
    // the first should fall back to counting tags off the insights themselves.
    //
    // Hidden entities are left out because the user does not want to see them, and merge losers
    // because their winner already stands for them. Each list mixes the most used names with the
    // most recent, so someone new in a long journal, the likeliest to be misspelled, still makes
    // the cut. Lists for switched-off sections are never fetched.
    func vocabulary(in context: ModelContext, sections: InsightSections = InsightSections()) -> InsightsPromptBuilder.JournalVocabulary? {
        guard ((try? context.fetchCount(FetchDescriptor<Entity>())) ?? 0) > 0 else { return nil }

        let tag = EntityKind.tag.rawValue
        var vocabulary = InsightsPromptBuilder.JournalVocabulary()
        if sections.tags {
            vocabulary.tags = mix(#Predicate { !$0.hidden && $0.mergedIntoID == nil && $0.kindRaw == tag },
                                  cap: InsightsPromptBuilder.maxExistingTags, in: context).map(\.name)
        }
        if sections.mentions {
            vocabulary.named = mix(#Predicate { !$0.hidden && $0.mergedIntoID == nil && $0.kindRaw != tag },
                                   cap: InsightsPromptBuilder.maxKnownEntities, in: context).map { entity in
                // An `other` nobody has settled goes without a kind, so the model can say what it is.
                let settled = entity.kind != .other || entity.kindEditedByUser
                return .init(name: entity.name, kind: settled ? MentionKind(rawValue: entity.kind.rawValue) : nil)
            }
        }
        return vocabulary
    }

    // Seven in ten of the cap by use, the rest by recency, without repeats.
    private func mix(_ predicate: Predicate<Entity>, cap: Int, in context: ModelContext) -> [Entity] {
        let byUse = cap * 7 / 10
        var used = FetchDescriptor<Entity>(predicate: predicate, sortBy: [SortDescriptor(\.linkCount, order: .reverse), SortDescriptor(\.createdAt)])
        used.fetchLimit = byUse
        var recent = FetchDescriptor<Entity>(predicate: predicate, sortBy: [SortDescriptor(\.lastLinkedAt, order: .reverse), SortDescriptor(\.createdAt)])
        recent.fetchLimit = cap

        var picked = (try? context.fetch(used)) ?? []
        var ids = Set(picked.map(\.id))
        for entity in (try? context.fetch(recent)) ?? [] where picked.count < cap && ids.insert(entity.id).inserted {
            picked.append(entity)
        }
        return picked
    }

    // MARK: - Counters

    // Recomputes every counter from the links and prunes entities nothing points at any more.
    // Runs at the end of a pass, never in the middle of one: an entity pruned between removing
    // an entry's links and re-adding them would come back with a new id.
    //
    // It never deletes a link. A relationship can read nil part-way through an unsaved batch,
    // and counting is not the place to decide that a link is rubbish: the sweep does that at
    // launch, against what is actually on disk.
    func recount(in context: ModelContext) {
        // Dates by entry id, so counting reads no relationships at all.
        let dates = Dictionary(
            ((try? context.fetch(FetchDescriptor<Entry>())) ?? []).map { ($0.id, $0.entryDate) },
            uniquingKeysWith: { first, _ in first }
        )
        let links = allLinks(in: context)
        var counts: [UUID: (count: Int, first: Date, last: Date)] = [:]

        for link in links {
            guard let entityID = link.entityID, let entryID = link.entryID, let date = dates[entryID] else { continue }
            if let existing = counts[entityID] {
                counts[entityID] = (existing.count + 1, min(existing.first, date), max(existing.last, date))
            } else {
                counts[entityID] = (1, date, date)
            }
        }

        // The candidate a tie didn't pick has no link of its own yet, but pruning it would
        // orphan the tie: "Which one?" would answer itself with nothing left to choose between.
        let tiedCandidates = Set(links.flatMap(\.unsureAmong))

        for entity in liveAndMergedEntities(in: context) {
            let tally = counts[entity.id]
            entity.linkCount = tally?.count ?? 0
            entity.firstLinkedAt = tally?.first
            entity.lastLinkedAt = tally?.last
            // Kept even with nothing pointing at it: anything the user touched, anything they
            // hid (or it would come back the next time it is mentioned), a merge loser (the undo
            // record), and a tie's other candidate.
            if entity.linkCount == 0 && !entity.confirmedByUser && !entity.hidden && !entity.isMerged
                && !tiedCandidates.contains(entity.id) {
                context.delete(entity)
            }
        }
    }

    // A link whose entity or entry is gone points at nothing and can never be shown. Only the
    // launch sweep does this, where every change has already been saved.
    // Returns the entries whose links it removed, so the save can leave them unstamped.
    @discardableResult
    func removeOrphanedLinks(in context: ModelContext) -> Set<UUID> {
        let entities = Set(((try? context.fetch(FetchDescriptor<Entity>())) ?? []).map(\.id))
        let entries = Set(((try? context.fetch(FetchDescriptor<Entry>())) ?? []).map(\.id))
        var touched: Set<UUID> = []
        for link in allLinks(in: context) {
            guard let entityID = link.entityID, let entryID = link.entryID,
                  entities.contains(entityID), entries.contains(entryID) else {
                if let entryID = link.entryID { touched.insert(entryID) }
                context.delete(link)
                continue
            }
        }
        return touched
    }

    // MARK: - Removal

    // Drops the links the AI pass created and forgets the entry was ever indexed, so the next
    // insights run rebuilds it. The user's own links stay.
    func removeGeneratedLinks(for entry: Entry, in context: ModelContext) {
        for link in allLinks(in: context) where link.entryID == entry.id && link.source == .ai {
            context.delete(link)
        }
        entry.graphIndexedAt = nil
    }

    func allLinks(in context: ModelContext) -> [EntityLink] {
        ((try? context.fetch(FetchDescriptor<EntityLink>())) ?? []).filter { !$0.isDeleted }
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

    // A user link claims a regenerated value with the same key even if the model now types it
    // differently ("Sarah" as a person last time, as `other` this time), or the entry would
    // gain an AI link right beside the one the user corrected. Tags only claim their own
    // kind, as everywhere else.
    private func isClaimed(_ value: Claim, by claimed: Set<Claim>) -> Bool {
        claimed.contains { claim in
            guard claim.key == value.key else { return false }
            if claim.kind == value.kind { return true }
            if EntityResolver.isLabel(claim.kind) || EntityResolver.isLabel(value.kind) { return false }
            return claim.kind == .other || value.kind == .other
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
