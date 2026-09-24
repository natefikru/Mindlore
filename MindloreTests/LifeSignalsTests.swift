import CoreGraphics
import Foundation
import Testing
@testable import Mindlore

struct LifeSignalsTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    // Enough journal for a reading: 25 plain entries spread over the last 80 days, no areas.
    private var padding: [LifeSignals.EntryFact] {
        (0..<25).map { LifeSignals.EntryFact(date: daysAgo(Double($0) * 3 + 0.5)) }
    }

    private func entries(_ count: Int, area: LifeArea, valence: Int?, from start: Double, every step: Double = 2, tags: [String] = []) -> [LifeSignals.EntryFact] {
        (0..<count).map { LifeSignals.EntryFact(date: daysAgo(start + Double($0) * step), areas: [area], valence: valence, tags: tags) }
    }

    // MARK: - Floors

    @Test func noReadingUntilTwentyEntriesOverThreeWeeks() {
        let tooFew = (0..<19).map { LifeSignals.EntryFact(date: daysAgo(Double($0) * 2)) }
        #expect(LifeSignals.reading(entries: tooFew, threads: [], window: .quarter, now: now) == nil)
        let tooShort = (0..<30).map { LifeSignals.EntryFact(date: daysAgo(Double($0) * 0.5)) }
        #expect(LifeSignals.progress(tooShort).days < LifeSignals.minimumDays)
        #expect(LifeSignals.reading(entries: tooShort, threads: [], window: .quarter, now: now) == nil)
        #expect(LifeSignals.reading(entries: padding, threads: [], window: .quarter, now: now) != nil)
    }

    @Test func anAreaNeedsThreeEntriesAndThreeMoodsForAHeight() {
        let facts = padding
            + entries(2, area: .money, valence: -1, from: 1)
            + entries(3, area: .home, valence: nil, from: 1)
            + entries(3, area: .work, valence: 1, from: 1)
        let reading = LifeSignals.reading(entries: facts, threads: [], window: .quarter, now: now)!
        #expect(!reading.areas.contains { $0.area == .money }, "two entries is too few")
        #expect(reading.areas.first { $0.area == .home }?.height == nil, "no moods, no height")
        #expect(reading.areas.first { $0.area == .work }?.height != nil)
    }

    @Test func hiddenAreasNeverAppear() {
        let facts = padding + entries(5, area: .love, valence: 1, from: 1)
        let reading = LifeSignals.reading(entries: facts, threads: [], window: .quarter, now: now, hidden: [.love])!
        #expect(reading.areas.isEmpty)
    }

    // MARK: - Baseline and height

    @Test func heightIsAgainstTheAuthorsOwnBaseline() {
        // A journal that runs heavy overall: work at -1 is only a little heavier than usual, and
        // friends at 0 is lighter than usual.
        let heavy = (0..<20).map { LifeSignals.EntryFact(date: daysAgo(Double($0) * 4 + 1), valence: -1) }
        let facts = heavy
            + entries(5, area: .work, valence: -1, from: 1)
            + entries(5, area: .friends, valence: 0, from: 2)
        let reading = LifeSignals.reading(entries: facts, threads: [], window: .quarter, now: now)!
        let base = reading.baseline!
        #expect(base < -0.5)
        let friends = reading.areas.first { $0.area == .friends }!.height!
        #expect(friends > 0, "a neutral area reads lighter than a heavy usual")
    }

    @Test func notesAndCreativeWorkCountTowardShareButNotMood() {
        // A fact with no valence is how LifeSource passes a note.
        let facts = padding + entries(4, area: .home, valence: nil, from: 1)
        let reading = LifeSignals.reading(entries: facts, threads: [], window: .quarter, now: now)!
        let home = reading.areas.first { $0.area == .home }!
        #expect(home.entries == 4)
        #expect(home.moods == 0)
    }

    @Test func sharesAreOfEntriesSoTwoAreasCanSumPastAWhole() {
        let both = (0..<20).map { LifeSignals.EntryFact(date: daysAgo(Double($0) * 4 + 1), areas: [.work, .money]) }
        let reading = LifeSignals.reading(entries: both, threads: [], window: .quarter, now: now)!
        #expect(reading.areas.map(\.share).reduce(0, +) > 1.5)
    }

    // MARK: - Headline

    @Test func theHeadlineNamesATwinAndATonOnlyOnEnoughMoods() {
        let lone = [LifeSignals.AreaReading(area: .work, entries: 10, share: 0.5, moods: 9, height: -0.4)]
        #expect(LifeSignals.headline(lone) == LifeSignals.Headline(areas: [.work], tone: .heavier))
        let fewMoods = [LifeSignals.AreaReading(area: .work, entries: 10, share: 0.5, moods: 7, height: -0.4)]
        #expect(LifeSignals.headline(fewMoods)?.tone == nil)
        let small = [LifeSignals.AreaReading(area: .work, entries: 10, share: 0.5, moods: 9, height: -0.2)]
        #expect(LifeSignals.headline(small)?.tone == nil)
        let twins = [
            LifeSignals.AreaReading(area: .work, entries: 10, share: 0.5, moods: 9, height: -0.4),
            LifeSignals.AreaReading(area: .family, entries: 8, share: 0.4, moods: 8, height: 0),
        ]
        #expect(LifeSignals.headline(twins) == LifeSignals.Headline(areas: [.work, .family], tone: nil))
    }

    // MARK: - Quiet and changed

    @Test func anAreaGoesQuietWhenItDropsToAThird() {
        // Love was 8 of the 24 entries in the window before, and is 1 of the window now.
        let before = entries(8, area: .love, valence: 1, from: 100, every: 5) + (0..<16).map { LifeSignals.EntryFact(date: daysAgo(95 + Double($0) * 5)) }
        let current = entries(1, area: .love, valence: 1, from: 10) + (0..<24).map { LifeSignals.EntryFact(date: daysAgo(Double($0) * 3 + 0.5)) }
        let reading = LifeSignals.reading(entries: before + current, threads: [], window: .quarter, now: now)!
        #expect(reading.quiet.map(\.area) == [.love])
        #expect(!reading.changes.contains { $0.area == .love }, "a quiet area isn't also a change")
    }

    @Test func aSmallDropIsNotQuiet() {
        let before = entries(8, area: .love, valence: 1, from: 100, every: 5) + (0..<16).map { LifeSignals.EntryFact(date: daysAgo(95 + Double($0) * 5)) }
        let current = entries(6, area: .love, valence: 1, from: 10) + (0..<20).map { LifeSignals.EntryFact(date: daysAgo(Double($0) * 3 + 0.5)) }
        let reading = LifeSignals.reading(entries: before + current, threads: [], window: .quarter, now: now)!
        #expect(reading.quiet.isEmpty)
    }

    @Test func changesAreTheLargestMovesAboveTheFloor() {
        let now = [
            LifeSignals.AreaReading(area: .work, entries: 20, share: 0.5, moods: 10, height: 0),
            LifeSignals.AreaReading(area: .health, entries: 5, share: 0.13, moods: 6, height: 0.6),
            LifeSignals.AreaReading(area: .home, entries: 4, share: 0.1, moods: 0, height: nil),
        ]
        let before = [
            LifeSignals.AreaReading(area: .work, entries: 8, share: 0.2, moods: 6, height: 0),
            LifeSignals.AreaReading(area: .health, entries: 5, share: 0.12, moods: 5, height: -0.2),
            LifeSignals.AreaReading(area: .home, entries: 4, share: 0.08, moods: 0, height: nil),
        ]
        let changes = LifeSignals.changes(now: now, before: before, skipping: [])
        #expect(changes.map(\.area) == [.health, .work] || changes.map(\.area) == [.work, .health])
        #expect(changes.first { $0.area == .health }?.kind == .tone(.lighter))
        #expect(!changes.contains { $0.area == .home }, "two points is under the floor")
    }

    // MARK: - Recurring

    @Test func aTagRecursAcrossDistinctWeeksOrMonthsAndNeverInAMonth() {
        let weekly = (0..<5).map { LifeSignals.EntryFact(date: daysAgo(Double($0) * 8 + 1), tags: ["running"]) }
        let onceBurst = (0..<6).map { LifeSignals.EntryFact(date: daysAgo(2 + Double($0) * 0.1), tags: ["move"]) }
        let found = LifeSignals.recurring(weekly + onceBurst, window: .quarter, calendar: utc)
        #expect(found.map(\.tag) == ["running"], "six entries in one week is a burst, not a return")
        #expect(found.first?.periods == 5)
        let reading = LifeSignals.reading(entries: padding + weekly, threads: [], window: .month, now: now)!
        #expect(reading.recurring.isEmpty)
    }

    // MARK: - Follow-through

    @Test func followThroughCountsClosedThreadsByTheirEntrysAreas() {
        func thread(_ status: LooseEndStatus, _ area: LifeArea, raised: Double, closed: Double) -> LifeSignals.ThreadFact {
            LifeSignals.ThreadFact(status: status, raisedOn: daysAgo(raised), closedAt: daysAgo(closed), areas: [area])
        }
        let threads = [
            thread(.resolved, .work, raised: 20, closed: 18),
            thread(.resolved, .work, raised: 30, closed: 26),
            thread(.resolved, .work, raised: 40, closed: 37),
            thread(.faded, .work, raised: 60, closed: 10),
            thread(.faded, .family, raised: 70, closed: 20),
            thread(.faded, .family, raised: 70, closed: 21),
            thread(.faded, .family, raised: 70, closed: 22),
            thread(.resolved, .family, raised: 20, closed: 19),
            thread(.resolved, .money, raised: 20, closed: 19),
            LifeSignals.ThreadFact(status: .open, raisedOn: daysAgo(5), areas: [.money]),
        ]
        let reading = LifeSignals.reading(entries: padding, threads: threads, window: .quarter, now: now)!
        let work = reading.followThrough.first { $0.area == .work }!
        #expect(work.closed == 4)
        #expect(work.resolved == 3)
        #expect(work.medianDaysToResolve == 3)
        #expect(!reading.followThrough.contains { $0.area == .money }, "one closed is too few")
        #expect(reading.contrast?.closes.area == .work)
        #expect(reading.contrast?.fades.area == .family)
        #expect(reading.openThreads == 1)
    }

    // MARK: - One area

    @Test func anAreasMonthsRunAcrossTheWindowWithItsTagsAndEntries() {
        let facts = padding + entries(4, area: .health, valence: 1, from: 1, every: 20, tags: ["knee", "running"])
        let detail = LifeSignals.detail(for: .health, entries: facts, threads: [], window: .quarter, now: now, calendar: utc)!
        #expect(detail.months.count >= 3)
        #expect(detail.months.reduce(0) { $0 + $1.entries } == 4)
        #expect(detail.tags.map(\.tag) == ["knee", "running"])
        #expect(detail.entryIDs.count == 4)
    }
}

