import Foundation
import Testing
@testable import Mindlore

// The journal in the shape Notes uses. Every case is dated against a fixed "now" in a fixed zone,
// so nothing here depends on when the suite runs.
struct JournalGroupsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // Fixed, or the machine's own locale decides whether a month reads "August" or "M08"
        // and the week starts on a different day.
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 1
        return calendar
    }

    // Thursday 17 September 2026, 14:00 UTC, built from the calendar rather than an epoch
    // constant, so the date is what it says it is.
    private var now: Date { day(2026, 9, 17, hour: 14) }

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return calendar.date(from: components)!
    }

    private func group(_ date: Date, now: Date? = nil) -> JournalGroup {
        JournalGroups.group(for: date, now: now ?? self.now, calendar: calendar)
    }

    @Test func todayIsRecentWhateverTheHour() {
        #expect(group(day(2026, 9, 17, hour: 0)) == .recent)
        #expect(group(day(2026, 9, 17, hour: 23)) == .recent)
    }

    // An entry written at 8pm today has a date later than "now". Comparing instants rather than
    // days would flip it into Later on every re-render.
    @Test func laterTodayIsStillRecentNotLater() {
        #expect(group(day(2026, 9, 17, hour: 20)) == .recent)
        #expect(group(day(2026, 9, 18)) == .later)
    }

    @Test func yesterdayIsItsOwnGroup() {
        #expect(group(day(2026, 9, 16)) == .yesterday)
    }

    @Test func theRestOfThisWeekIsThisWeek() {
        // The week containing Wednesday the 17th starts Sunday the 13th.
        #expect(group(day(2026, 9, 15)) == .thisWeek)
        #expect(group(day(2026, 9, 13)) == .thisWeek)
        // Saturday the 12th is the week before.
        #expect(group(day(2026, 9, 12)) == .month(year: 2026, month: 9))
    }

    @Test func earlierThisMonthButOutsideTheWeekIsItsMonth() {
        #expect(group(day(2026, 9, 2)) == .month(year: 2026, month: 9))
        #expect(group(day(2026, 8, 20)) == .month(year: 2026, month: 8))
    }

    @Test func anEarlierYearCollapsesIntoThatYear() {
        #expect(group(day(2025, 12, 31)) == .year(2025))
        #expect(group(day(2025, 1, 1)) == .year(2025))
        #expect(group(day(2024, 6, 6)) == .year(2024))
    }

    // On 2 January, "this week" reaches back into December. That is right, and the rest of
    // December still belongs to its own year.
    @Test func aWeekSpanningTheYearBoundary() {
        let january2 = day(2027, 1, 2)
        #expect(group(day(2026, 12, 30), now: january2) == .thisWeek)
        #expect(group(day(2026, 12, 15), now: january2) == .year(2026))
        #expect(group(day(2027, 1, 1), now: january2) == .yesterday)
        #expect(group(january2, now: january2) == .recent)
    }

    @Test func buildKeepsTheGivenOrderAndGroupsInIt() {
        let ids = (0..<5).map { _ in UUID() }
        let dated = [
            JournalGroups.Dated(id: ids[0], date: day(2026, 9, 17)),
            JournalGroups.Dated(id: ids[1], date: day(2026, 9, 16)),
            JournalGroups.Dated(id: ids[2], date: day(2026, 9, 15)),
            JournalGroups.Dated(id: ids[3], date: day(2026, 8, 4)),
            JournalGroups.Dated(id: ids[4], date: day(2025, 3, 3)),
        ]

        let built = JournalGroups.build(dated, now: now, calendar: calendar)

        #expect(built.map(\.group) == [.recent, .yesterday, .thisWeek, .month(year: 2026, month: 8), .year(2025)])
        #expect(built.map(\.ids) == [[ids[0]], [ids[1]], [ids[2]], [ids[3]], [ids[4]]])
    }

    @Test func entriesInOneGroupStayTogetherInOrder() {
        let first = UUID(), second = UUID(), other = UUID()
        let dated = [
            JournalGroups.Dated(id: first, date: day(2026, 9, 17, hour: 18)),
            JournalGroups.Dated(id: second, date: day(2026, 9, 17, hour: 9)),
            JournalGroups.Dated(id: other, date: day(2026, 9, 16)),
        ]

        let built = JournalGroups.build(dated, now: now, calendar: calendar)

        #expect(built.count == 2)
        #expect(built[0].ids == [first, second])
    }

    // A section's swipe gives an offset into that section. No test can drive SwiftUI's own
    // onDelete, so the mapping is a named function and this is what proves it.
    @Test func deletingUsesTheSectionsOwnOffsets() {
        let ids = [UUID(), UUID(), UUID()]

        #expect(JournalGroups.id(at: 0, in: ids) == ids[0])
        #expect(JournalGroups.id(at: 2, in: ids) == ids[2])
        #expect(JournalGroups.id(at: 3, in: ids) == nil)
        #expect(JournalGroups.ids(at: IndexSet([0, 2]), in: ids) == [ids[0], ids[2]])
        #expect(JournalGroups.ids(at: IndexSet([5]), in: ids).isEmpty)
    }

    @Test func titlesReadLikeNotes() {
        #expect(JournalGroups.title(.later, calendar: calendar) == "Later")
        #expect(JournalGroups.title(.recent, calendar: calendar) == "Recent")
        #expect(JournalGroups.title(.yesterday, calendar: calendar) == "Yesterday")
        #expect(JournalGroups.title(.thisWeek, calendar: calendar) == "This week")
        #expect(JournalGroups.title(.month(year: 2026, month: 8), calendar: calendar) == "August")
        #expect(JournalGroups.title(.year(2025), calendar: calendar) == "2025")
    }

    // A DST day is 23 or 25 hours long, which is why the grouping compares days and not spans.
    @Test func aDaylightSavingChangeDoesNotShiftAGroup() {
        var pacific = Calendar(identifier: .gregorian)
        pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        // 8 November 2026 is the Sunday the clocks go back.
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 8
        components.hour = 23
        let springBack = pacific.date(from: components)!
        components.hour = 1
        let sameDayEarly = pacific.date(from: components)!

        #expect(JournalGroups.group(for: springBack, now: springBack, calendar: pacific) == .recent)
        #expect(JournalGroups.group(for: sameDayEarly, now: springBack, calendar: pacific) == .recent)
    }

    // The row says only what the header leaves out.
    // The claim is relative, not a literal string: formatting follows the machine's locale and
    // zone, so the test says the header's group makes the row's date shorter.
    @Test func theRowDateShortensToSuitItsGroup() {
        let date = day(2026, 8, 4, hour: 15)
        let ungrouped = EntryDateText.rowText(date, dayOnly: false, group: nil)

        for group in [JournalGroup.recent, .yesterday, .thisWeek, .month(year: 2026, month: 8), .year(2025)] {
            let text = EntryDateText.rowText(date, dayOnly: false, group: group)
            #expect(!text.isEmpty, "\(group) should still say something")
            #expect(text.count < ungrouped.count, "\(group) should be shorter than \(ungrouped)")
        }
        // A day the user picked has no meaningful time, and the header already gives the day.
        #expect(EntryDateText.rowText(date, dayOnly: true, group: .recent).isEmpty)
    }
}

