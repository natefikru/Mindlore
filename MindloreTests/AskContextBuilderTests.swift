import Foundation
import Testing
@testable import Mindlore

private let day: TimeInterval = 86_400

struct AskContextBuilderTests {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func entry(_ text: String, daysAgo: Double = 0, title: String = "", entities: [UUID] = [], id: UUID = UUID()) -> AskContextBuilder.EntryInput {
        AskContextBuilder.EntryInput(id: id, date: now.addingTimeInterval(-daysAgo * day), title: title, text: text, entityIDs: entities)
    }

    private func build(_ question: String, entries: [AskContextBuilder.EntryInput], entities: [AskContextBuilder.EntityInput] = [], handles: [String: UUID] = [:], budget: Int = AskContextBuilder.openAIBudget) -> AskContextBuilder.Context {
        AskContextBuilder.build(question: question, entries: entries, entities: entities, handles: handles, now: now, budget: budget)
    }

    @Test func namedEntitiesComeFirstThenKeywordsThenTheDateRange() {
        let sarahID = UUID()
        let sarah = AskContextBuilder.EntityInput(id: sarahID, name: "Sarah", bio: "My sister.", openLooseEnds: ["Call Sarah back"])
        let withSarah = entry("Walked the river with Sarah.", daysAgo: 30, entities: [sarahID])
        let keyword = entry("The kayak needed a new paddle.", daysAgo: 20)
        let yesterday = entry("Quiet day, read a book.", daysAgo: 1)

        let context = build("What did Sarah say about the kayak yesterday?", entries: [withSarah, keyword, yesterday], entities: [sarah])

        #expect(context.entryIDs == [withSarah.id, keyword.id, yesterday.id])
        #expect(context.blocks.first?.entryID == nil, "the entity's own block comes before its excerpts")
        #expect(context.blocks.first?.text.contains("My sister.") == true)
        #expect(context.blocks.first?.text.contains("Call Sarah back") == true)
    }

    @Test func anEntryGoesInOnceAtItsHighestTier() {
        let sarahID = UUID()
        let sarah = AskContextBuilder.EntityInput(id: sarahID, name: "Sarah")
        let shared = entry("Sarah brought the kayak.", daysAgo: 2, entities: [sarahID])

        let context = build("Did Sarah bring the kayak?", entries: [shared], entities: [sarah])

        #expect(context.entryIDs == [shared.id])
        #expect(context.blocks.filter { $0.entryID == shared.id }.count == 1)
    }

    @Test func aBlockTooBigToFitIsSkippedAndASmallerOneStillGoesIn() {
        let huge = entry(String(repeating: "kayak paddle. ", count: 300), daysAgo: 1)
        let small = entry("kayak in the shed.", daysAgo: 2)

        let context = build("where is the kayak", entries: [huge, small], budget: 300)

        #expect(context.entryIDs == [small.id])
        #expect(context.characters <= 300)
    }

    @Test func aLongEntryIsCutAtASentenceEnd() throws {
        let sentence = "The kayak sat in the shed " + String(repeating: "and waited ", count: 25) + "all winter. "
        let long = entry(String(repeating: sentence, count: 10), daysAgo: 1)

        let context = build("kayak", entries: [long])

        let block = try #require(context.blocks.first?.text)
        #expect(block.hasSuffix(AskContextBuilder.closeDelimiter))
        let body = block.components(separatedBy: "\n").dropFirst(2).dropLast().joined(separator: "\n")
        #expect(body.hasSuffix("."))
        #expect(body.count <= AskContextBuilder.maxEntryCharacters)
    }

    @Test func handlesAreStableAcrossTurnsAndNewEntriesTakeTheNextNumber() {
        let first = entry("kayak day", daysAgo: 5)
        let second = entry("kayak again", daysAgo: 1)

        let one = build("kayak", entries: [first])
        #expect(one.handles == ["E1": first.id])

        let two = build("kayak", entries: [first, second], handles: one.handles)
        #expect(two.handles["E1"] == first.id)
        #expect(two.handles["E2"] == second.id)
        #expect(two.handle(for: second.id) == "E2")
    }

    @Test func aReopenedConversationReusesTheStoredMap() {
        let entry = entry("kayak day", daysAgo: 5)
        let stored = ["E7": entry.id]

        let context = build("kayak", entries: [entry], handles: stored)

        #expect(context.handles["E7"] == entry.id)
        #expect(context.blocks.first?.text.hasPrefix("[E7] ") == true)
    }

    @Test func aMergedEntityNamedByItsAliasIsFound() {
        let id = UUID()
        let entity = AskContextBuilder.EntityInput(id: id, name: "Sarah Kim", aliases: ["Sarah K"], bio: "Rows on Sundays.")
        let linked = entry("Sarah K brought the kayak.", daysAgo: 3, entities: [id])

        let context = build("What has Sarah K been up to?", entries: [linked], entities: [entity])

        #expect(context.blocks.first?.text.contains("Rows on Sundays.") == true)
        #expect(context.entryIDs == [linked.id])
    }

    @Test func aQuestionThatMatchesNothingSendsNoRecentEntriesWhenSomethingElseMatched() {
        let matched = entry("kayak in the shed.", daysAgo: 10)
        let recent = entry("Nothing much.", daysAgo: 1)

        #expect(build("kayak", entries: [matched, recent]).entryIDs == [matched.id])
    }

    @Test func aQuestionThatMatchesNothingAtAllFallsBackToTheFiveMostRecent() {
        let entries = (1...7).map { entry("Entry \($0)", daysAgo: Double($0)) }

        let context = build("hi", entries: entries)

        #expect(context.entryIDs == entries.prefix(5).map(\.id))
    }

    @Test func keywordsDropStopWordsAndShortWords() {
        #expect(AskContextBuilder.keywords(in: "What did I do with the kayak last week?") == ["kayak"])
        #expect(AskContextBuilder.keywords(in: "How are you?").isEmpty)
    }

    @Test func entriesAreRankedByHowManyKeywordsTheyMatch() {
        let both = entry("kayak and paddle together", daysAgo: 30)
        let one = entry("just a paddle", daysAgo: 1)

        let context = build("kayak paddle", entries: [one, both])

        #expect(context.entryIDs == [both.id, one.id], "more keywords beats more recent")
    }
}
