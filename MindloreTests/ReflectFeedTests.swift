import Foundation
import Testing
@testable import Mindlore

// Pure feed shape: which weeks are "recent," which months come before them, and what a month's
// fold-out produces. No SwiftData; ReflectView's own load() decides which months actually have
// entries.
struct ReflectFeedTests {
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2 // Monday, so week boundaries are unambiguous in the assertions below.
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @Test func theCurrentWeekIsFirstAndFlaggedCurrent() {
        let weeks = ReflectFeed.recentWeeks(recentWeekCount: 3, now: date(2026, 9, 21), calendar: utc)
        #expect(weeks.count == 3)
        #expect(weeks.first?.isCurrent == true)
        #expect(weeks.dropFirst().allSatisfy { !$0.isCurrent })
        // Newest first, each one week apart.
        #expect(weeks[0].interval.start > weeks[1].interval.start)
        #expect(weeks[1].interval.start > weeks[2].interval.start)
    }

    // The week/month boundary: a month's own interval never overlaps the recent-weeks stretch, so
    // no day is shown twice and none is dropped between the two densities.
    @Test func aMonthRowNeverOverlapsTheRecentWeeksStretch() {
        let now = date(2026, 9, 21)
        let weeks = ReflectFeed.recentWeeks(recentWeekCount: 8, now: now, calendar: utc)
        let oldestWeekStart = try! #require(weeks.last?.interval.start)

        let months = ReflectFeed.months(beforeWeekStart: oldestWeekStart, earliestEntryDate: date(2025, 1, 1), calendar: utc)

        for month in months {
            #expect(month.interval.end <= oldestWeekStart, "\(month.interval) reaches into the recent-weeks stretch starting \(oldestWeekStart)")
        }
    }

    @Test func monthsReachBackToTheEarliestEntrysMonthInclusive() {
        let oldestWeekStart = date(2026, 3, 2)
        let earliest = date(2026, 1, 15)

        let months = ReflectFeed.months(beforeWeekStart: oldestWeekStart, earliestEntryDate: earliest, calendar: utc)

        let earliestMonthStart = utc.dateInterval(of: .month, for: earliest)!.start
        #expect(months.last?.interval.start == earliestMonthStart)
    }

    @Test func noMonthsWhenTheJournalStartsInsideTheRecentWeeksStretch() {
        let now = date(2026, 9, 21)
        let weeks = ReflectFeed.recentWeeks(recentWeekCount: 8, now: now, calendar: utc)
        let oldestWeekStart = try! #require(weeks.last?.interval.start)

        // The journal's first entry is inside the recent stretch itself.
        let months = ReflectFeed.months(beforeWeekStart: oldestWeekStart, earliestEntryDate: now, calendar: utc)
        #expect(months.isEmpty)
    }

    // A month's fold-out produces exactly its weeks: every week whose start falls inside it,
    // oldest first, and no more.
    @Test func aMonthsFoldOutProducesExactlyItsWeeks() {
        let march = utc.dateInterval(of: .month, for: date(2026, 3, 15))!

        let weeks = ReflectFeed.weeks(in: march, calendar: utc)

        #expect(!weeks.isEmpty)
        for week in weeks {
            #expect(week.interval.start >= march.start && week.interval.start < march.end)
        }
        #expect(weeks == weeks.sorted { $0.interval.start < $1.interval.start })
        // No duplicates.
        #expect(Set(weeks.map(\.id)).count == weeks.count)
    }
}
