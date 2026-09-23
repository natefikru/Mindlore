import Foundation

// The numbers Mind shows for a window: how many entries name each entity, the area it leans
// toward, its sparkline, and what changed against the stretch before. Pure over a snapshot, no
// SwiftData, the same split EntityGraph keeps from GraphServices, so MindView can compute all of
// it once per (revision, window) and nothing runs per frame.
//
// Windows are start-exclusive and end-inclusive: an entry on a window's first instant belongs to
// the window before, so a window and its baseline never share an entry.
nonisolated enum MindStats {
    struct Change: Equatable, Identifiable, Sendable {
        enum Kind: String, Sendable {
            case new, back, more, quieter
        }

        let id: UUID
        let kind: Kind
        // Entries naming the entity in the window, and in the three windows before it.
        let inWindow: Int
        let before: Int
        // Every entry written in the window, and in the three before: what a share is out of.
        let windowEntries: Int
        let beforeEntries: Int
        let lastMentioned: Date?
    }

    static let baselineWindows = 3
    static let changeCap = 4
    static let seriesBuckets = 16
    // A name is back only after at least this long without a mention, or two windows if longer,
    // so a month window doesn't call a three-week gap a return.
    static let backSilence: TimeInterval = 45 * 86_400

    private static func contains(_ date: Date, after start: Date?, through end: Date) -> Bool {
        date <= end && (start.map { date > $0 } ?? true)
    }

    // Each entity's distinct entries up to `asOf`, with their dates. One entity can reach an entry
    // through several links (a name and its tag after a merge); it counts once.
    private static func entryDates(_ snapshot: MindMapSnapshot, asOf: Date) -> [UUID: [UUID: Date]] {
        var result: [UUID: [UUID: Date]] = [:]
        for link in snapshot.links where link.entryDate <= asOf {
            result[link.entityID, default: [:]][link.entryID] = link.entryDate
        }
        return result
    }

    // Entries per entity in the window, each entry once.
    static func counts(_ snapshot: MindMapSnapshot, window: MindWindow, asOf: Date) -> [UUID: Int] {
        let start = window.interval(endingAt: asOf)?.start
        var entries: [UUID: Set<UUID>] = [:]
        for link in snapshot.links where contains(link.entryDate, after: start, through: asOf) {
            entries[link.entityID, default: []].insert(link.entryID)
        }
        return entries.mapValues(\.count)
    }

    // The life area each entity leans toward within the window. An entity whose windowed entries
    // carry no area gets none (drawn neutral).
    static func areas(_ snapshot: MindMapSnapshot, window: MindWindow, asOf: Date) -> [UUID: LifeArea] {
        let start = window.interval(endingAt: asOf)?.start
        let links = snapshot.links.filter { contains($0.entryDate, after: start, through: asOf) }
        let values = snapshot.entries.compactMapValues { entry -> EntityTally.Entry<LifeArea>? in
            entry.areas.isEmpty ? nil : EntityTally.Entry(values: entry.areas, date: entry.date)
        }
        return EntityTally.primary(links: links, values: values)
    }

    // The span a sparkline covers: the window and the three before it, or for all time the
    // journal's own span. Nil when there is nothing to span.
    private static func seriesSpan(_ snapshot: MindMapSnapshot, window: MindWindow, asOf: Date) -> TimeInterval? {
        if let length = window.length { return length * Double(baselineWindows + 1) }
        let earliest = snapshot.entryDates.filter { $0 <= asOf }.min()
            ?? snapshot.links.lazy.map(\.entryDate).filter { $0 <= asOf }.min()
        return earliest.map { asOf.timeIntervalSince($0) }
    }

    // Every entity's sparkline, oldest bucket first, the last bucket ending at `asOf`. Buckets are
    // start-exclusive like windows. For all time the journal's first entry lands in the first bucket.
    static func series(_ snapshot: MindMapSnapshot, window: MindWindow, asOf: Date, buckets: Int = seriesBuckets) -> [UUID: [Int]] {
        guard buckets > 0, let span = seriesSpan(snapshot, window: window, asOf: asOf) else { return [:] }
        let width = span / Double(buckets)
        var result: [UUID: [Int]] = [:]
        for (entityID, entries) in entryDates(snapshot, asOf: asOf) {
            var bars = [Int](repeating: 0, count: buckets)
            for date in entries.values {
                let age = asOf.timeIntervalSince(date)
                var fromEnd = width > 0 ? Int((age / width).rounded(.down)) : 0
                if fromEnd >= buckets {
                    guard window == .all else { continue }
                    fromEnd = buckets - 1
                }
                bars[buckets - 1 - fromEnd] += 1
            }
            result[entityID] = bars
        }
        return result
    }

    static func series(_ snapshot: MindMapSnapshot, entity: UUID, window: MindWindow, asOf: Date, buckets: Int = seriesBuckets) -> [Int] {
        let only = MindMapSnapshot(
            entities: snapshot.entities,
            links: snapshot.links.filter { $0.entityID == entity },
            entries: snapshot.entries,
            entryDates: snapshot.entryDates
        )
        return series(only, window: window, asOf: asOf, buckets: buckets)[entity] ?? [Int](repeating: 0, count: max(0, buckets))
    }

    // What changed in the window against the three windows before it, by share of entries, so
    // writing less in a month never makes everyone quieter. At most `cap`, none for all time and
    // none without a baseline (a journal younger than its window would call everyone new). Tags
    // need more to count and are never new or back: a tag that turns up twice is usually a word,
    // not news. Ranked by the shift in share times the larger of the two counts, so a name that
    // filled the journal and went quiet outranks one that went from one mention to three. On the
    // story journal that is what puts Greg (22 of 155 entries, then 1 of 42) above a busier tag.
    static func changes(_ snapshot: MindMapSnapshot, window: MindWindow, asOf: Date, excluding excluded: Set<UUID> = [], cap: Int = changeCap) -> [Change] {
        guard let length = window.length else { return [] }
        let start = asOf.addingTimeInterval(-length)
        let baseStart = asOf.addingTimeInterval(-length * Double(1 + baselineWindows))
        let windowEntries = snapshot.entryDates.count { contains($0, after: start, through: asOf) }
        let beforeEntries = snapshot.entryDates.count { contains($0, after: baseStart, through: start) }
        guard windowEntries > 0, beforeEntries > 0 else { return [] }
        let silence = max(2 * length, backSilence)

        var found: [(change: Change, score: Double)] = []
        for (entityID, entries) in entryDates(snapshot, asOf: asOf) where !excluded.contains(entityID) {
            guard let info = snapshot.entities[entityID] else { continue }
            let isTag = info.kind == .tag
            let dates = entries.values
            let inside = dates.filter { $0 > start }
            let earlier = dates.filter { $0 <= start }
            let inWindow = inside.count
            let before = earlier.count { $0 > baseStart }
            let shareNow = Double(inWindow) / Double(windowEntries)
            let shareBefore = Double(before) / Double(beforeEntries)

            let kind: Change.Kind?
            if !isTag, inWindow >= 2, earlier.isEmpty {
                kind = .new
            } else if !isTag, let firstInside = inside.min(), let lastEarlier = earlier.max(),
                      earlier.count >= 3, firstInside.timeIntervalSince(lastEarlier) >= silence {
                kind = .back
            } else if inWindow >= (isTag ? 4 : 3), before >= 1, shareNow >= 2 * shareBefore {
                kind = .more
            } else if before >= (isTag ? 3 : 2) * baselineWindows, shareNow <= shareBefore / 2 {
                kind = .quieter
            } else {
                kind = nil
            }
            guard let kind else { continue }

            let change = Change(
                id: entityID, kind: kind, inWindow: inWindow, before: before,
                windowEntries: windowEntries, beforeEntries: beforeEntries, lastMentioned: dates.max()
            )
            found.append((change, abs(shareNow - shareBefore) * Double(max(inWindow, before))))
        }

        return found
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                let l = lhs.change.lastMentioned ?? .distantPast, r = rhs.change.lastMentioned ?? .distantPast
                if l != r { return l > r }
                return lhs.change.id.uuidString < rhs.change.id.uuidString
            }
            .prefix(max(0, cap))
            .map(\.change)
    }

    // The entities that are the author, by the name Settings holds, matched against a person's
    // name and aliases the way every other name is matched. The author fills every page, so they
    // are never news.
    static func authorIDs(named userName: String, in snapshot: MindMapSnapshot) -> Set<UUID> {
        let key = EntityNormalizer.key(for: userName, kind: .person)
        guard !key.isEmpty else { return [] }
        return Set(snapshot.entities.values.filter { info in
            info.kind == .person && ([info.name] + info.aliases).contains { EntityNormalizer.key(for: $0, kind: .person) == key }
        }.map(\.id))
    }
}
