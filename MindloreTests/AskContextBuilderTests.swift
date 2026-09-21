import Foundation
import Testing
@testable import Mindlore

private let day: TimeInterval = 86_400

// The builder no longer chooses anything: AskIndex ranks, AskRetrieval.plan divides the budget, and
// this renders what they picked. Selection and ranking are covered by AskIndexTests and
// AskRetrievalTests; what is left here is handles, fencing, truncation, and whether a slice can eat
// the room the entries needed.
struct AskContextBuilderTests {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func entry(_ text: String, daysAgo: Double = 0, title: String = "", entities: [UUID] = [], id: UUID = UUID()) -> AskContextBuilder.EntryInput {
        AskContextBuilder.EntryInput(id: id, date: now.addingTimeInterval(-daysAgo * day), title: title, text: text, entityIDs: entities)
    }

    private func render(
        ranked: [AskContextBuilder.EntryInput] = [],
        continuity: [AskContextBuilder.EntryInput] = [],
        excerpt: Set<UUID> = [],
        entities: [AskContextBuilder.EntityInput] = [],
        rollups: [String] = [],
        matched: Int = 0,
        handles: [String: UUID] = [:],
        budget: Int = AskContextBuilder.openAIBudget,
        provider: AskProviderKind = .openAI
    ) -> AskContextBuilder.Context {
        var plan = AskRetrieval.Plan()
        plan.slices = AskRetrieval.slices(budget: budget, provider: provider)
        plan.rankedEntryIDs = ranked.map(\.id)
        plan.continuityEntryIDs = continuity.map(\.id)
        plan.excerptEntryIDs = excerpt
        plan.aboutEntityIDs = entities.map(\.id)
        plan.matchedCount = matched
        plan.rollupMonths = rollups.map { _ in DateInterval(start: now, duration: day) }
        let selection = AskSources.Selection(entries: ranked + continuity, entities: entities)
        return AskContextBuilder.render(plan: plan, selection: selection, rollups: rollups, handles: handles, budget: budget)
    }

    // MARK: - Order

    @Test func entitiesComeFirstAndTheBestMatchesLastNearestTheQuestion() throws {
        let sarahID = UUID()
        let sarah = AskContextBuilder.EntityInput(id: sarahID, name: "Sarah", bio: "My sister.", openLooseEnds: ["Call Sarah back"])
        let best = entry("Walked the river with Sarah.", daysAgo: 30, entities: [sarahID])
        let earlier = entry("Quiet day, read a book.", daysAgo: 1)

        let context = render(ranked: [best], continuity: [earlier], entities: [sarah])

        #expect(context.blocks.first?.entryID == nil, "the entity's own block comes before any entry")
        #expect(context.blocks.first?.text.contains("My sister.") == true)
        #expect(context.blocks.first?.text.contains("Call Sarah back") == true)
        // Continuity before ranked: the strongest evidence sits closest to the question.
        #expect(context.entryIDs == [earlier.id, best.id])
    }

    @Test func anEntryGoesInOnceEvenIfTwoSlicesAskForIt() {
        let shared = entry("Sarah brought the kayak.", daysAgo: 2)
        let context = render(ranked: [shared], continuity: [shared])
        #expect(context.entryIDs == [shared.id])
        #expect(context.blocks.filter { $0.entryID == shared.id }.count == 1)
    }

    // MARK: - Budget

    @Test func aBlockTooBigToFitIsSkippedAndASmallerOneStillGoesIn() {
        let huge = entry(String(repeating: "kayak paddle. ", count: 300), daysAgo: 1)
        let small = entry("kayak in the shed.", daysAgo: 2)

        let context = render(ranked: [huge, small], budget: 300)

        #expect(context.entryIDs == [small.id])
        #expect(context.characters <= 300)
    }

    @Test func aRollupCannotEatTheRoomTheEntriesNeeded() {
        // Twenty rollup lines of 500 characters is 10,000, well past the 6,000 rollup slice. What
        // does not fit that slice has to be dropped rather than taken out of the entries.
        let rollups = (0..<20).map { _ in String(repeating: "x", count: 500) }
        let entries = (0..<8).map { entry(String(repeating: "kayak ", count: 200), daysAgo: Double($0)) }

        let context = render(ranked: entries, rollups: rollups)
        let rollupCharacters = context.blocks.filter { $0.entryID == nil }.reduce(0) { $0 + $1.text.count }

        #expect(rollupCharacters <= AskRetrieval.rollupBudgetOpenAI + 40)
        #expect(context.entryIDs.count == 8, "every entry still fits")
    }

    @Test func continuityCannotEatTheRoomTheEntriesNeeded() {
        let cited = (0..<20).map { entry(String(repeating: "old ", count: 500), daysAgo: Double(100 + $0)) }
        let best = entry("kayak in the shed", daysAgo: 0)

        let context = render(ranked: [best], continuity: cited)

        #expect(context.entryIDs.contains(best.id))
        #expect(context.entryIDs.count < 21)
    }

