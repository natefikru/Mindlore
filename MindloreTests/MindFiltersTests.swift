import Testing
@testable import Mindlore

struct MindFiltersTests {
    @Test func aYoungJournalShowsSingleMentions() {
        #expect(MindFilters.defaultMinimum(browsableCount: 0) == 1)
        #expect(MindFilters.defaultMinimum(browsableCount: MindFilters.largeJournal - 1) == 1)
        #expect(MindFilters.defaultMinimum(browsableCount: MindFilters.largeJournal) == 2)
        #expect(MindFilters.defaultMinimum(browsableCount: 300) == 2)
    }

    @Test func everyKindIsOnByDefault() {
        #expect(MindFilters().kinds == Set(EntityKind.allCases))
    }
}

struct MindFiltersToggleTests {
    @Test func entriesAndRegionsStartOff() {
        let filters = MindFilters()
        #expect(!filters.showsEntries)
        #expect(!filters.groupsByArea)
    }
}
