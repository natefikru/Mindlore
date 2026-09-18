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

    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    // The panel reads the same index the prompt is built from, which is the whole point of the
    // change: before it, the panel could say "nothing matches that" about an entry the question
    // then went on to send.
    private func results(_ query: String) -> JournalSearch.Results {
        let gathered = AskSources.documents(in: context)
        let index = AskIndex.build(from: gathered.documents, entities: gathered.entities)
        return JournalSearch.results(for: query, index: index, now: now, in: context)
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

    @Test func rankedAndCappedAtThirty() {
        for index in 0..<35 {
            entry("river \(index)", daysAgo: Double(index))
        }

        let rows = results("river").entries

        #expect(rows.count == JournalSearch.maxEntries)
        // Ranked, not sorted by date: thirty-five entries all saying "river" are separated by
        // recency, so newest still leads, but relevance is what decides the order now.
        #expect(rows.first?.date ?? .distantPast > rows.last?.date ?? .distantFuture)
    }

    // Case and diacritics folded at index time, the same way they folded in the old predicate, so
    // a result set does not change shape now that queries no longer go through SwiftData.
    @Test func caseAndDiacriticsFoldTheWayThePredicateDid() throws {
        let cafe = entry("Coffee at the Café.")

        #expect(results("café").entries.map(\.id) == [cafe.id])
        #expect(results("CAFE").entries.map(\.id) == [cafe.id])
        #expect("Coffee at the Café.".localizedStandardContains("cafe"))
    }

    // The one thing prefix matching loses, kept as a fallback because people do type it.
    @Test func matchingTheMiddleOfAWordStillWorks() throws {
        let river = entry("We walked by the river.")
        #expect(results("iver").entries.map(\.id) == [river.id])
    }

    // What the screenshot showed and no test caught: typing a whole question at the panel matched
    // nothing, while the line underneath said asking would send an entry.
    @Test func aWholeQuestionFindsWhatAskingWouldSend() throws {
        let river = entry("We walked by the river.")
        #expect(results("What did I do by the river?").entries.map(\.id) == [river.id])
    }

    // An entry can now rank on something that appears nowhere in its words, and the snippet is then
    // just its opening. The row says why instead of looking like a mistake.
    @Test func aRowMatchedOnSomethingInvisibleSaysWhy() throws {
        let tagged = entry("Nothing in the words themselves.", tags: ["deadline"])
        let rows = results("deadline").entries
        #expect(rows.map(\.id) == [tagged.id])
        #expect(rows.first?.reason == "tag: deadline")
    }

    @Test func aRowWhoseWordsAreInTheEntryNeedsNoReason() throws {
        entry("The deadline moved again.")
        #expect(results("deadline").entries.first?.reason == nil)
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
