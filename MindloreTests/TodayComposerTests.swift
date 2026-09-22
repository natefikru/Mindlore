import Foundation
import Testing
@testable import Mindlore

// The composer is pure, so every rule is a plain function call: no container, no view, no clock.
struct TodayComposerTests {
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private var now: Date { date(2026, 9, 19) }

    private func entry(
        _ day: Date,
        title: String = "an entry",
        summary: String? = nil,
        areas: [LifeArea] = []
    ) -> EntryFacts {
        EntryFacts(id: UUID(), entryDate: day, title: title, summary: summary, areas: areas)
    }

    private func looseEnd(
        _ text: String = "call the landlord",
        opened: Date,
        status: LooseEndStatus = .open,
        due: Date? = nil,
        resolvedBy: UUID? = nil
    ) -> LooseEndFacts {
        LooseEndFacts(
            id: UUID(), text: text, status: status, sourceEntryDate: opened,
            dueDate: due, resolvedByEntryID: resolvedBy
        )
    }

    private func entity(_ name: String, links: Int = 5, lastSeen: Date?) -> EntityFacts {
        EntityFacts(id: UUID(), name: name, kind: .person, linkCount: links, lastLinkedAt: lastSeen)
    }

    private func input(
        entries: [EntryFacts] = [],
        looseEnds: [LooseEndFacts] = [],
        entities: [EntityFacts] = [],
        at moment: Date? = nil,
        dismissed: Set<String> = [],
        resurfacing: Bool = true
    ) -> TodayInput {
        TodayInput(
            entries: entries, looseEnds: looseEnds, entities: entities,
            now: moment ?? now, calendar: utc, dismissed: dismissed, resurfacingEnabled: resurfacing
        )
    }

    // MARK: - The empty case

    @Test func anEmptyJournalIsAGreetingAndNothingElse() {
        let today = TodayComposer.compose(input())

        #expect(today.cards.isEmpty)
        #expect(today.week.isEmpty, "a strip of seven empty dots would be an accusation")
        #expect(!today.greeting.isEmpty)
    }

    // MARK: - Priority

    @Test func aClosedThreadComesFirst() {
        let latest = entry(now, summary: "a summary")
        let closed = looseEnd(opened: date(2026, 9, 3), status: .resolved, resolvedBy: latest.id)

        let today = TodayComposer.compose(input(entries: [latest], looseEnds: [closed]))

        #expect(today.cards.first == .closed(closed))
    }

    @Test func aThreadDueTodayComesFirstWhenNothingClosed() {
        let latest = entry(now)
        let due = looseEnd(opened: date(2026, 9, 3), due: date(2026, 9, 19, hour: 9))

        let today = TodayComposer.compose(input(entries: [latest], looseEnds: [due]))

        #expect(today.cards.first == .dueToday(due))
    }

    @Test func aThreadClosedByAnOlderEntryIsNotTodaysNews() {
        let latest = entry(now)
        let older = entry(date(2026, 9, 10))
        let closed = looseEnd(opened: date(2026, 9, 3), status: .resolved, resolvedBy: older.id)

        let today = TodayComposer.compose(input(entries: [latest, older], looseEnds: [closed]))

        #expect(!today.cards.contains { $0.kind == .closed })
    }

    @Test func theFullRowComesOutInOrder() {
        let latest = entry(now, summary: "a summary")
        let yearAgo = entry(date(2025, 9, 19))
        let closed = looseEnd("the landlord", opened: date(2026, 9, 3), status: .resolved, resolvedBy: latest.id)
        let due = looseEnd("the form", opened: date(2026, 9, 1), due: date(2026, 9, 19, hour: 9))
        let open = looseEnd("the dentist", opened: date(2026, 9, 4))
        let lapsed = entity("Maya", lastSeen: date(2026, 7, 1))

        let today = TodayComposer.compose(input(
            entries: [latest, yearAgo], looseEnds: [closed, due, open], entities: [lapsed]
        ))

        #expect(today.cards.map(\.kind) == [.dueToday, .closed, .onThisDay, .beenAWhile, .latestSummary, .stillOpen])
    }

    // The row is something to go through, not a top three: every open thread has a card.
    @Test func everyOpenThreadGetsACard() {
        let threads = (1...12).map { looseEnd("thread \($0)", opened: date(2026, 9, $0)) }

        let cards = TodayComposer.compose(input(entries: [entry(now)], looseEnds: threads)).cards

        #expect(cards.filter { $0.kind == .stillOpen }.count == 12)
    }

