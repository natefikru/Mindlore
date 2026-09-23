import Foundation
import SwiftData
import Testing
@testable import Mindlore

struct MindStatsTests {
    private let sarah = UUID(), tom = UUID(), lisbon = UUID(), run = UUID(), teo = UUID()
    private let asOf = Date(timeIntervalSince1970: 1000 * 86_400)

    private func at(_ day: Double) -> Date { Date(timeIntervalSince1970: day * 86_400) }

    private struct Written {
        let id = UUID()
        let day: Double
        let names: [UUID]
        var areas: [LifeArea] = []
    }

    // `count` entries spread evenly through (from, to], the first `naming.count` of whatever each
    // name's own count is naming it. Entries naming nobody still count toward the share.
    private func stretch(_ count: Int, from: Double, to: Double, naming: [UUID: Int] = [:]) -> [Written] {
        (0..<count).map { index in
            let day = to - (to - from) * Double(index) / Double(count)
            return Written(day: day, names: naming.filter { index < $0.value }.map(\.key))
        }
    }

    private func snapshot(_ written: [Written]) -> MindMapSnapshot {
        let entities: [UUID: MindMapSnapshot.EntityInfo] = [
            sarah: .init(id: sarah, name: "Sarah", kind: .person),
            tom: .init(id: tom, name: "Tom", kind: .person),
            lisbon: .init(id: lisbon, name: "Lisbon", kind: .place),
            run: .init(id: run, name: "running", kind: .tag),
            teo: .init(id: teo, name: "Teo", kind: .person, aliases: ["Teodoro"]),
        ]
        var links: [EntityGraph.LinkInput] = []
        var entries: [UUID: MindMapSnapshot.EntryInfo] = [:]
        for entry in written {
            entries[entry.id] = .init(id: entry.id, date: at(entry.day), areas: entry.areas, mood: nil)
            links += entry.names.map { .init(entryID: entry.id, entityID: $0, entryDate: at(entry.day)) }
        }
        return MindMapSnapshot(entities: entities, links: links, entries: entries, entryDates: written.map { at($0.day) })
    }

    // A month window ending at day 1000 is (970, 1000]; its baseline is (880, 970].
    private func month(baseline: [UUID: Int] = [:], window: [UUID: Int] = [:], baselineCount: Int = 30, windowCount: Int = 10) -> MindMapSnapshot {
        snapshot(stretch(baselineCount, from: 880, to: 970, naming: baseline) + stretch(windowCount, from: 970, to: 1000, naming: window))
    }

    private func changes(_ snapshot: MindMapSnapshot, excluding: Set<UUID> = []) -> [UUID: MindStats.Change.Kind] {
        Dictionary(uniqueKeysWithValues: MindStats.changes(snapshot, window: .month, asOf: asOf, excluding: excluding).map { ($0.id, $0.kind) })
    }

    // MARK: - Windows

    @Test func windowsAreFixedLengthsAndAllTimeHasNone() {
        #expect(MindWindow.allCases.map(\.days) == [30, 90, 365, nil])
        #expect(MindWindow.default == .quarter)
        let interval = MindWindow.month.interval(endingAt: asOf)
        #expect(interval?.start == at(970))
        #expect(interval?.end == asOf)
        #expect(MindWindow.all.interval(endingAt: asOf) == nil)
    }

    @Test func countsAreStartExclusiveEndInclusiveAndCountAnEntryOnce() {
        let onStart = Written(day: 970, names: [sarah])
        let inside = Written(day: 970.5, names: [sarah, sarah])
        let onEnd = Written(day: 1000, names: [sarah, tom])
        let future = Written(day: 1001, names: [sarah])
        let map = snapshot([onStart, inside, onEnd, future])

        let month = MindStats.counts(map, window: .month, asOf: asOf)
        #expect(month[sarah] == 2, "the start instant belongs to the window before, and a doubled link counts once")
        #expect(month[tom] == 1)

        let all = MindStats.counts(map, window: .all, asOf: asOf)
        #expect(all[sarah] == 3, "all time is everything up to asOf, never the future")
    }

    @Test func areasReadOnlyTheWindowsEntries() {
        var old1 = Written(day: 500, names: [sarah]), old2 = Written(day: 600, names: [sarah])
        var recent = Written(day: 990, names: [sarah])
        var onlyOld = Written(day: 600, names: [tom])
        old1.areas = [.work]
        old2.areas = [.work]
        recent.areas = [.family]
        onlyOld.areas = [.play]
        let map = snapshot([old1, old2, recent, onlyOld])

        let month = MindStats.areas(map, window: .month, asOf: asOf)
        #expect(month[sarah] == .family)
        #expect(month[tom] == nil, "nothing in the window means no area, drawn neutral")
        #expect(MindStats.areas(map, window: .all, asOf: asOf)[sarah] == .work)
    }

