import Foundation
import SwiftData

// Rows two phones made apart that mean the same thing, folded into one.
//
// CloudKit's mirroring has no uniqueness, and nothing in the model may be unique, so the same name
// written on two phones offline arrives as two entities, and a recap written on both arrives twice.
// Each kind has a rule, and every rule picks its survivor from the rows alone, so both phones,
// sweeping the same rows seconds apart, keep the same one rather than each deleting the other's.
//
// Rows with no id of their own (a link, an insights row) can't be ordered the same way on both
// phones when they are identical, so only the phone the entry was made on (`LocalOrigin`) folds
// those. `Entry` itself is `EntryDuplicates`; loose ends need nothing, since only the phone that
// made an entry writes them automatically.
//
// Run at launch and each time sync settles, next to the restore check.
enum SyncDuplicates {
    struct Result: Equatable {
        var entities = 0
        var links = 0
        var insights = 0
        var summaries = 0

        var total: Int { entities + links + insights + summaries }
    }

    @discardableResult
    static func run(in context: ModelContext, editor: GraphEditor, indexer: GraphIndexer, diagnostics: DiagnosticsLog = .shared) throws -> Result {
        var result = Result()
        var exempt = Set<UUID>()
        result.summaries = try summaries(in: context)
        result.insights = try insights(in: context, exempt: &exempt)
        result.links = links(in: context, indexer: indexer, exempt: &exempt)
        if result.total > 0 {
            if result.links > 0 { indexer.recount(in: context) }
            // Removing a link or an insights row marks its entry changed, which isn't an edit to it.
            let unstamped = Set(try context.fetch(FetchDescriptor<Entry>()).filter { exempt.contains($0.id) }.map(\.persistentModelID))
            try context.saveStampingEntries(except: unstamped)
        }
        // Last: each merge saves on its own, through the editor, like a merge from Mind.
        result.entities = try entities(in: context, editor: editor)
        if result.total > 0 {
            diagnostics.record("sync.duplicatesMerged", [
                "entities": .int(result.entities), "links": .int(result.links),
                "insights": .int(result.insights), "summaries": .int(result.summaries),
            ])
        }
        return result
    }

    // MARK: - Entities

    // Same key and kind, and neither touched by hand. A touched pair is the user's to decide, and
    // Mind already asks "same person?" about it, since an exact key scores 1.
    static func entities(in context: ModelContext, editor: GraphEditor) throws -> Int {
        let candidates = try context.fetch(FetchDescriptor<Entity>()).filter { !$0.isDeleted && !$0.isMerged && !$0.key.isEmpty && isUntouched($0) }
        var merged = 0
        for group in Dictionary(grouping: candidates, by: { "\($0.kindRaw)|\($0.key)" }).values where group.count > 1 {
            let ordered = group.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
            for loser in ordered.dropFirst() where editor.merge(loser, into: ordered[0], in: context, byUser: false) == .merged {
                merged += 1
            }
        }
        return merged
    }

    static func isUntouched(_ entity: Entity) -> Bool {
        !entity.confirmedByUser && !entity.bioEditedByUser && !entity.kindEditedByUser
            && !entity.hidden && !entity.resurfacingMuted && entity.notSameAs.isEmpty
    }

    // MARK: - Links

    // One entry mentioning one name from one source is one row. The row kept is the one carrying
    // the most, a tie's candidates first.
    static func links(in context: ModelContext, indexer: GraphIndexer, exempt: inout Set<UUID>) -> Int {
        let links = indexer.allLinks(in: context).filter { link in
            guard let entryID = link.entryID, link.entityID != nil else { return false }
            return isLocal(entryID, in: context)
        }
        var removed = 0
        let groups = Dictionary(grouping: links) { "\($0.entityID!.uuidString)|\($0.entryID!.uuidString)|\($0.sourceRaw)" }
        for group in groups.values where group.count > 1 {
            let ordered = group.sorted { a, b in
                if a.unsureAmong.count != b.unsureAmong.count { return a.unsureAmong.count > b.unsureAmong.count }
                return (a.surface, a.writtenSurface ?? "") < (b.surface, b.writtenSurface ?? "")
            }
            for extra in ordered.dropFirst() {
                context.delete(extra)
                removed += 1
            }
            if let entryID = ordered[0].entryID { exempt.insert(entryID) }
        }
        return removed
    }

    // MARK: - Insights

    // An entry has one insights row; a second is the older run, and goes. Read after everything is
    // saved, where the relationship is dependable; a row whose entry reads nil is left alone.
    static func insights(in context: ModelContext, exempt: inout Set<UUID>) throws -> Int {
        let rows = try context.fetch(FetchDescriptor<EntryInsights>()).filter { row in
            guard !row.isDeleted, let entry = row.entry else { return false }
            return isLocal(entry.id, in: context)
        }
        var removed = 0
        for group in Dictionary(grouping: rows, by: { $0.entry!.id }).values where group.count > 1 {
            let ordered = group.sorted { ($0.generatedAt, $0.sourceTextHash) > ($1.generatedAt, $1.sourceTextHash) }
            let keep = ordered[0]
            let entry = keep.entry
            for extra in ordered.dropFirst() {
                context.delete(extra)
                removed += 1
            }
            if let entry {
                entry.insights = keep
                exempt.insert(entry.id)
            }
        }
        return removed
    }

    // MARK: - Summaries

    // One row per period and kind, the newest. Life's feedback is one row of verdicts on both
    // phones, so the two are combined instead, the later row's verdict on a line winning.
    static func summaries(in context: ModelContext) throws -> Int {
        let rows = try context.fetch(FetchDescriptor<ReflectSummary>()).filter { !$0.isDeleted }
        var removed = 0
        let feedback = rows.filter { $0.periodKindRaw == LifeWords.feedbackKind }
        if feedback.count > 1 {
            let oldestFirst = feedback.sorted { ($0.generatedAt, $0.id.uuidString) < ($1.generatedAt, $1.id.uuidString) }
            var items: [ReflectQueueItem] = []
            for row in oldestFirst {
                for item in row.items {
                    items.removeAll { $0.title == item.title }
                    items.append(item)
                }
            }
            let keep = oldestFirst.last!
            keep.itemsData = try? JSONEncoder().encode(items)
            for extra in oldestFirst.dropLast() {
                context.delete(extra)
                removed += 1
            }
        }
        let periods = rows.filter { $0.periodKindRaw != LifeWords.feedbackKind }
        for group in Dictionary(grouping: periods, by: { "\($0.periodKindRaw)|\($0.periodStart.timeIntervalSinceReferenceDate)" }).values where group.count > 1 {
            let ordered = group.sorted { ($0.generatedAt, $0.id.uuidString) > ($1.generatedAt, $1.id.uuidString) }
            for extra in ordered.dropFirst() {
                context.delete(extra)
                removed += 1
            }
        }
        return removed
    }

    private static func isLocal(_ entryID: UUID, in context: ModelContext) -> Bool {
        LocalOrigin.of(context)?.contains(entryID) ?? true
    }
}
