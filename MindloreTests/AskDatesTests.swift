import Foundation
import Testing
@testable import Mindlore

struct AskDatesTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    // Monday 14 September 2026, 14:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_789_394_400)

    private func range(_ question: String) -> DateInterval? {
        AskDates.range(in: question, now: now, calendar: calendar)
    }

    private func day(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)!
    }

    @Test func todayAndYesterdayAreOneDayEach() {
        #expect(range("what did I do today?") == DateInterval(start: day("2026-09-14"), end: day("2026-09-15")))
        #expect(range("anything from yesterday") == DateInterval(start: day("2026-09-13"), end: day("2026-09-14")))
    }

    @Test func weeksMonthsAndYears() {
        #expect(range("this week") == calendar.dateInterval(of: .weekOfYear, for: now))
        #expect(range("last week") == calendar.dateInterval(of: .weekOfYear, for: now.addingTimeInterval(-7 * 86_400)))
        #expect(range("this month")?.start == day("2026-09-01"))
        #expect(range("last month") == DateInterval(start: day("2026-08-01"), end: day("2026-09-01")))
        #expect(range("this year")?.start == day("2026-01-01"))
        #expect(range("last year") == DateInterval(start: day("2025-01-01"), end: day("2026-01-01")))
    }

    @Test func countedPhrasesCountBackFromToday() {
        #expect(range("what happened 3 days ago") == DateInterval(start: day("2026-09-11"), end: day("2026-09-12")))
        #expect(range("two weeks ago") == DateInterval(start: day("2026-08-31"), end: day("2026-09-01")))
        #expect(range("the last 5 days") == DateInterval(start: day("2026-09-09"), end: day("2026-09-15")))
        #expect(range("in the past two weeks") == DateInterval(start: day("2026-08-31"), end: day("2026-09-15")))
    }

    @Test func aBareMonthIsItsMostRecentOccurrence() {
        #expect(range("what happened in March") == DateInterval(start: day("2026-03-01"), end: day("2026-04-01")))
        #expect(range("what happened in September") == DateInterval(start: day("2026-09-01"), end: day("2026-10-01")))
        // October hasn't come round yet this year, so it means last October.
        #expect(range("anything in October?") == DateInterval(start: day("2025-10-01"), end: day("2025-11-01")))
        #expect(range("March 2025") == DateInterval(start: day("2025-03-01"), end: day("2025-04-01")))
    }

    @Test func anExplicitDateIsThatOneDay() {
        #expect(range("what did I write on March 4, 2025") == DateInterval(start: day("2025-03-04"), end: day("2025-03-05")))
    }

    // "may", "march" and "august" are ordinary words: a month only counts when the question
    // frames it as a date, or a month of entries goes out for a question about nothing of the kind.
    @Test func aMonthWordUsedAsAnOrdinaryWordIsNotADate() {
        #expect(range("what may I have forgotten?") == nil)
        #expect(range("did I march anywhere?") == nil)
        #expect(range("in May") != nil)
        #expect(range("May 2025") != nil)
    }

    @Test func aQuestionWithNoDateHasNoRange() {
        #expect(range("what's been going on with Sarah?") == nil)
        #expect(range("") == nil)
    }
}
