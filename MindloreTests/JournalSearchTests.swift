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
    private func index() -> AskIndex {
        let gathered = AskSources.documents(in: context)
        return AskIndex.build(from: gathered.documents, entities: gathered.entities)
    }

    private func results(_ query: String) -> JournalSearch.Results {
        JournalSearch.results(for: query, index: index(), now: now, in: context)
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

    @Test func cappedAtThirty() {
        for index in 0..<35 {
            entry("river \(index)", daysAgo: Double(index))
        }
        #expect(results("river").entries.count == JournalSearch.maxEntries)
    }

    // Ranked, not sorted by date. Thirty-five entries that all say "river" are relevance-identical
    // and only recency separates them, which is not the same claim.
    @Test func relevanceOrdersTheRowsAndNotJustRecency() throws {
        entry("A day with nothing much in it, and somewhere in here the word river appears once.", daysAgo: 0)
        let focused = entry("River.", title: "River", daysAgo: 40)

        let rows = results("river").entries
        #expect(rows.count == 2)
        // The older entry leads: the word is its title and most of its text, against one passing
        // mention forty days fresher.
        #expect(rows.first?.id == focused.id)
    }

    // Every word of this is in the stop list, so the ranked path has nothing to search with. It
    // used to match through the predicate, and it has to keep matching.
    @Test func aQueryOfNothingButStopWordsStillFindsWhatItUsedTo() throws {
        let today = entry("Today was quiet.")
        #expect(results("today").entries.map(\.id) == [today.id])
        let mine = entry("My own fault.")
        #expect(results("my").entries.map(\.id).contains(mine.id))
    }

    @Test func aRowMatchedOnAMoodOrAMonthSaysWhich() throws {
        let entry = entry("Nothing in the words themselves.")
        let insights = EntryInsights()
        context.insert(insights)
        insights.entry = entry
        insights.primaryMoodRaw = Mood.allCases.first?.rawValue
        let mood = try #require(Mood.allCases.first?.rawValue)

        #expect(results(mood).entries.first?.reason == "mood: \(mood)")
    }

    // The caption may only ever say what it checked. It used to fall through to "mentions someone
    // by this name" for a mood or a month, which is a claim it had no way to make.
    @Test func aRowNeverClaimsANameItDidNotMatch() throws {
        let entry = entry("Nothing in the words themselves.")
        let insights = EntryInsights()
        context.insert(insights)
        insights.entry = entry
        insights.areasRaw = [LifeArea.work.rawValue]

        let reason = results("work").entries.first?.reason
        #expect(reason == "area: Work")
        #expect(reason?.contains("someone") == false)
    }

    // A whole question matches no literal substring, so every row used to show its own opening.
    @Test func theSnippetWindowsOnAWordTheEntryActuallyHolds() throws {
        entry("A long morning of nothing at all, and then we walked by the river until it got dark.")
        let snippet = try #require(results("What did I do by the river?").entries.first?.snippet)
        #expect(snippet.contains("river"))
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

        #expect(JournalSearch.entries(taggedWith: "River", index: index(), in: context).map(\.id) == [tagged.id])
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