    // A thread is put away by acting on it, never by "not today": it stays until done, let go,
    // or faded.
    @Test func aThreadIgnoresTheDaysDismissals() {
        let open = looseEnd(opened: date(2026, 9, 4))

        let today = TodayComposer.compose(input(
            entries: [entry(now)], looseEnds: [open], dismissed: [TodayCard.stillOpen(open).id]
        ))

        #expect(today.cards == [.stillOpen(open)])
    }

    // MARK: - Nothing twice

    @Test func oneLooseEndNeverFillsTwoCards() {
        let latest = entry(now)
        let due = looseEnd(opened: date(2026, 1, 4), due: date(2026, 9, 19))

        let today = TodayComposer.compose(input(entries: [latest], looseEnds: [due]))

        #expect(today.cards.map(\.kind) == [.dueToday], "it is also the oldest open thread")
    }

    // A journal a year and a day old: its newest entry is also the entry from a year ago.
    @Test func oneEntryNeverFillsTwoCards() {
        let only = entry(date(2025, 9, 19), summary: "a summary")

        let today = TodayComposer.compose(input(entries: [only]))

        #expect(today.cards.map(\.kind) == [.onThisDay])
    }

    // MARK: - On this day

    @Test func theFurthestBackAnniversaryWins() {
        let lastYear = entry(date(2025, 9, 19), title: "last year")
        let longAgo = entry(date(2021, 9, 19), title: "five years ago")

        let today = TodayComposer.compose(input(entries: [lastYear, longAgo]))

        #expect(today.cards.first == .onThisDay(longAgo, .yearsAgo(5)))
    }

    @Test func dismissingTheAnniversaryDoesNotPromoteAnother() {
        let lastYear = entry(date(2025, 9, 19))
        let longAgo = entry(date(2021, 9, 19))
        let dismissed = TodayCard.onThisDay(longAgo, .yearsAgo(5)).id

        let today = TodayComposer.compose(input(entries: [lastYear, longAgo], dismissed: [dismissed]))

        #expect(!today.cards.contains { $0.kind == .onThisDay })
    }

    @Test func aYearsAgoEntryBeatsAMonthAgoOne() {
        let monthAgo = entry(date(2026, 8, 19))
        let yearAgo = entry(date(2025, 9, 19))

        let today = TodayComposer.compose(input(entries: [monthAgo, yearAgo]))

        #expect(today.cards.first == .onThisDay(yearAgo, .yearsAgo(1)))
    }

    @Test func aMonthAgoBeatsSixMonthsAgo() {
        let monthAgo = entry(date(2026, 8, 19))
        let halfYear = entry(date(2026, 3, 19))

        let today = TodayComposer.compose(input(entries: [monthAgo, halfYear]))

        #expect(today.cards.first == .onThisDay(monthAgo, .monthAgo))
    }

    // MARK: - The calendar

    @Test func aLeapDayEntrySurfacesOnTheTwentyEighthInAnOrdinaryYear() {
        let leapDay = entry(date(2024, 2, 29))

        let today = TodayComposer.compose(input(entries: [leapDay], at: date(2026, 2, 28)))

        #expect(today.cards.first == .onThisDay(leapDay, .yearsAgo(2)))
    }

    @Test func aLeapDayEntryKeepsItsOwnDayInALeapYear() {
        let leapDay = entry(date(2024, 2, 29))

        let onTheDay = TodayComposer.compose(input(entries: [leapDay], at: date(2028, 2, 29)))
        let dayBefore = TodayComposer.compose(input(entries: [leapDay], at: date(2028, 2, 28)))

        #expect(onTheDay.cards.first == .onThisDay(leapDay, .yearsAgo(4)))
        #expect(dayBefore.cards.isEmpty, "the 29th exists this year, so the 28th is not its anniversary")
    }

    @Test func aTwentyEighthOfFebruaryEntryDoesNotDuplicateOntoALeapDay() {
        let february = entry(date(2025, 2, 28))

        let today = TodayComposer.compose(input(entries: [february], at: date(2028, 2, 29)))

        #expect(today.cards.isEmpty)
    }

    // Calendar clamps 31 March minus one month onto the end of February. Documented rather than
    // fought: "a month ago" means the day the user would name, and that is what Calendar says.
    @Test func aMonthBeforeTheThirtyFirstLandsOnTheEndOfFebruary() {
        let february = entry(date(2026, 2, 28))

        let today = TodayComposer.compose(input(entries: [february], at: date(2026, 3, 31)))

        #expect(today.cards.first == .onThisDay(february, .monthAgo))
    }