    // MARK: - Sparklines

    @Test func seriesBucketsCoverTheWindowAndTheThreeBefore() {
        // Month: 120 days in 16 buckets of 7.5 days, the last ending at asOf.
        let map = snapshot([
            Written(day: 1000, names: [sarah]),       // age 0: last bucket
            Written(day: 992.51, names: [sarah]),     // just inside the last bucket
            Written(day: 992.5, names: [sarah]),      // on the last bucket's start: the one before
            Written(day: 880.01, names: [sarah]),     // just inside the first bucket
            Written(day: 880, names: [sarah]),        // on the span's start: out
        ])
        let bars = MindStats.series(map, entity: sarah, window: .month, asOf: asOf)
        #expect(bars.count == 16)
        #expect(bars[15] == 2)
        #expect(bars[14] == 1)
        #expect(bars[0] == 1)
        #expect(bars.reduce(0, +) == 4)
        #expect(MindStats.series(map, entity: tom, window: .month, asOf: asOf) == Array(repeating: 0, count: 16))
    }

    @Test func allTimeSeriesSpansTheJournal() {
        // The journal starts at day 100 with an entry naming nobody; Sarah comes later.
        let map = snapshot([
            Written(day: 100, names: []),
            Written(day: 100.5, names: [sarah]),
            Written(day: 1000, names: [sarah]),
        ])
        let bars = MindStats.series(map, entity: sarah, window: .all, asOf: asOf)
        #expect(bars.first == 1)
        #expect(bars.last == 1)
        let onFirstDay = MindStats.series(snapshot([Written(day: 100, names: [sarah])] + [Written(day: 1000, names: [])]),
                                          entity: sarah, window: .all, asOf: asOf)
        #expect(onFirstDay.first == 1, "the journal's first entry lands in the first bucket, not off the end")
    }

    // MARK: - What changed

    @Test func newIsAFirstMentionInsideTheWindowTwiceOverAndNeverATag() {
        let map = month(window: [tom: 2, lisbon: 1, run: 5])
        let found = changes(map)
        #expect(found[tom] == .new)
        #expect(found[lisbon] == nil, "once is not enough")
        #expect(found[run] == nil, "a tag is never new, and with no earlier share it can't be more either")
    }

    @Test func backNeedsThreeEarlierMentionsAndALongSilence() {
        let longAgo = [Written(day: 800, names: [sarah]), Written(day: 810, names: [sarah]), Written(day: 820, names: [sarah])]
        let returning = snapshot(longAgo + stretch(30, from: 880, to: 970) + [Written(day: 995, names: [sarah])] + stretch(9, from: 970, to: 1000))
        #expect(changes(returning)[sarah] == .back)

        let twiceBefore = snapshot(Array(longAgo.prefix(2)) + stretch(30, from: 880, to: 970) + [Written(day: 995, names: [sarah])] + stretch(9, from: 970, to: 1000))
        #expect(changes(twiceBefore)[sarah] == nil)

        // Forty days of quiet is short of a month window's sixty.
        let shortGap = snapshot([Written(day: 900, names: [sarah]), Written(day: 910, names: [sarah]), Written(day: 950, names: [sarah])]
            + stretch(27, from: 880, to: 970) + [Written(day: 990, names: [sarah])] + stretch(9, from: 970, to: 1000))
        #expect(changes(shortGap)[sarah] == nil)
    }

    @Test func moreLatelyNeedsThreeAndDoubleTheShareAndTagsNeedFour() {
        #expect(changes(month(baseline: [sarah: 3], window: [sarah: 3]))[sarah] == .more, "3 of 10, up from 3 of 30")
        #expect(changes(month(baseline: [sarah: 3], window: [sarah: 2]))[sarah] == nil, "2 in the window is too few")
        #expect(changes(month(baseline: [sarah: 6], window: [sarah: 3]))[sarah] == nil, "0.3 is not double 0.2")
        #expect(changes(month(baseline: [run: 3], window: [run: 3]))[run] == nil)
        #expect(changes(month(baseline: [run: 3], window: [run: 4]))[run] == .more)
    }

    @Test func quieterNeedsTwoAWindowBeforeAndHalfTheShareAndTagsNeedThree() {
        #expect(changes(month(baseline: [sarah: 6], window: [sarah: 1]))[sarah] == .quieter, "1 of 10, down from 6 of 30")
        #expect(changes(month(baseline: [sarah: 5], window: [sarah: 0]))[sarah] == nil, "under two a window is too thin to call")
        #expect(changes(month(baseline: [run: 6], window: [run: 0]))[run] == nil)
        #expect(changes(month(baseline: [run: 9], window: [run: 1]))[run] == .quieter)
    }