struct JournalFilterMultiSelectTests {
    // Any of them, not all.
    @Test func anEntryMatchingAnySelectedAreaShows() {
        #expect(JournalFilter.matches(areasRaw: ["work"], areas: [.work, .health]))
        #expect(JournalFilter.matches(areasRaw: ["health"], areas: [.work, .health]))
        #expect(JournalFilter.matches(areasRaw: ["work", "money"], areas: [.money]))
        #expect(!JournalFilter.matches(areasRaw: ["play"], areas: [.work, .health]))
        #expect(!JournalFilter.matches(areasRaw: [], areas: [.work]))
    }

    @Test func aHiddenAreaDropsOutOfTheSelection() {
        #expect(JournalFilter.active([.work, .health], hidden: ["health"]) == [.work])
        #expect(JournalFilter.active([.work], hidden: ["work"]).isEmpty)
        #expect(JournalFilter.active([.work, .health], hidden: []) == [.work, .health])
    }

    @Test func theEmptyStateNamesWhatIsSelected() {
        #expect(JournalFilter.emptyStateTitle(["Work"]) == "Nothing in Work")
        #expect(JournalFilter.emptyStateTitle(["Work", "Health"]) == "Nothing in Work or Health")
        #expect(JournalFilter.emptyStateTitle(["Work", "Health", "Play"]) == "Nothing in Work, Health or Play")
        #expect(JournalFilter.emptyStateTitle(["Work", "Health", "Play", "Home"]) == "Nothing in Work, Health and 2 more")
    }

    @Test func offeredAreasAreUnchanged() {
        let offered = JournalFilter.offered(entryAreas: [["work"], ["health", "work"]], hidden: ["health"])
        #expect(offered == [.work])
    }
}
