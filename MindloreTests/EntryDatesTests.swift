import Foundation
import SwiftData
import Testing
@testable import Mindlore

@MainActor
struct EntryDatesTests {
    private func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    private func components(_ date: Date, in calendar: Calendar) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    @Test func noonKeepsTheCalendarDay() {
        let newYork = calendar("America/New_York")
        let lateNight = newYork.date(from: DateComponents(year: 2025, month: 3, day: 3, hour: 23, minute: 50))!
        let noon = EntryDates.noon(of: lateNight, calendar: newYork)

        #expect(components(noon, in: newYork) == DateComponents(year: 2025, month: 3, day: 3, hour: 12, minute: 0))
    }

    @Test func noonOnADaylightSavingChangeDay() {
        let newYork = calendar("America/New_York")
        // Clocks sprang forward at 2 AM on March 9, 2025.
        let parsed = EntryDates.parseDay("2025-03-09", calendar: newYork)
        #expect(parsed.map { components($0, in: newYork) } == DateComponents(year: 2025, month: 3, day: 9, hour: 12, minute: 0))
    }

    @Test func parsesOnlyCompleteValidDays() {
        let utc = calendar("UTC")
        #expect(EntryDates.parseDay("2025-03-03", calendar: utc) != nil)
        #expect(EntryDates.parseDay(" 2025-03-03 ", calendar: utc) != nil)
        #expect(EntryDates.parseDay("2025-02-30", calendar: utc) == nil)
        #expect(EntryDates.parseDay("2025-03", calendar: utc) == nil)
        #expect(EntryDates.parseDay("03-03-2025", calendar: utc) == nil)
        #expect(EntryDates.parseDay("2025-3-3", calendar: utc) == nil)
        #expect(EntryDates.parseDay("", calendar: utc) == nil)
    }

    @Test func noonStaysOnItsDayAcrossSmallTimeZoneChanges() {
        let newYork = calendar("America/New_York")
        let picked = EntryDates.parseDay("2025-03-03", calendar: newYork)!
        for zone in ["America/Los_Angeles", "Europe/London", "Europe/Berlin", "Pacific/Honolulu"] {
            #expect(calendar(zone).component(.day, from: picked) == 3, "shifted in \(zone)")
        }
    }

    @Test func pickingADayStoresNoonAndHidesTheTime() {
        let utc = calendar("UTC")
        let created = Date(timeIntervalSince1970: 1_757_970_000)
        let entry = Entry(createdAt: created, text: "backfilled")
        let march3 = utc.date(from: DateComponents(year: 2025, month: 3, day: 3, hour: 8))!

        entry.setEntryDay(march3, calendar: utc)

        #expect(entry.entryDateIsDayOnly)
        #expect(components(entry.entryDate, in: utc) == DateComponents(year: 2025, month: 3, day: 3, hour: 12, minute: 0))
        #expect(entry.createdAt == created)
        #expect(entry.entryDateDiffersFromCreation(calendar: utc))
    }

    @Test func useOriginalDateRestoresTheCreationTimestamp() {
        let created = Date(timeIntervalSince1970: 1_757_970_123)
        let entry = Entry(createdAt: created)
        entry.setEntryDay(Date(timeIntervalSince1970: 0))

        entry.useOriginalEntryDate()

        #expect(entry.entryDate == created)
        #expect(!entry.entryDateIsDayOnly)
        #expect(!entry.entryDateDiffersFromCreation())
    }

    @Test func suggestionForTheCurrentDayIsNotStored() {
        let utc = calendar("UTC")
        let created = utc.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 21))!
        let entry = Entry(createdAt: created)

        #expect(entry.storeSuggestedEntryDate(utc.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 1))!, calendar: utc) == false)
        #expect(entry.suggestedEntryDate == nil)
        #expect(entry.storeSuggestedEntryDate(utc.date(from: DateComponents(year: 2025, month: 3, day: 3))!, calendar: utc))
        #expect(entry.shouldShowDateSuggestion(calendar: utc))
    }

    @Test func acceptingASuggestionSetsTheDayAndClearsIt() {
        let utc = calendar("UTC")
        let entry = Entry(createdAt: utc.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 21))!)
        entry.storeSuggestedEntryDate(utc.date(from: DateComponents(year: 2025, month: 3, day: 3))!, calendar: utc)

        entry.acceptSuggestedEntryDate(calendar: utc)

        #expect(entry.suggestedEntryDate == nil)
        #expect(entry.entryDateIsDayOnly)
        #expect(utc.component(.day, from: entry.entryDate) == 3)
    }

    @Test func dismissingASuggestionLeavesTheDate() {
        let entry = Entry(createdAt: Date(timeIntervalSince1970: 1_757_970_000))
        entry.storeSuggestedEntryDate(Date(timeIntervalSince1970: 0))

        entry.dismissSuggestedEntryDate()

        #expect(entry.suggestedEntryDate == nil)
        #expect(entry.entryDate == entry.createdAt)
    }

    @Test func pickingTheSuggestedDayByHandClearsTheSuggestion() {
        let utc = calendar("UTC")
        let entry = Entry(createdAt: utc.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 21))!)
        let march3 = utc.date(from: DateComponents(year: 2025, month: 3, day: 3))!
        entry.storeSuggestedEntryDate(march3, calendar: utc)

        entry.setEntryDay(march3, calendar: utc)

        #expect(entry.suggestedEntryDate == nil)
        #expect(!entry.shouldShowDateSuggestion(calendar: utc))
    }

    @Test func listOrderFollowsEntryDateWithCreationAsTieBreaker() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let utc = calendar("UTC")
        let recent = Entry(createdAt: utc.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 9))!, text: "recent")
        let backfilledFirst = Entry(createdAt: utc.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 10))!, text: "backfilled first")
        let backfilledSecond = Entry(createdAt: utc.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 11))!, text: "backfilled second")
        let march3 = utc.date(from: DateComponents(year: 2025, month: 3, day: 3))!
        backfilledFirst.setEntryDay(march3, calendar: utc)
        backfilledSecond.setEntryDay(march3, calendar: utc)
        [recent, backfilledFirst, backfilledSecond].forEach(context.insert)
        try context.save()

        let descriptor = FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.entryDate, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)])
        #expect(try context.fetch(descriptor).map(\.text) == ["recent", "backfilled second", "backfilled first"])
    }
}