    @Test func anUnusedSliceRollsForwardIntoTheEntries() {
        // No entities, no rollups, and no digests, so the room all three would have taken is there
        // for the entries. Thirty blocks of 2,000 is 60,000 against a ranked slice of 25,600.
        let entries = (0..<30).map { entry(String(repeating: "kayak ", count: 330), daysAgo: Double($0)) }
        let context = render(ranked: entries)
        #expect(context.characters > AskRetrieval.slices(budget: AskContextBuilder.openAIBudget, provider: .openAI).ranked)
        #expect(context.characters <= AskContextBuilder.openAIBudget)
    }

    @Test func aLongEntryIsCutAtASentenceEnd() throws {
        let sentence = "The kayak sat in the shed " + String(repeating: "and waited ", count: 25) + "all winter. "
        let long = entry(String(repeating: sentence, count: 10), daysAgo: 1)

        let context = render(ranked: [long])

        let block = try #require(context.blocks.first?.text)
        #expect(block.hasSuffix(AskContextBuilder.closeDelimiter))
        let body = block.components(separatedBy: "\n").dropFirst(2).dropLast().joined(separator: "\n")
        #expect(body.hasSuffix("."))
        #expect(body.count <= AskContextBuilder.maxEntryCharacters)
    }

    // MARK: - Handles

    @Test func handlesAreStableAcrossTurnsAndNewEntriesTakeTheNextNumber() {
        let first = entry("kayak day", daysAgo: 5)
        let second = entry("kayak again", daysAgo: 1)

        let one = render(ranked: [first])
        #expect(one.handles == ["E1": first.id])

        let two = render(ranked: [first, second], handles: one.handles)
        #expect(two.handles["E1"] == first.id)
        #expect(two.handles["E2"] == second.id)
        #expect(two.handle(for: second.id) == "E2")
    }

    @Test func aReopenedConversationReusesTheStoredMap() {
        let entry = entry("kayak day", daysAgo: 5)
        let context = render(ranked: [entry], handles: ["E7": entry.id])

        #expect(context.handles["E7"] == entry.id)
        #expect(context.blocks.first?.text.hasPrefix("[E7] ") == true)
    }

    // MARK: - Entity blocks

    @Test func anEntityBlockNamesTheOtherSpellingsTheJournalUses() throws {
        let id = UUID()
        let entity = AskContextBuilder.EntityInput(id: id, name: "Luis", aliases: ["Lewis", "luis"], bio: "Thrift-store friend.")
        let entry = entry("Went thrifting with Lewis.", daysAgo: 4, entities: [id])

        let context = render(ranked: [entry], entities: [entity])
        let block = try #require(context.blocks.first?.text)

        #expect(block.contains("About Luis"))
        #expect(block.contains("Also written in the journal as: Lewis"), "\(block)")
        #expect(!block.contains(", luis"), "a spelling that only differs in case isn't another name")
        #expect(context.entryIDs == [entry.id], "and the entry that says Lewis still goes in")
    }

    // MARK: - Excerpts

    @Test func anEntryMatchedOnlyThroughAnEntityIsSentAsTheSentencesNamingHer() throws {
        let id = UUID()
        let sarah = AskContextBuilder.EntityInput(id: id, name: "Sarah")
        let long = entry(
            "Rebuilt the fence all morning. Sarah came by at lunch. " + String(repeating: "Then hours of nothing much. ", count: 60),
            daysAgo: 3,
            entities: [id]
        )

        let context = render(ranked: [long], excerpt: [long.id], entities: [sarah])
        let block = try #require(context.blocks.last?.text)

        #expect(block.contains("Sarah came by at lunch."))
        #expect(block.contains("Rebuilt the fence all morning.") == false)
        // Ten of these fit where three full blocks would, which is what the old tier 1 bought and
        // what a whole-block rewrite would have thrown away.
        #expect(block.count < 400)
    }

    @Test func anExcerptFallsBackToTheWholeEntryWhenNoNameIsInIt() {
        let id = UUID()
        let sarah = AskContextBuilder.EntityInput(id: id, name: "Sarah")
        // Linked to Sarah by insights, but her name is nowhere in the words.
        let entry = entry("Dinner and a long argument about nothing.", daysAgo: 3, entities: [id])

        let context = render(ranked: [entry], excerpt: [entry.id], entities: [sarah])
        #expect(context.blocks.last?.text.contains("long argument") == true)
    }

    // MARK: - Counting

    @Test func theContextCarriesWhatWasCutSoThePromptCanSaySo() {
        let entries = (0..<3).map { entry("kayak \($0)", daysAgo: Double($0)) }
        let context = render(ranked: entries, matched: 84)
        #expect(context.matchedCount == 84)
        #expect(context.wasCut)

        let all = render(ranked: entries, matched: 3)
        #expect(all.wasCut == false)
    }

    @Test func matchedIsNeverLessThanWhatWentIn() {
        let entries = (0..<3).map { entry("kayak \($0)", daysAgo: Double($0)) }
        // A plan that under-counted must not produce "3 of 0".
        #expect(render(ranked: entries, matched: 0).matchedCount == 3)
    }

    @Test func nothingChosenRendersNothing() {
        let context = render()
        #expect(context.isEmpty)
        #expect(context.blocks.isEmpty)
        #expect(context.characters == 0)
    }
}
