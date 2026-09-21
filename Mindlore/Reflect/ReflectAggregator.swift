import Foundation

// Mood, area, tag, and loose-end counts for one period. No SwiftData import: the caller (a
// fetching layer, not this one) resolves `Entry`/`EntryInsights`/`LooseEnd` into facts first, the
// same split `GraphServices` keeps against `EntityGraph`'s pure computation. Ask's rollup reads
// this too, so this is the one place these counts are computed.
nonisolated enum ReflectAggregator {
    struct EntryFact: Sendable {
        let date: Date
        let mood: MoodCategory?
        let areas: [LifeArea]
        let tags: [String]

        init(date: Date, mood: MoodCategory? = nil, areas: [LifeArea] = [], tags: [String] = []) {
            self.date = date
            self.mood = mood
            self.areas = areas
            self.tags = tags
        }
    }

    struct LooseEndFact: Sendable {
        let openedAt: Date
        // nil unless the loose end resolved; a dismissed or faded one is never "closed" here.
        let resolvedAt: Date?

        init(openedAt: Date, resolvedAt: Date? = nil) {
            self.openedAt = openedAt
            self.resolvedAt = resolvedAt
        }
    }

    struct TagCount: Sendable, Equatable {
        let tag: String
        let count: Int
    }

    struct Period: Sendable, Equatable {
        let interval: DateInterval
        let entryCount: Int
        // A mood or area absent from the period never appears here; callers read `?? 0`.
        let moodCounts: [MoodCategory: Int]
        let areaCounts: [LifeArea: Int]
        let topTags: [TagCount]
        let looseEndsOpened: Int
        let looseEndsClosed: Int
    }

    static let maxTopTags = 5

    // Always returns one `Period` for the interval asked about, even an empty one, since a
    // period the user is looking at needs an empty state, not a missing entry in a list. Compare
    // `AskRollups.months`, which drops empty months because it's building a list to summarize.
    static func aggregate(
        facts: [EntryFact],
        looseEnds: [LooseEndFact] = [],
        in interval: DateInterval
    ) -> Period {
        // Half-open, matching `AskRollups`: a date on `end` belongs to the next period, not this
        // one, so two adjacent periods never both claim the same entry.
        func isInside(_ date: Date) -> Bool {
            date >= interval.start && date < interval.end
        }

        let inside = facts.filter { isInside($0.date) }

        var moodCounts: [MoodCategory: Int] = [:]
        var areaCounts: [LifeArea: Int] = [:]
        var tagCounts: [String: Int] = [:]
        for fact in inside {
            if let mood = fact.mood { moodCounts[mood, default: 0] += 1 }
            for area in fact.areas { areaCounts[area, default: 0] += 1 }
            for tag in fact.tags { tagCounts[tag, default: 0] += 1 }
        }

        let topTags = tagCounts
            .map { TagCount(tag: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.tag < $1.tag }
            .prefix(maxTopTags)

        let opened = looseEnds.filter { isInside($0.openedAt) }.count
        let closed = looseEnds.filter { $0.resolvedAt.map(isInside) ?? false }.count

        return Period(
            interval: interval,
            entryCount: inside.count,
            moodCounts: moodCounts,
            areaCounts: areaCounts,
            topTags: Array(topTags),
            looseEndsOpened: opened,
            looseEndsClosed: closed
        )
    }
}
