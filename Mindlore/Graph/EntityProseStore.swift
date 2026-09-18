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

    static func rewriteAll(oldName: String, newName: String, entityID: UUID, in context: ModelContext) -> Result {
        walk(name: oldName, newName: newName, entityID: entityID, in: context)
    }

    // What a rename would change, counted off the name the entity has now.
    static func countOnly(name: String, entityID: UUID, in context: ModelContext) -> EntityProseRewriter.Counts {
        walk(name: name, newName: nil, entityID: entityID, in: context).counts
    }

    // newName nil counts without writing.
    private static func walk(name: String, newName: String?, entityID: UUID, in context: ModelContext) -> Result {
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

        rewriteBios(old, apply: apply, into: &result, in: context)
        rewriteEntryProse(old, entityID: entityID, apply: apply, into: &result, in: context)
        rewriteLooseEnds(old, entityID: entityID, apply: apply, into: &result, in: context)
        return result
    }

    private typealias Apply = (String, (String) -> Void) -> Bool

    // Any entity's bio can name any other, so this is the one walk that can't be narrowed by
    // links. A bio the user wrote is the user's words, and the rule that protects an entry
    // protects it, the same guard EntityBioDrafter.mayWrite applies.
    private static func rewriteBios(_ old: String, apply: Apply, into result: inout Result, in context: ModelContext) {
        for entity in (try? context.fetch(FetchDescriptor<Entity>())) ?? [] where !entity.isDeleted && !entity.bioEditedByUser {
            guard let bio = entity.bio else { continue }
            if apply(bio, { entity.bio = $0 }) { result.counts.bios += 1 }
        }
    }

    // Only the entries this entity is actually linked to: an entry that never mentioned Sarah has
    // no business containing her name. Links carry the ids; the relationships are not read.
    private static func rewriteEntryProse(_ old: String, entityID: UUID, apply: Apply, into result: inout Result, in context: ModelContext) {
        let linkedEntryIDs = Set(((try? context.fetch(FetchDescriptor<EntityLink>())) ?? [])
            .filter { !$0.isDeleted && $0.entityID == entityID }
            .compactMap(\.entryID))
        guard !linkedEntryIDs.isEmpty else { return }

        for entry in (try? context.fetch(FetchDescriptor<Entry>())) ?? []
        where !entry.isDeleted && linkedEntryIDs.contains(entry.id) {
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
