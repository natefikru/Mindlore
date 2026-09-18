import Foundation
import Testing
@testable import Mindlore

struct JournalFilterTests {
    @Test func noAreaKeepsEverything() {
        #expect(JournalFilter.matches(areasRaw: [], area: nil))
        #expect(JournalFilter.matches(areasRaw: ["work"], area: nil))
    }

    @Test func anAreaKeepsOnlyEntriesFiledUnderIt() {
        #expect(JournalFilter.matches(areasRaw: ["work", "money"], area: .money))
        #expect(!JournalFilter.matches(areasRaw: ["work"], area: .money))
        #expect(!JournalFilter.matches(areasRaw: [], area: .money))
        // A value the enum no longer knows never matches anything.
        #expect(!JournalFilter.matches(areasRaw: ["theme"], area: .mind))
    }

    @Test func aHiddenAreaStopsFiltering() {
        #expect(JournalFilter.active(.love, hidden: []) == .love)
        #expect(JournalFilter.active(.love, hidden: ["love"]) == nil)
        #expect(JournalFilter.active(nil, hidden: []) == nil)
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
