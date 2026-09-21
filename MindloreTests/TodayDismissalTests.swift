import Foundation
import Testing
@testable import Mindlore

struct TodayDismissalTests {
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test func aStampIsOneDayWhateverTheTime() {
        let morning = TodayDismissal.stamp(date(2026, 9, 19, hour: 0), calendar: utc)
        let night = TodayDismissal.stamp(date(2026, 9, 19, hour: 23), calendar: utc)

        #expect(morning == "2026-09-19")
        #expect(morning == night)
    }

    @Test func stampsSortAndPadTheirParts() {
        #expect(TodayDismissal.stamp(date(2026, 1, 5), calendar: utc) == "2026-01-05")
    }

    @Test func aDismissedCardStaysDismissedForTheDay() {
        var dismissal = TodayDismissal()
        dismissal.dismiss("onThisDay", on: "2026-09-19")

        #expect(dismissal.keys(on: "2026-09-19") == ["onThisDay"])
    }

    @Test func severalCardsCanBeDismissedOnOneDay() {
        var dismissal = TodayDismissal()
        dismissal.dismiss("onThisDay", on: "2026-09-19")
        dismissal.dismiss("stillOpen", on: "2026-09-19")

        #expect(dismissal.keys(on: "2026-09-19") == ["onThisDay", "stillOpen"])
    }

    @Test func tomorrowBringsEveryCardBack() {
        var dismissal = TodayDismissal()
        dismissal.dismiss("onThisDay", on: "2026-09-19")

        #expect(dismissal.keys(on: "2026-09-20").isEmpty)
    }

    @Test func dismissingOnANewDayForgetsTheOldOne() {
        var dismissal = TodayDismissal()
        dismissal.dismiss("onThisDay", on: "2026-09-19")
        dismissal.dismiss("stillOpen", on: "2026-09-20")

        #expect(dismissal.keys(on: "2026-09-20") == ["stillOpen"])
        #expect(dismissal.keys(on: "2026-09-19").isEmpty)
    }

    // A clock stepping back is the same case as any other day that isn't the stored one: the
    // stamp stops matching and the cards come back, rather than staying hidden.
    @Test func aClockSteppingBackBringsTheCardsBack() {
        var dismissal = TodayDismissal()
        dismissal.dismiss("onThisDay", on: "2026-09-19")

        #expect(dismissal.keys(on: "2026-09-18").isEmpty)
    }

    @Test func itRoundTripsThroughJSON() throws {
        var dismissal = TodayDismissal()
        dismissal.dismiss("beenAWhile", on: "2026-09-19")

        let data = try JSONEncoder().encode(dismissal)
        #expect(try JSONDecoder().decode(TodayDismissal.self, from: data) == dismissal)
    }
}
