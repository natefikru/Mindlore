import Foundation
import Testing
@testable import Mindlore

struct ReflectAggregatorTests {
    // Monday 14 September 2026, 14:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_789_394_400)

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    private func week(daysAgo: Int = 0) -> DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: now.addingTimeInterval(-Double(daysAgo) * 86_400))!
    }

    private func fact(
        daysAgo: Int,
        mood: MoodCategory? = .calm,
        areas: [LifeArea] = [.work],
        tags: [String] = []
    ) -> ReflectAggregator.EntryFact {
        ReflectAggregator.EntryFact(
            date: now.addingTimeInterval(-Double(daysAgo) * 86_400),
            mood: mood,
            areas: areas,
            tags: tags
        )
    }

    // MARK: - Counting

    @Test func countsMoodsAreasAndTagsInThePeriod() {
        let interval = week()
        let facts = [
            ReflectAggregator.EntryFact(date: interval.start, mood: .calm, areas: [.work, .health], tags: ["deadline"]),
            ReflectAggregator.EntryFact(
                date: interval.start.addingTimeInterval(86_400),
                mood: .calm,
                areas: [.health],
                tags: ["deadline", "sleep"]
            ),
            ReflectAggregator.EntryFact(
                date: interval.start.addingTimeInterval(2 * 86_400),
                mood: .anxious,
                areas: [.work],
                tags: []
            ),
        ]
        let period = ReflectAggregator.aggregate(facts: facts, in: interval)

        #expect(period.entryCount == 3)
        #expect(period.moodCounts[.calm] == 2)
        #expect(period.moodCounts[.anxious] == 1)
        #expect(period.areaCounts[.work] == 2)
        #expect(period.areaCounts[.health] == 2)
        #expect(period.topTags.first == .init(tag: "deadline", count: 2))
    }

    @Test func aMoodOrAreaThatNeverAppearsIsAbsentNotZero() {
        let period = ReflectAggregator.aggregate(facts: [fact(daysAgo: 0, areas: [.work])], in: week())
        #expect(period.moodCounts[.joyful] == nil)
        #expect(period.areaCounts[.love] == nil)
    }

    // MARK: - Boundaries

    @Test func anEntryOnTheIntervalStartCountsOneOnEndDoesNot() {
        let interval = week()
        let onStart = ReflectAggregator.EntryFact(date: interval.start)
        let onEnd = ReflectAggregator.EntryFact(date: interval.end)
        let period = ReflectAggregator.aggregate(facts: [onStart, onEnd], in: interval)
        #expect(period.entryCount == 1)
    }

    @Test func aDateOutsideTheIntervalIsNotCounted() {
        let period = ReflectAggregator.aggregate(facts: [fact(daysAgo: 30)], in: week())
        #expect(period.entryCount == 0)
    }

    // MARK: - Empty periods

    @Test func anEmptyPeriodReturnsZeroedCountsNotNil() {
        let period = ReflectAggregator.aggregate(facts: [], in: week())
        #expect(period.entryCount == 0)
        #expect(period.moodCounts.isEmpty)
        #expect(period.areaCounts.isEmpty)
        #expect(period.topTags.isEmpty)
        #expect(period.looseEndsOpened == 0)
        #expect(period.looseEndsClosed == 0)
    }

    // MARK: - Top tags

    @Test func topTagsCapsAndBreaksTiesAlphabetically() {
        let facts = ["f", "e", "d", "c", "b", "a"].map { fact(daysAgo: 0, tags: [$0]) }
        let period = ReflectAggregator.aggregate(facts: facts, in: week())
        #expect(period.topTags.count == ReflectAggregator.maxTopTags)
        #expect(period.topTags.map(\.tag) == ["a", "b", "c", "d", "e"])
    }

    @Test func topTagsSortsByCountDescendingThenTag() {
        let facts = [
            fact(daysAgo: 0, tags: ["b"]),
            fact(daysAgo: 0, tags: ["a", "b"]),
        ]
        let period = ReflectAggregator.aggregate(facts: facts, in: week())
        #expect(period.topTags.map(\.tag) == ["b", "a"])
        #expect(period.topTags.first?.count == 2)
    }

    // MARK: - Loose ends

    @Test func aLooseEndOpenedInPeriodAndResolvedLaterCountsOnlyAsOpened() {
        let interval = week()
        let looseEnd = ReflectAggregator.LooseEndFact(
            openedAt: interval.start,
            resolvedAt: interval.end.addingTimeInterval(86_400)
        )
        let period = ReflectAggregator.aggregate(facts: [], looseEnds: [looseEnd], in: interval)
        #expect(period.looseEndsOpened == 1)
        #expect(period.looseEndsClosed == 0)
    }

    @Test func aLooseEndOpenedEarlierAndResolvedInPeriodCountsOnlyAsClosed() {
        let interval = week()
        let looseEnd = ReflectAggregator.LooseEndFact(
            openedAt: interval.start.addingTimeInterval(-86_400 * 30),
            resolvedAt: interval.start
        )
        let period = ReflectAggregator.aggregate(facts: [], looseEnds: [looseEnd], in: interval)
        #expect(period.looseEndsOpened == 0)
        #expect(period.looseEndsClosed == 1)
    }

    @Test func aLooseEndWithNoResolutionNeverCountsAsClosed() {
        let interval = week()
        let looseEnd = ReflectAggregator.LooseEndFact(openedAt: interval.start, resolvedAt: nil)
        let period = ReflectAggregator.aggregate(facts: [], looseEnds: [looseEnd], in: interval)
        #expect(period.looseEndsClosed == 0)
    }

    // MARK: - DST

    @Test func aWeekSpanningADaylightSavingChangeStillBucketsCorrectly() {
        // The US spring-forward Sunday, 8 March 2026: a calendar-built interval, not raw
        // 7 * 86_400 arithmetic, is what keeps every day of that week inside it.
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York")!
        let springForward = eastern.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!
        let interval = eastern.dateInterval(of: .weekOfYear, for: springForward)!

        let facts = (0..<7).map { offset in
            ReflectAggregator.EntryFact(date: eastern.date(byAdding: .day, value: offset, to: interval.start)!)
        }
        let period = ReflectAggregator.aggregate(facts: facts, in: interval)
        #expect(period.entryCount == 7)
    }
}