    // Five a window before and two this month is fewer mentions, but it is a quiet month, not a
    // quieter Sarah: 2 of 5 entries against 15 of 30.
    @Test func aMonthWithFewerEntriesDoesNotMakeEveryoneQuieter() {
        let map = month(baseline: [sarah: 15, tom: 15], window: [sarah: 2, tom: 2], windowCount: 5)
        #expect(changes(map).isEmpty)
    }

    @Test func theAuthorIsMatchedByNameOrAliasAndNeverListed() {
        let map = month(window: [teo: 5, tom: 2])
        #expect(MindStats.authorIDs(named: "teo", in: map) == [teo])
        #expect(MindStats.authorIDs(named: "  Teodoro ", in: map) == [teo])
        #expect(MindStats.authorIDs(named: "Lisbon", in: map).isEmpty, "only a person can be the author")
        #expect(MindStats.authorIDs(named: "", in: map).isEmpty)

        #expect(changes(map)[teo] == .new)
        let without = changes(map, excluding: MindStats.authorIDs(named: "Teo", in: map))
        #expect(without[teo] == nil)
        #expect(without[tom] == .new)
    }

    @Test func changesAreCappedAndTheBiggestShiftComesFirst() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID(), e = UUID()
        var map = month(baseline: [sarah: 3], window: [sarah: 8, tom: 2, a: 3, b: 4, c: 5, d: 6, e: 7])
        let extra = Dictionary(uniqueKeysWithValues: [a, b, c, d, e].map { ($0, MindMapSnapshot.EntityInfo(id: $0, name: "x", kind: .person)) })
        map = MindMapSnapshot(entities: map.entities.merging(extra) { first, _ in first }, links: map.links, entries: map.entries, entryDates: map.entryDates)

        let found = MindStats.changes(map, window: .month, asOf: asOf)
        #expect(found.count == 4)
        #expect(found.map(\.id) == [sarah, e, d, c])
        #expect(found.first?.inWindow == 8)
        #expect(found.first?.before == 3)
        #expect(found.first?.windowEntries == 10)
        #expect(found.first?.beforeEntries == 30)
        #expect(MindStats.changes(map, window: .month, asOf: asOf, cap: 10).count == 7)
    }

    @Test func allTimeAndAJournalWithNoBaselineHaveNoChanges() {
        let map = month(baseline: [sarah: 3], window: [sarah: 8, tom: 2])
        #expect(MindStats.changes(map, window: .all, asOf: asOf).isEmpty)
        let young = snapshot(stretch(10, from: 970, to: 1000, naming: [tom: 3]))
        #expect(MindStats.changes(young, window: .month, asOf: asOf).isEmpty, "a journal younger than its window would call everyone new")
    }
}

@MainActor
struct MindStatsStoreTests {
    @Test func theSnapshotDatesEveryNonDraftEntryLinkedOrNot() throws {
        let harness = try GraphHarness()
        try harness.entry(entryDate: Date(timeIntervalSince1970: 1_000), mentions: [("Sarah", .person)])
        try harness.entry(entryDate: Date(timeIntervalSince1970: 2_000))
        let draft = try harness.entry(entryDate: Date(timeIntervalSince1970: 3_000))
        draft.isDraft = true
        try harness.context.save()
        harness.indexer.sweep(in: harness.context)

        let snapshot = GraphServices(diagnostics: .disabled).mapSnapshot(in: harness.context)

        #expect(snapshot.entries.count == 1)
        #expect(snapshot.entryDates.sorted() == [Date(timeIntervalSince1970: 1_000), Date(timeIntervalSince1970: 2_000)])
    }

    // The regenerated story's arc, read by the real rules: the month is running, and over three
    // months the Ledgerline chapter closes (Greg goes quiet) while running takes its place. The
    // author, who is in nearly every entry, is never news.
    @Test func theStorysHeadlineArc() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try DemoStory.seedIfEmpty(in: container.mainContext, now: now)
        let snapshot = GraphServices(diagnostics: .disabled).mapSnapshot(in: container.mainContext)
        let author = MindStats.authorIDs(named: "Teo", in: snapshot)
        #expect(author.count == 1)

        func found(_ window: MindWindow) -> [String: MindStats.Change.Kind] {
            let changes = MindStats.changes(snapshot, window: window, asOf: now, excluding: author)
            return Dictionary(changes.compactMap { change in snapshot.entities[change.id].map { ($0.name, change.kind) } }, uniquingKeysWith: { first, _ in first })
        }

        let month = found(.month)
        #expect(month["running"] == .more)
        #expect(month["therapy"] == .quieter)

        let quarter = found(.quarter)
        #expect(quarter["running"] == .more)
        #expect(quarter["Greg"] == .quieter)

        #expect(found(.year).isEmpty, "the story is one year long, so a year has nothing before it")
        for window in MindWindow.allCases {
            #expect(found(window)["Teo"] == nil)
        }
    }
}
