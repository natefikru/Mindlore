import Foundation
import Testing
@testable import Mindlore

// Pure edge cases for the two reused signals, asked about a past week's end rather than now.
struct ReflectSignalsTests {
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    // MARK: - Loose ends

    @Test func aLooseEndOpenedBeforeTheWeekEndsIsStillOpen() {
        let end = LooseEndFacts(id: UUID(), text: "call the landlord", sourceEntryDate: date(2026, 9, 1))
        let result = ReflectSignals.stillOpen([end], asOf: date(2026, 9, 6))
        #expect(result.map(\.id) == [end.id])
    }

    // A loose end opened after a past week closed can't have been open "at" that week: the week
    // simply hadn't reached it yet.
    @Test func aLooseEndOpenedAfterTheWeekEndsIsNotCounted() {
        let end = LooseEndFacts(id: UUID(), text: "call the landlord", sourceEntryDate: date(2026, 9, 10))
        let result = ReflectSignals.stillOpen([end], asOf: date(2026, 9, 6))
        #expect(result.isEmpty)
    }

    @Test func aLooseEndOpenedTheDayBeforeTheWeekStartsIsStillOpen() {
        // The week is 2026-09-07 through 2026-09-13; the loose end predates it entirely.
        let end = LooseEndFacts(id: UUID(), text: "renew the lease", sourceEntryDate: date(2026, 9, 6))
        let result = ReflectSignals.stillOpen([end], asOf: date(2026, 9, 13))
        #expect(result.map(\.id) == [end.id])
    }

    // The bug this guards against: returning every qualifying loose end flooded a week with the
    // journal's whole backlog instead of the one thread most worth surfacing.
    @Test func onlyTheOldestStillOpenLooseEndSurfaces() {
        let older = LooseEndFacts(id: UUID(), text: "renew the lease", sourceEntryDate: date(2026, 8, 1))
        let newer = LooseEndFacts(id: UUID(), text: "call the landlord", sourceEntryDate: date(2026, 9, 1))
        let result = ReflectSignals.stillOpen([newer, older], asOf: date(2026, 9, 6))
        #expect(result.map(\.id) == [older.id])
    }

    @Test func aResolvedLooseEndIsNeverStillOpen() {
        var end = LooseEndFacts(id: UUID(), text: "call the landlord", sourceEntryDate: date(2026, 9, 1))
        end = LooseEndFacts(id: end.id, text: end.text, status: .resolved, sourceEntryDate: end.sourceEntryDate)
        let result = ReflectSignals.stillOpen([end], asOf: date(2026, 9, 6))
        #expect(result.isEmpty)
    }

    // MARK: - Quiet names

    @Test func anEntityLastLinkedOverAMonthBeforeTheWeekEndsIsQuiet() {
        let entity = EntityFacts(id: UUID(), name: "Maya", linkCount: 4, lastLinkedAt: date(2026, 7, 1))
        let result = ReflectSignals.quiet([entity], asOf: date(2026, 9, 6))
        #expect(result.map(\.id) == [entity.id])
    }

    // Quiet as of the week's end, not as of today: an entity mentioned again since that week
    // (but still over 30 days before now) should not be flagged for a week it wasn't quiet at.
    @Test func anEntityLinkedAgainAfterTheWeekIsNotQuietForThatWeek() {
        let entity = EntityFacts(id: UUID(), name: "Maya", linkCount: 4, lastLinkedAt: date(2026, 9, 5))
        let result = ReflectSignals.quiet([entity], asOf: date(2026, 9, 6))
        #expect(result.isEmpty, "linked five days before this week's end, nowhere near the 30-day threshold")
    }

    // The bug this guards against: most of a journal's cast goes 30 days unmentioned in any given
    // week, so returning everyone who qualified used to flood a week with dozens of cards instead
    // of the one name most worth surfacing.
    @Test func onlyTheBestQuietNameSurfacesRankedByLinkCountThenStaleness() {
        let minor = EntityFacts(id: UUID(), name: "Harbor Cafe", linkCount: 1, lastLinkedAt: date(2026, 1, 1))
        let major = EntityFacts(id: UUID(), name: "Maya", linkCount: 12, lastLinkedAt: date(2026, 7, 1))
        let result = ReflectSignals.quiet([minor, major], asOf: date(2026, 9, 6))
        #expect(result.map(\.id) == [major.id], "the most-linked name wins over a barely-mentioned place")
    }

    @Test func anEntityWithNoLinksIsNeverQuiet() {
        let entity = EntityFacts(id: UUID(), name: "Maya", linkCount: 0, lastLinkedAt: date(2026, 1, 1))
        let result = ReflectSignals.quiet([entity], asOf: date(2026, 9, 6))
        #expect(result.isEmpty)
    }

    @Test func composedItemsCarryTheirSourceAndAStablePrompt() {
        let end = LooseEndFacts(id: UUID(), text: "call the landlord", sourceEntryDate: date(2026, 9, 1))
        let entity = EntityFacts(id: UUID(), name: "Maya", linkCount: 4, lastLinkedAt: date(2026, 6, 1))
        let items = ReflectSignals.compose(looseEnds: [end], entities: [entity], weekEnd: date(2026, 9, 6))

        #expect(items.count == 2)
        #expect(items.contains { $0.source == .looseEnd(end.id) && $0.prompt == end.text })
        #expect(items.contains { $0.source == .quietName(entity.id) && $0.prompt.contains("Maya") })
    }
}
