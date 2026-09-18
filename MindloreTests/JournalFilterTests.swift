import Foundation
import Testing
@testable import Mindlore

struct JournalFilterTests {
    @Test func noAreaKeepsEverything() {
        #expect(JournalFilter.matches(areasRaw: [], areas: []))
        #expect(JournalFilter.matches(areasRaw: ["work"], areas: []))
    }

    @Test func anAreaKeepsOnlyEntriesFiledUnderIt() {
        #expect(JournalFilter.matches(areasRaw: ["work", "money"], areas: [.money]))
        #expect(!JournalFilter.matches(areasRaw: ["work"], areas: [.money]))
        #expect(!JournalFilter.matches(areasRaw: [], areas: [.money]))
        // A value the enum no longer knows never matches anything.
        #expect(!JournalFilter.matches(areasRaw: ["theme"], areas: [.mind]))
    }

    @Test func aHiddenAreaStopsFiltering() {
        #expect(JournalFilter.active([.love], hidden: []) == [.love])
        #expect(JournalFilter.active([.love], hidden: ["love"]).isEmpty)
        #expect(JournalFilter.active([], hidden: []).isEmpty)
    }

    @Test func offeredAreasAreUsedVisibleAndInOrder() {
        let offered = JournalFilter.offered(
            entryAreas: [["home", "work"], [], ["health"], ["work"], ["bogus"]],
            hidden: ["health"]
        )
        #expect(offered == [.work, .home])
        #expect(JournalFilter.offered(entryAreas: [], hidden: []).isEmpty)
    }
}