    @Test func aDayOnlyEntryMatchesOnItsDayNotItsHour() {
        let noon = EntryFacts(id: UUID(), entryDate: date(2025, 9, 19), entryDateIsDayOnly: true)

        let earlyToday = TodayComposer.compose(input(entries: [noon], at: date(2026, 9, 19, hour: 1)))
        let lateToday = TodayComposer.compose(input(entries: [noon], at: date(2026, 9, 19, hour: 23)))

        #expect(earlyToday.cards.first == .onThisDay(noon, .yearsAgo(1)))
        #expect(lateToday.cards.first == .onThisDay(noon, .yearsAgo(1)))
    }

    // MARK: - A clock that steps back

    @Test func anEntryDatedAheadOfNowIsNotYetAnythingsAnniversary() {
        let future = entry(date(2027, 9, 19), summary: "not yet")

        let today = TodayComposer.compose(input(entries: [future]))

        #expect(today.cards.isEmpty, "never a card, and never a negative span")
    }

    @Test func aFutureEntryIsNotTheLatestEntry() {
        let future = entry(date(2027, 1, 1), summary: "from the future")
        let real = entry(date(2026, 9, 18), summary: "the real last entry")

        let today = TodayComposer.compose(input(entries: [future, real]))

        #expect(today.cards == [.latestSummary(real)])
    }

    @Test func aFutureEntryDoesNotFillAWeekDot() {
        let future = entry(date(2026, 9, 25))
        let real = entry(date(2026, 9, 18))

        let week = TodayComposer.compose(input(entries: [future, real])).week

        #expect(week.filter(\.hasEntry).count == 1)
    }

    // MARK: - Still open, and been a while

    // The first thread card is the one that most needs you: whichever fades soonest. A dated one
    // fades a week after its day; an undated one six weeks after it was last written about.
    @Test func threadsComeInTheOrderTheyWouldFade() {
        let quietLong = looseEnd("the dentist", opened: date(2026, 8, 20))
        let dueSoon = looseEnd("the form", opened: date(2026, 9, 15), due: date(2026, 9, 22))
        let recent = LooseEndFacts(id: UUID(), text: "the landlord", sourceEntryDate: date(2026, 8, 1), lastMentionedAt: date(2026, 9, 18))

        let cards = TodayComposer.compose(input(entries: [entry(now)], looseEnds: [recent, quietLong, dueSoon])).cards

        #expect(cards.compactMap(\.thread) == [dueSoon, quietLong, recent])
    }

    @Test func aFadedOrResolvedThreadIsNotOpen() {
        let faded = looseEnd("faded", opened: date(2025, 3, 1), status: .faded)
        let dismissed = looseEnd("dismissed", opened: date(2025, 3, 2), status: .dismissed)
        let resolved = looseEnd("resolved", opened: date(2025, 3, 3), status: .resolved)

        let today = TodayComposer.compose(input(
            entries: [entry(now)], looseEnds: [faded, dismissed, resolved]
        ))

        #expect(!today.cards.contains { $0.kind == .stillOpen })
    }

    // One name all day, a different one the next: the best-linked quiet person no longer holds
    // the card until someone writes about them.
    @Test func theQuietNameChangesDailyAndHoldsWithinADay() {
        let people = ["Maya", "Tom", "Priya"].enumerated().map { index, name in
            entity(name, links: 12 - index, lastSeen: date(2026, 6, 1))
        }
        func shown(_ moment: Date) -> EntityFacts? {
            TodayComposer.compose(input(entries: [entry(now)], entities: people, at: moment)).cards
                .compactMap { if case .beenAWhile(let who) = $0 { who } else { nil } }.first
        }

        #expect(shown(date(2026, 9, 19, hour: 8)) == shown(date(2026, 9, 19, hour: 22)))
        #expect(Set((19...21).compactMap { shown(date(2026, 9, $0))?.name }).count == 3)
    }

    @Test func thirtyDaysIsNotYetAWhile() {
        let exactly = entity("Maya", lastSeen: now.addingTimeInterval(-TodayComposer.staleAfter))
        let aSecondLess = entity("Maya", lastSeen: now.addingTimeInterval(-TodayComposer.staleAfter + 1))
        let aSecondMore = entity("Maya", lastSeen: now.addingTimeInterval(-TodayComposer.staleAfter - 1))

        func shows(_ who: EntityFacts) -> Bool {
            TodayComposer.compose(input(entries: [entry(now)], entities: [who]))
                .cards.contains { $0.kind == .beenAWhile }
        }

        #expect(shows(exactly) == false)
        #expect(shows(aSecondLess) == false)
        #expect(shows(aSecondMore) == true)
    }

