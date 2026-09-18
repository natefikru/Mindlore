import Foundation
import SwiftData

// The store half of a rename's rewrite. Kept apart from the pure matching rules so the walk can
// be read against tasks/lessons.md in one sitting: one fetch per model, filtered in memory on
// saved objects, no predicate reaching through a relationship or over an array.
//
// One walk serves both callers. The rename writes; the sheet's warning counts without writing,
// so what it promises and what happens come from the same rules.
@MainActor
enum EntityProseStore {
    struct Result {
        var counts = EntityProseRewriter.Counts()
        // Entries whose insights or title changed. Rewriting a summary marks the entry changed
        // through the relationship, but it is not an edit to the entry, so the caller's save
        // exempts these from stamping the way GraphEditor.save(touchedBy:) does for moved links.
        var touchedEntryIDs: Set<UUID> = []
    }

    static func rewriteAll(oldName: String, newName: String, entityID: UUID, kind: EntityKind, in context: ModelContext) -> Result {
        walk(name: oldName, newName: newName, entityID: entityID, kind: kind, in: context)
    }

    // What a rename would change, counted off the name the entity has now.
    static func countOnly(name: String, entityID: UUID, kind: EntityKind, in context: ModelContext) -> EntityProseRewriter.Counts {
        walk(name: name, newName: nil, entityID: entityID, kind: kind, in: context).counts
    }

    // newName nil counts without writing.
    private static func walk(name: String, newName: String?, entityID: UUID, kind: EntityKind, in context: ModelContext) -> Result {
        var result = Result()
        let old = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !old.isEmpty else { return result }
        if let newName, EntityProseRewriter.rewrite(old, from: old, to: newName) == nil { return result }

        // Applies the change when there is one, and reports whether the text held the name.
        func apply(_ text: String, _ write: (String) -> Void) -> Bool {
            guard let newName else { return EntityProseRewriter.contains(old, in: text) }
            guard let rewritten = EntityProseRewriter.rewrite(text, from: old, to: newName) else { return false }
            write(rewritten)
            return true
        }

        // A tag's name is an ordinary lowercase word ("river", "work"). Exact case then matches
        // every normal occurrence, so tags are never rewritten at all.
        guard kind != .tag else { return result }

        let evidence = Evidence.gather(entityID: entityID, oldName: old, in: context)
        rewriteBios(old, evidence: evidence, apply: apply, into: &result, in: context)
        rewriteEntryProse(old, evidence: evidence, apply: apply, into: &result, in: context)
        rewriteLooseEnds(old, entityID: entityID, apply: apply, into: &result, in: context)
        return result
    }

    private typealias Apply = (String, (String) -> Void) -> Bool

    // Which entries actually call this entity by the old name, and which entities those entries
    // also mention. Names like April, Grace, Will, and May are ordinary words, so being linked is
    // not enough: the entry has to have used that exact spelling for this entity.
    private struct Evidence {
        var entryIDs: Set<UUID> = []
        var entityIDs: Set<UUID> = []

        static func gather(entityID: UUID, oldName: String, in context: ModelContext) -> Evidence {
            let links = ((try? context.fetch(FetchDescriptor<EntityLink>())) ?? []).filter { !$0.isDeleted }
            var evidence = Evidence(entityIDs: [entityID])
            for link in links where link.entityID == entityID {
                let spellings = [link.writtenSurface, link.surface].compactMap { $0 }
                guard spellings.contains(oldName), let entryID = link.entryID else { continue }
                evidence.entryIDs.insert(entryID)
            }
            // A bio is only rewritten for an entity that shares one of those entries, so a
            // stranger's bio that happens to say "April" is never touched.
            for link in links where link.entryID.map({ evidence.entryIDs.contains($0) }) == true {
                if let id = link.entityID { evidence.entityIDs.insert(id) }
            }
            return evidence
        }
    }

    // Any entity's bio can name any other, so this walk isn't narrowed to one entity, only to the
    // ones that share an entry where this name was actually written. A bio the user wrote is the
    // user's words, the same guard EntityBioDrafter.mayWrite applies.
    private static func rewriteBios(_ old: String, evidence: Evidence, apply: Apply, into result: inout Result, in context: ModelContext) {
        for entity in (try? context.fetch(FetchDescriptor<Entity>())) ?? []
        where !entity.isDeleted && !entity.bioEditedByUser && evidence.entityIDs.contains(entity.id) {
            guard let bio = entity.bio else { continue }
            if apply(bio, { entity.bio = $0 }) { result.counts.bios += 1 }
        }
    }

    // Only entries that wrote this name for this entity: an entry that never mentioned Sarah has
    // no business containing her name, and one that says "April" the month never linked it here.
    private static func rewriteEntryProse(_ old: String, evidence: Evidence, apply: Apply, into result: inout Result, in context: ModelContext) {
        guard !evidence.entryIDs.isEmpty else { return }

        for entry in (try? context.fetch(FetchDescriptor<Entry>())) ?? []
        where !entry.isDeleted && evidence.entryIDs.contains(entry.id) {
            var touched = false

            // A title the user typed is the user's words, the same rule as a hand-edited bio.
            if entry.titleWasGenerated, apply(entry.title, { entry.title = $0 }) {
                result.counts.titles += 1
                touched = true
            }

            if let insights = entry.insights, !insights.isDeleted {
                if let summary = insights.summary, apply(summary, { insights.summary = $0 }) {
                    result.counts.summaries += 1
                    touched = true
                }
                // The card's name is the user's own prompt name; only the model's answer changes.
                var cards = insights.customResults
                var changedCards = false
                for index in cards.indices {
                    let changed = apply(cards[index].content) { rewritten in
                        cards[index] = CustomInsightResult(promptID: cards[index].promptID, name: cards[index].name, content: rewritten)
                        changedCards = true
                    }
                    if changed { result.counts.cards += 1 }
                }
                if changedCards {
                    insights.customResults = cards
                    touched = true
                }
            }

            if touched { result.touchedEntryIDs.insert(entry.id) }
        }
    }

    // entityIDs is never rewritten by a merge, so a loose end reaches this entity through any id
    // that resolves to it. One entity fetch builds the map; mergedIntoID is walked with a guard.
    private static func rewriteLooseEnds(_ old: String, entityID: UUID, apply: Apply, into result: inout Result, in context: ModelContext) {
        let entities = ((try? context.fetch(FetchDescriptor<Entity>())) ?? []).filter { !$0.isDeleted }
        let byID = Dictionary(entities.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        func root(of id: UUID) -> UUID? {
            guard var current = byID[id] else { return nil }
            var seen: Set<UUID> = [current.id]
            while let nextID = current.mergedIntoID, let next = byID[nextID], seen.insert(next.id).inserted {
                current = next
            }
            return current.id
        }

        for looseEnd in LooseEnd.all(in: context)
        where looseEnd.entityIDs.contains(where: { root(of: $0) == entityID }) {
            if apply(looseEnd.text, { looseEnd.text = $0 }) { result.counts.looseEnds += 1 }
        }
    }
}
