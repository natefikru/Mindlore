import Foundation
import SwiftData
import Testing
@testable import Mindlore

@MainActor
struct JournalSearchTests {
    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        container = try ModelContainerFactory.make(.inMemory)
        context = container.mainContext
    }

    @discardableResult
    private func entry(_ text: String, title: String = "", daysAgo: Double = 0, draft: Bool = false, tags: [String] = []) -> Entry {
        let entry = Entry(createdAt: Date(timeIntervalSince1970: 1_750_000_000 - daysAgo * 86_400), text: text)
        entry.title = title
        entry.isDraft = draft
        context.insert(entry)
        if !tags.isEmpty {
            let insights = EntryInsights()
            context.insert(insights)
            insights.entry = entry
            insights.tags = tags
        }
        return entry
    }

    private func results(_ query: String) -> JournalSearch.Results {
        JournalSearch.results(for: query, in: context)
    }

    @Test func matchesTextOrTitle() throws {
        let inText = entry("We walked by the river.")
        let inTitle = entry("Nothing about water here.", title: "River day")
        entry("A day in the hills.")

        let found = results("river")

        #expect(Set(found.entries.map(\.id)) == [inText.id, inTitle.id])
    }

    @Test func draftsAreNeverSearched() {
        entry("River thoughts, half written.", draft: true)

        #expect(results("river").entries.isEmpty)
    }

    @Test func newestFirstAndCappedAtThirty() {
        for index in 0..<35 {
            entry("river \(index)", daysAgo: Double(index))
        }

        let rows = results("river").entries

        #expect(rows.count == JournalSearch.maxEntries)
        #expect(rows == rows.sorted { $0.date > $1.date })
    }

    // The store's predicate and the in-memory rule have to agree, or a result set changes shape
    // the moment a query stops going through SwiftData.
    @Test func thePredicateMatchesCaseAndDiacriticsLikeTheInMemoryRule() throws {
        let cafe = entry("Coffee at the Café.")

        #expect(results("café").entries.map(\.id) == [cafe.id])
        #expect(results("CAFE").entries.map(\.id) == [cafe.id])
        #expect("Coffee at the Café.".localizedStandardContains("cafe"))
    }

    @Test func aQueryUnderTwoCharactersFindsNothing() {
        entry("River day.")

        #expect(results("r").isEmpty)
        #expect(results(" ").isEmpty)
        #expect(!results("ri").isEmpty)
    }

    @Test func tagsMatchExactlyAndCaseInsensitivelyWithTheirCounts() {
        entry("Paddled out.", tags: ["river", "morning"])
        entry("Walked the bank.", tags: ["River"])
        entry("Draft thoughts.", draft: true, tags: ["river"])

        let rows = results("RIVER").tags

        #expect(rows.count == 1)
        #expect(rows.first?.count == 2, "the draft's tag doesn't count")
        #expect(results("riv").tags.isEmpty, "a partial tag is not a tag row")
    }

    @Test func tappingATagFillsTheEntriesWithThatTagsEntries() {
        let tagged = entry("Paddled out.", tags: ["river"])
        entry("Nothing to do with it.", tags: ["work"])

        #expect(JournalSearch.entries(taggedWith: "River", in: context).map(\.id) == [tagged.id])
    }

    @Test func theSnippetIsAWindowAroundTheFirstMatch() {
        let long = String(repeating: "walking ", count: 30) + "the river was high " + String(repeating: "later ", count: 30)
        let snippet = JournalSearch.snippet(in: long, around: "river")

        #expect(snippet.contains("the river was high"))
        #expect(snippet.count <= JournalSearch.snippetCharacters + 2)
        #expect(snippet.hasPrefix("…"))
        #expect(snippet.hasSuffix("…"))
    }

    @Test func aShortEntryNeedsNoEllipses() {
        #expect(JournalSearch.snippet(in: "The river was high.", around: "river") == "The river was high.")
    }

    @Test func anEntryWithNoTitleShowsItsFirstLine() {
        let untitled = entry("First line here.\nSecond line.")
        let titled = entry("Body.", title: "A title")

        #expect(JournalSearch.displayTitle(for: untitled) == "First line here.")
        #expect(JournalSearch.displayTitle(for: titled) == "A title")
    }
}
