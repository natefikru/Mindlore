import Foundation
import SwiftData

// What the peek card says about one entity: a glance, never a page. Reading it starts nothing, so
// a bio is only drafted once the full page opens.
enum EntityPeekPresentation {
    struct Summary: Equatable {
        let name: String
        let kind: EntityKind
        let bioFirstLine: String?
        let lastMentioned: Date?
        let recentEntryCount: Int
        var openLooseEnd: String? = nil
    }

    static let recentDays = 30

    // `entryDates` holds one date per distinct entry that mentions the entity.
    nonisolated static func summary(name: String, kind: EntityKind, bio: String?, entryDates: [Date], now: Date, calendar: Calendar = .current) -> Summary {
        let firstLine = bio?
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        let cutoff = calendar.date(byAdding: .day, value: -recentDays, to: now) ?? now
        return Summary(
            name: name,
            kind: kind,
            bioFirstLine: firstLine,
            lastMentioned: entryDates.max(),
            recentEntryCount: entryDates.filter { $0 >= cutoff && $0 <= now }.count
        )
    }

    // One link fetch, one entity fetch, and one entry fetch. A merge already moved the loser's
    // links to the winner, so counting links whose root is `id` counts everything it absorbed.
    static func load(_ id: UUID, graph: GraphServices, in context: ModelContext, now: Date = .now) -> Summary? {
        let entities = ((try? context.fetch(FetchDescriptor<Entity>())) ?? []).filter { !$0.isDeleted }
        let byID = Dictionary(entities.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard let entity = byID[id] else { return nil }

        func root(of id: UUID) -> UUID? {
            guard var current = byID[id] else { return nil }
            var seen: Set<UUID> = [current.id]
            while let nextID = current.mergedIntoID, let next = byID[nextID], seen.insert(next.id).inserted {
                current = next
            }
            return current.id
        }

        // The most recently mentioned open loose end about this entity, through merges.
        let looseEnd = LooseEnd.all(in: context)
            .filter { $0.isOpen && $0.entityIDs.contains { root(of: $0) == id } }
            .max { $0.lastMentionedAt < $1.lastMentionedAt }

        let entryIDs = Set(graph.indexer.allLinks(in: context).compactMap { link -> UUID? in
            guard let entityID = link.entityID, root(of: entityID) == id else { return nil }
            return link.entryID
        })
        let entries = entryIDs.isEmpty ? [] : ((try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { entryIDs.contains($0.id) }))) ?? [])
        var result = summary(
            name: entity.name,
            kind: entity.kind,
            bio: entity.bio,
            entryDates: entries.filter { !$0.isDeleted }.map(\.entryDate),
            now: now
        )
        result.openLooseEnd = looseEnd?.text
        return result
    }
}