    @Test func someoneNeverLinkedIsNotSomeoneWhoWentQuiet() {
        let never = EntityFacts(id: UUID(), name: "Maya", linkCount: 0, lastLinkedAt: nil)

        let today = TodayComposer.compose(input(entries: [entry(now)], entities: [never]))

        #expect(!today.cards.contains { $0.kind == .beenAWhile })
    }

    // MARK: - Dismissal, and the switch

    @Test func aDismissedCardStepsAsideForTheNextKind() {
        let latest = entry(now, summary: "a summary")
        let closed = looseEnd(opened: date(2026, 9, 3), status: .resolved, resolvedBy: latest.id)
        let dismissed = TodayCard.closed(closed).id

        let today = TodayComposer.compose(input(
            entries: [latest], looseEnds: [closed], dismissed: [dismissed]
        ))

        #expect(today.cards.map(\.kind) == [.latestSummary], "the slot is filled, not left empty")
    }

    // The same bug would pass either test alone: "off" must mean never a candidate, while
    // "dismissed" means gone for today only.
    @Test func turningResurfacingOffIsNotTheSameAsDismissingIt() {
        let lapsed = entity("Maya", lastSeen: date(2026, 6, 1))
        let only = input(entries: [entry(now)], entities: [lapsed])

        let on = TodayComposer.compose(only)
        let off = TodayComposer.compose(input(entries: [entry(now)], entities: [lapsed], resurfacing: false))
        let dismissed = TodayComposer.compose(input(
            entries: [entry(now)], entities: [lapsed], dismissed: [TodayCard.beenAWhile(lapsed).id]
        ))

        #expect(on.cards.contains { $0.kind == .beenAWhile })
        #expect(!off.cards.contains { $0.kind == .beenAWhile })
        #expect(!dismissed.cards.contains { $0.kind == .beenAWhile })
    }

    @Test func aDismissalKeyNamesNobody() {
        let lapsed = entity("Maya Okonkwo", lastSeen: date(2026, 6, 1))
        let end = looseEnd("call the landlord about the boiler", opened: date(2026, 1, 1))

        #expect(!TodayCard.beenAWhile(lapsed).id.contains("Maya"))
        #expect(!TodayCard.stillOpen(end).id.contains("landlord"))
    }

    // MARK: - The week strip

    @Test func theWeekIsSevenDaysEndingToday() {
        let week = TodayComposer.compose(input(entries: [entry(now)])).week

        #expect(week.count == 7)
        #expect(week.last.map { utc.isDate($0.date, inSameDayAs: now) } == true)
        #expect(week.first.map { utc.isDate($0.date, inSameDayAs: date(2026, 9, 13)) } == true)
    }

    @Test func aDayWithAnEntryIsFilledAndTakesItsColour() {
        let written = entry(date(2026, 9, 17), areas: [.work, .money])

        let week = TodayComposer.compose(input(entries: [written])).week

        let day = week.first { utc.isDate($0.date, inSameDayAs: date(2026, 9, 17)) }
        #expect(day?.hasEntry == true)
        #expect(day?.tint == .work)
        #expect(week.filter(\.hasEntry).count == 1)
    }

    @Test func anEntryOlderThanTheWeekFillsNoDot() {
        let week = TodayComposer.compose(input(entries: [entry(date(2026, 8, 1))])).week

        #expect(week.allSatisfy { !$0.hasEntry })
    }

    // MARK: - Greeting

    @Test func theGreetingFollowsTheHourAndUsesTheNameWhenThereIsOne() {
        #expect(TodayCopy.greeting(at: date(2026, 9, 19, hour: 8), calendar: utc) == "Good morning")
        #expect(TodayCopy.greeting(at: date(2026, 9, 19, hour: 14), calendar: utc) == "Good afternoon")
        #expect(TodayCopy.greeting(at: date(2026, 9, 19, hour: 21), calendar: utc) == "Good evening")
        #expect(TodayCopy.greeting(at: date(2026, 9, 19, hour: 8), calendar: utc, name: "Nate") == "Good morning, Nate")
    }
}
