import Foundation
import Testing
@testable import Mindlore

// A thread card says when its loose end will fade, by the same rule the sweep that fades it uses.
struct TodayFadeTests {
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let english = Locale(identifier: "en_US")

    private func date(_ month: Int, _ day: Int, hour: Int = 12) -> Date {
        utc.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func fade(_ end: LooseEndFacts, at now: Date) -> String? {
        TodayCopy.fade(.stillOpen(end), now: now, calendar: utc, locale: english)
    }

    @Test func anUndatedThreadFadesSixWeeksAfterItWasLastWrittenAbout() {
        let end = LooseEndFacts(id: UUID(), text: "t", sourceEntryDate: date(8, 1), lastMentionedAt: date(9, 1))
        #expect(end.fadeDate == date(10, 13))
        #expect(fade(end, at: date(9, 22)) == "fades Oct 13")
        #expect(TodayCopy.threadLine(.stillOpen(end), now: date(9, 22), calendar: utc, locale: english) == "Since Aug 1 \u{00B7} fades Oct 13")
    }

    @Test func aDatedThreadFadesAWeekAfterItsDay() {
        let end = LooseEndFacts(id: UUID(), text: "t", sourceEntryDate: date(9, 2), dueDate: date(9, 30))
        #expect(end.fadeDate == date(10, 7))
        #expect(fade(end, at: date(9, 22)) == "fades Oct 7")
        #expect(TodayCopy.threadLine(.stillOpen(end), now: date(9, 22), calendar: utc, locale: english) == "Due Sep 30 \u{00B7} fades Oct 7", "a due date is the date that matters")
    }

    @Test func closeToItsDayItCountsDown() {
        let end = LooseEndFacts(id: UUID(), text: "t", sourceEntryDate: date(9, 1), dueDate: date(9, 20))
        #expect(fade(end, at: date(9, 23)) == "fades in 4 days")
        #expect(fade(end, at: date(9, 26)) == "fades tomorrow")
        #expect(fade(end, at: date(9, 27, hour: 8)) == "fades today")
    }

    @Test func aDayCardHasNoFadeLine() {
        let entry = EntryFacts(id: UUID(), entryDate: date(9, 1), summary: "s")
        #expect(TodayCopy.fade(.latestSummary(entry), now: date(9, 2), calendar: utc, locale: english) == nil)
    }

    // The card and the sweep read one rule: a loose end is past its fade date exactly when the
    // sweep would fade it.
    @Test @MainActor func theSweepFadesOnTheDayTheCardNames() {
        let end = LooseEnd(text: "t", sourceEntryID: UUID(), sourceEntryDate: date(9, 1))
        let facts = LooseEndFacts(id: end.id, text: end.text, sourceEntryDate: end.sourceEntryDate, lastMentionedAt: end.lastMentionedAt)
        #expect(!LooseEnd.shouldFade(end, now: facts.fadeDate))
        #expect(LooseEnd.shouldFade(end, now: facts.fadeDate.addingTimeInterval(1)))
    }
}