struct LifeBubbleLayoutTests {
    private func readings(_ shares: [(LifeArea, Double, Double?)]) -> [LifeSignals.AreaReading] {
        shares.map { LifeSignals.AreaReading(area: $0.0, entries: Int($0.1 * 100), share: $0.1, moods: 5, height: $0.2) }
    }

    @Test func noTwoBubblesOverlapAndAllStayInside() {
        let areas = readings([(.health, 0.4, 0.3), (.mind, 0.33, -0.3), (.work, 0.26, 0), (.family, 0.21, 0.2), (.friends, 0.21, 0.1), (.home, 0.14, 0.4), (.money, 0.12, 0.3), (.love, 0.07, 0.6), (.play, 0.05, -0.5)])
        let size = CGSize(width: 340, height: 320)
        let bubbles = LifeBubbleLayout.layout(areas, in: size)
        #expect(bubbles.count == areas.count)
        for (i, a) in bubbles.enumerated() {
            #expect(a.center.x - a.radius >= -0.5 && a.center.x + a.radius <= size.width + 0.5)
            #expect(a.center.y - a.radius >= -0.5 && a.center.y + a.radius <= size.height + 0.5)
            for b in bubbles[(i + 1)...] {
                let distance = hypot(a.center.x - b.center.x, a.center.y - b.center.y)
                #expect(distance >= a.radius + b.radius - 1, "\(a.area) and \(b.area) overlap")
            }
        }
    }

    @Test func aBiggerShareIsABiggerBubbleAndLighterSitsHigher() {
        let areas = readings([(.work, 0.5, 0.8), (.money, 0.1, -0.8)])
        let bubbles = LifeBubbleLayout.layout(areas, in: CGSize(width: 340, height: 320))
        let work = bubbles.first { $0.area == .work }!, money = bubbles.first { $0.area == .money }!
        #expect(work.radius > money.radius)
        #expect(work.center.y < money.center.y)
    }

    @Test func theSameReadingAlwaysDrawsTheSamePicture() {
        let areas = readings([(.work, 0.5, 0.1), (.home, 0.3, -0.2), (.play, 0.2, nil)])
        let size = CGSize(width: 300, height: 300)
        #expect(LifeBubbleLayout.layout(areas, in: size) == LifeBubbleLayout.layout(areas, in: size))
    }
}
