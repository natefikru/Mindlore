import Foundation

// What Mind's drawer lists when nothing is being searched: a "what changed" row and every name
// the window holds, ranked. Pure, like MindStats: MindView computes the window's numbers once per
// (revision, window) into `Stats`, the panel joins them with its own directory rows here.
nonisolated enum MindDrawer {
    // One window's numbers, computed together so nothing in the drawer runs per frame.
    struct Stats: Equatable, Sendable {
        var window: MindWindow = .default
        var counts: [UUID: Int] = [:]
        var areas: [UUID: LifeArea] = [:]
        var series: [UUID: [Int]] = [:]
        var changes: [MindStats.Change] = []

        static let empty = Stats()

        static func make(_ snapshot: MindMapSnapshot, window: MindWindow, asOf: Date, excluding author: Set<UUID>) -> Stats {
            Stats(
                window: window,
                counts: MindStats.counts(snapshot, window: window, asOf: asOf),
                areas: MindStats.areas(snapshot, window: window, asOf: asOf),
                series: MindStats.series(snapshot, window: window, asOf: asOf),
                changes: MindStats.changes(snapshot, window: window, asOf: asOf, excluding: author)
            )
        }
    }

    struct RankedRow: Equatable, Identifiable, Sendable {
        let id: UUID
        let name: String
        let kind: EntityKind
        let area: LifeArea?
        let count: Int
        let series: [Int]
        let change: MindStats.Change.Kind?
        let openLooseEnds: Int
        let lastMentioned: Date?
    }

    struct ChangeCard: Equatable, Identifiable, Sendable {
        var id: UUID { change.id }
        let name: String
        let kind: EntityKind
        let change: MindStats.Change
        let words: String
    }

    // Every name with at least one entry in the window, in the chosen kind: most entries first,
    // then the most recently mentioned, then by name. A name the window doesn't hold is left to
    // search, the way it leaves the map.
    static func ranked(_ rows: [EntitySearch.Row], stats: Stats, segment: EntitySearch.Segment) -> [RankedRow] {
        let changed = Dictionary(stats.changes.map { ($0.id, $0.kind) }, uniquingKeysWith: { first, _ in first })
        return rows
            .filter { segment.includes($0.kind) && (stats.counts[$0.id] ?? 0) > 0 }
            .map { row in
                RankedRow(
                    id: row.id, name: row.name, kind: row.kind, area: stats.areas[row.id],
                    count: stats.counts[row.id] ?? 0, series: stats.series[row.id] ?? [],
                    change: changed[row.id], openLooseEnds: row.openLooseEnds, lastMentioned: row.lastMentioned
                )
            }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                switch (lhs.lastMentioned, rhs.lastMentioned) {
                case (let l?, let r?) where l != r: return l > r
                case (_?, nil): return true
                case (nil, _?): return false
                default: return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
            }
    }

    // The changes as cards, in the chosen kind. A change about a name no longer browsable (hidden
    // or merged since the numbers were counted) is dropped rather than shown without a name.
    static func cards(_ rows: [EntitySearch.Row], stats: Stats, segment: EntitySearch.Segment) -> [ChangeCard] {
        let byID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return stats.changes.compactMap { change in
            guard let row = byID[change.id], segment.includes(row.kind) else { return nil }
            return ChangeCard(name: row.name, kind: row.kind, change: change, words: words(for: change, window: stats.window))
        }
    }

    // MARK: - Words

    static func title(_ kind: MindStats.Change.Kind) -> String {
        switch kind {
        case .new: "New"
        case .back: "Back"
        case .more: "More lately"
        case .quieter: "Quieter"
        }
    }

    private static func span(_ window: MindWindow) -> String {
        switch window {
        case .month: "a month"
        case .quarter: "3 months"
        case .year: "a year"
        case .all: "all time"
        }
    }

    // The three windows a change is measured against.
    private static func baseline(_ window: MindWindow) -> String {
        switch window {
        case .month: "3 months"
        case .quarter: "9 months"
        case .year: "3 years"
        case .all: "time"
        }
    }

    private static func entries(_ count: Int) -> String {
        count == 1 ? "1 entry" : "\(count) entries"
    }

    // The numbers behind a change, as a sentence: "in 11 of your last 19 entries, up from 7 of 41",
    // "once in 3 months, down from 22 in the 9 months before". Counts, never a judgement, and never a streak.
    static func words(for change: MindStats.Change, window: MindWindow) -> String {
        let share = switch change.inWindow {
        case change.windowEntries where change.windowEntries == 1: "in your only entry"
        case change.windowEntries: "in all of your last \(entries(change.windowEntries))"
        default: "in \(change.inWindow) of your last \(entries(change.windowEntries))"
        }
        switch change.kind {
        case .new:
            return "first mentioned lately, \(share)"
        case .back:
            return change.inWindow == 1 ? "once in \(span(window)), after a long quiet" : "\(share), after a long quiet"
        case .more:
            return "\(share), up from \(change.before) of \(change.beforeEntries)"
        case .quieter:
            let now = switch change.inWindow {
            case 0: "not in \(span(window))"
            case 1: "once in \(span(window))"
            default: "\(change.inWindow) times in \(span(window))"
            }
            return "\(now), down from \(change.before) in the \(baseline(window)) before"
        }
    }
}
