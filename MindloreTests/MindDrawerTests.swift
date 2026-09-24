import Foundation
import Testing
@testable import Mindlore

struct MindDrawerTests {
    private let maya = UUID(), greg = UUID(), park = UUID(), running = UUID(), quiet = UUID()
    private func at(_ day: Double) -> Date { Date(timeIntervalSince1970: day * 86_400) }

    private var rows: [EntitySearch.Row] {
        [
            EntitySearch.Row(id: maya, name: "Maya", kind: .person, lastMentioned: at(90), openLooseEnds: 2),
            EntitySearch.Row(id: greg, name: "Greg", kind: .person, lastMentioned: at(99)),
            EntitySearch.Row(id: park, name: "Humboldt Park", kind: .place, lastMentioned: at(95)),
            EntitySearch.Row(id: running, name: "running", kind: .tag, lastMentioned: at(98)),
            EntitySearch.Row(id: quiet, name: "Old friend", kind: .person, lastMentioned: at(10)),
        ]
    }

    private func change(_ id: UUID, _ kind: MindStats.Change.Kind, inWindow: Int, before: Int, windowEntries: Int = 19, beforeEntries: Int = 41) -> MindStats.Change {
        MindStats.Change(id: id, kind: kind, inWindow: inWindow, before: before, windowEntries: windowEntries, beforeEntries: beforeEntries, lastMentioned: nil)
    }

    private var stats: MindDrawer.Stats {
        MindDrawer.Stats(
            window: .month,
            counts: [maya: 6, greg: 6, park: 2, running: 11],
            areas: [maya: .love, running: .health],
            series: [maya: [1, 2, 3]],
            changes: [change(running, .more, inWindow: 11, before: 7), change(quiet, .quieter, inWindow: 0, before: 9)]
        )
    }

    @Test func rankedIsByCountThenMostRecentAndLeavesOutWhatTheWindowDoesNotHold() {
        let ranked = MindDrawer.ranked(rows, stats: stats, segment: .all)
        #expect(ranked.map(\.name) == ["running", "Greg", "Maya", "Humboldt Park"], "Greg and Maya tie on 6; Greg was mentioned later")
        #expect(!ranked.contains { $0.id == quiet }, "no entry in the window, so search finds it instead")
        let running = ranked[0]
        #expect(running.change == .more)
        #expect(running.area == .health)
        #expect(ranked.first { $0.id == maya }?.openLooseEnds == 2)
        #expect(ranked.first { $0.id == maya }?.series == [1, 2, 3])
        #expect(ranked.first { $0.id == greg }?.area == nil)
    }

    @Test func chipsFilterTheListAndTheCards() {
        #expect(MindDrawer.ranked(rows, stats: stats, segment: .people).map(\.name) == ["Greg", "Maya"])
        #expect(MindDrawer.ranked(rows, stats: stats, segment: .places).map(\.name) == ["Humboldt Park"])
        #expect(MindDrawer.ranked(rows, stats: stats, segment: .tags).map(\.name) == ["running"])
        #expect(MindDrawer.cards(rows, stats: stats, segment: .tags).map(\.name) == ["running"])
        #expect(MindDrawer.cards(rows, stats: stats, segment: .people).map(\.name) == ["Old friend"])
        #expect(MindDrawer.cards(rows, stats: stats, segment: .all).count == 2)
    }

    @Test func aCardForANameNoLongerListedIsDropped() {
        let hiddenSince = rows.filter { $0.id != running }
        #expect(MindDrawer.cards(hiddenSince, stats: stats, segment: .all).map(\.name) == ["Old friend"])
    }

    @Test func changesReadAsCountsInWords() {
        #expect(MindDrawer.words(for: change(running, .more, inWindow: 11, before: 7), window: .month)
            == "in 11 of your last 19 entries, up from 7 of 41")
        #expect(MindDrawer.words(for: change(greg, .quieter, inWindow: 1, before: 22), window: .quarter)
            == "once in 3 months, down from 22 in the 9 months before")
        #expect(MindDrawer.words(for: change(greg, .quieter, inWindow: 0, before: 9), window: .month)
            == "not in a month, down from 9 in the 3 months before")
        #expect(MindDrawer.words(for: change(greg, .quieter, inWindow: 3, before: 30), window: .year)
            == "3 times in a year, down from 30 in the 3 years before")
        #expect(MindDrawer.words(for: change(maya, .new, inWindow: 3, before: 0), window: .month)
            == "first mentioned lately, in 3 of your last 19 entries")
        #expect(MindDrawer.words(for: change(maya, .back, inWindow: 1, before: 0), window: .quarter)
            == "once in 3 months, after a long quiet")
        #expect(MindDrawer.words(for: change(maya, .more, inWindow: 5, before: 1, windowEntries: 5), window: .month)
            == "in all of your last 5 entries, up from 1 of 41")
        #expect(MindDrawer.words(for: change(maya, .more, inWindow: 1, before: 0, windowEntries: 1), window: .month)
            == "in your only entry, up from 0 of 41")
        #expect(MindDrawer.title(.more) == "More lately")
        #expect(MindDrawer.title(.quieter) == "Quieter")
    }

    @Test func tidyUpCountsEveryUnskippedQuestionInAskingOrder() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let suggestions = [EntityMatcher.Suggestion(a: a, b: b, score: 1), EntityMatcher.Suggestion(a: c, b: d, score: 1)]
        let all = ReviewQueue.questions(suggestions: suggestions, unsure: [], skipped: [])
        #expect(all.count == 2)
        let skipped = ReviewQueue.questions(suggestions: suggestions, unsure: [], skipped: [all[0].id])
        #expect(skipped.map(\.id) == [all[1].id])
        #expect(ReviewQueue.next(suggestions: suggestions, unsure: [], skipped: [all[0].id])?.id == all[1].id)
    }
}
