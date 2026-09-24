import Foundation
import SwiftData

// What the peek card says about one entity: a glance, never a page. How present it has been
// lately, who it turns up with, what is still open about it, and the bio's first line. Reading it
// starts nothing, so a bio is only drafted once the full page opens.
enum EntityPeekPresentation {
    // A partner from `GraphServices.mentionedWith`, with the entries the two share: the same
    // query and the same number the entity page prints.
    struct Connection: Equatable, Identifiable {
        let id: UUID
        let name: String
        let entries: Int
    }

    struct Summary: Equatable {
        let name: String
        let kind: EntityKind
        let bioFirstLine: String?
        let lastMentioned: Date?
        let recentEntryCount: Int
        // Entries per week over the last `seriesWeeks`, oldest first. Weekly, not by Mind's
        // window, because the card also opens from the editor and Ask, where there is no window.
        var series: [Int] = []
        // Names first, themes on their own quieter line: tags share most entries with anyone
        // (Maya's top three were dating, processing, texting), so ranked together they crowded
        // out the people (owner, 2026-09-23).
        var connections: [Connection] = []
        var themes: [String] = []
        // How many open threads are about it, and the most recently mentioned one's words.
        var openLooseEndCount = 0
        var openLooseEnd: String? = nil
        // The linked CNContact, when there is one. The card reads the photo itself: the summary
        // stays pure so it can be tested without an address book.
        var contactIdentifier: String? = nil
        // Where a linked place is, so the card can draw its map. Nil for everything else.
        var place: PlaceCoordinate? = nil
    }

    static let recentDays = 30
    static let seriesWeeks = 26
    static let connectionLimit = 3
    // How far down mentionedWith's ranking to read so three names and three themes both fill.
    static let partnerScan = 40

    // Names and themes from one ranked partner list, each capped at `limit`.
    nonisolated static func split(_ partners: [(id: UUID, name: String, kind: EntityKind, entries: Int)], limit: Int = connectionLimit) -> (connections: [Connection], themes: [String]) {
        let names = partners.filter { $0.kind != .tag }.prefix(limit).map { Connection(id: $0.id, name: $0.name, entries: $0.entries) }
        let themes = partners.filter { $0.kind == .tag }.prefix(limit).map(\.name)
        return (Array(names), Array(themes))
    }

    // "today", "yesterday", "3 days ago", "2 weeks ago": days, never minutes, since an entry's
    // date is the day it belongs to.
    nonisolated static func lastMentionedWords(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ...0: return "today"
        case 1: return "yesterday"
        default:
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            formatter.dateTimeStyle = .named
            formatter.calendar = calendar
            return formatter.localizedString(for: calendar.startOfDay(for: date), relativeTo: calendar.startOfDay(for: now))
        }
    }

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
            lastMentioned: entryDates.filter { $0 <= now }.max(),
            recentEntryCount: entryDates.filter { $0 >= cutoff && $0 <= now }.count,
            series: series(entryDates, now: now)
        )
    }

    // Weekly buckets ending at `now`, the last covering the seven days up to it. A week's start
    // instant belongs to the week before, the same rule as Mind's windows. Future dates and
    // anything older than the span are left out.
    nonisolated static func series(_ dates: [Date], now: Date, weeks: Int = seriesWeeks) -> [Int] {
        guard weeks > 0 else { return [] }
        let week: TimeInterval = 7 * 86_400
        var bars = [Int](repeating: 0, count: weeks)
        for date in dates where date <= now {
            let fromEnd = Int((now.timeIntervalSince(date) / week).rounded(.down))
            guard fromEnd < weeks else { continue }
            bars[weeks - 1 - fromEnd] += 1
        }
        return bars
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

        // Open loose ends about this entity, through merges, and the most recently mentioned.
        let open = LooseEnd.all(in: context)
            .filter { $0.isOpen && $0.entityIDs.contains { root(of: $0) == id } }
        let looseEnd = open.max { $0.lastMentionedAt < $1.lastMentionedAt }

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
        result.openLooseEndCount = open.count
        let partners = graph.mentionedWith(of: id, in: context, limit: partnerScan)
            .map { (id: $0.id, name: $0.name, kind: $0.kind, entries: $0.entries) }
        (result.connections, result.themes) = split(partners)
        result.contactIdentifier = entity.contactIdentifier
        result.place = entity.placeCoordinate
        return result
    }
}
