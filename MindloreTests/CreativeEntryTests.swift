import Foundation
import SwiftData
import Testing
@testable import Mindlore

// A poem, lyrics, or a story is work the author made, not an account of their life: its names,
// area, mood, and loose ends are never taken as facts (owner, 2026-09-22).
@MainActor
struct CreativeEntryTests {
    // The same full answer as InsightsHarness.fullResponse, with the model calling it creative.
    static let creativeResponse = InsightsHarness.fullResponse.replacingOccurrences(of: #"{"summary""#, with: #"{"entryKind":"creative","summary""#)

    // Tags stay: a theme ("ocean", "leaving") is not a claim about the author's life. People,
    // places, and the rest are.
    private func nameLinks(_ context: ModelContext) throws -> Int {
        try context.fetch(FetchDescriptor<EntityLink>()).filter { $0.kindRaw != EntityKind.tag.rawValue }.count
    }

    @Test func theSchemaAsksFirstAndTheParserReadsIt() throws {
        let plan = InsightsPromptBuilder.plan(text: "x", source: .typed, sections: InsightSections(), vocabulary: .empty, model: "m")
        guard case .object(let properties, _, _) = try #require(plan.request.schema) else { Issue.record("not an object"); return }
        #expect(properties.first?.name == "entryKind", "decided before the fields it changes")
        #expect(try InsightsPromptBuilder.parse(Self.creativeResponse, plan: plan).creative)
        #expect(try !InsightsPromptBuilder.parse(InsightsHarness.fullResponse, plan: plan).creative, "a missing answer means life")
        #expect(try InsightsPromptBuilder.parse(InsightsHarness.fullResponse, plan: plan).kind == .journal)
        let kinds = (properties.first?.schema).flatMap { schema -> [String]? in
            if case .enumeration(let values, _, _) = schema { return values } else { return nil }
        }
        #expect(kinds == ["life", "note", "creative"], "every kind the app knows, in the picker's order")
    }

    @Test func aCreativeEntryKeepsItsTitleTagsAndSummaryAndNothingElse() async throws {
        let harness = try InsightsHarness()
        harness.useGraph = true
        let entry = try harness.entry("Rosa drove to Memphis with the moon on the water")
        harness.generator.results = [.success(Self.creativeResponse)]

        await harness.coordinator.processQueue(context: harness.context)

        #expect(entry.isCreative)
        #expect(!entry.creativeSetByUser)
        let insights = try #require(entry.insights)
        #expect(insights.summary == "A river walk.")
        #expect(insights.tags == ["nature"])
        #expect(insights.areas.isEmpty)
        #expect(insights.mentions.isEmpty)
        #expect(insights.primaryMood == nil, "a sad poem is not a sad week")
        #expect(try nameLinks(harness.context) == 0, "Rosa never reaches the map")
        #expect(try harness.context.fetchCount(FetchDescriptor<LooseEnd>()) == 0)
    }

    @Test func theUsersCallIsNeverOverridden() async throws {
        let harness = try InsightsHarness()
        let entry = try harness.entry("A day at the river with Sarah")
        entry.setCreativeByUser(false)
        harness.generator.results = [.success(Self.creativeResponse)]

        await harness.coordinator.processQueue(context: harness.context)

        #expect(!entry.isCreative)
        #expect(entry.insights?.areas == [.health], "read as life, as the user said")
    }

    @Test func markingAnEntryCreativeTakesItsNamesAreaMoodAndOpenThreads() async throws {
        let harness = try InsightsHarness()
        harness.useGraph = true
        let entry = try harness.entry("Sarah by the river")
        // Recent, so the loose end the answer raises is born open rather than already faded.
        entry.entryDate = .now
        harness.generator.results = [.success(InsightsHarness.fullResponse)]
        await harness.coordinator.processQueue(context: harness.context)
        #expect(try nameLinks(harness.context) == 1)
        let touched = LooseEnd(text: "kept by the user", sourceEntryID: entry.id, sourceEntryDate: entry.entryDate)
        touched.setByUser(.resolved)
        harness.context.insert(touched)
        try harness.context.save()

        GraphServices(diagnostics: .disabled).setCreative(true, on: entry, in: harness.context)

        #expect(entry.isCreative && entry.creativeSetByUser)
        #expect(entry.insights?.areas.isEmpty == true)
        #expect(entry.insights?.primaryMood == nil)
        #expect(try nameLinks(harness.context) == 0)
        let ends = LooseEnd.all(in: harness.context)
        #expect(ends.first { $0.text == "Call Sarah" }?.status == .dismissed)
        #expect(ends.first { $0.text == "kept by the user" }?.status == .resolved, "the user's own stay theirs")
    }

    @Test func askAndReflectSayItIsWriting() {
        let block = AskContextBuilder.block(handle: "E1", date: .now, title: "Memphis", text: "moon on the water", creative: true)
        #expect(block.contains(AskContextBuilder.creativeMarker))
        #expect(!AskContextBuilder.block(handle: "E1", date: .now, title: "t", text: "x").contains(AskContextBuilder.creativeMarker))
        #expect(AskPrompt.system(today: .now).contains(AskPrompt.creativeRule))
        #expect(AskPrompt.system(today: .now, provider: .onDevice).contains(AskPrompt.creativeRuleShort))

        let poem = ReflectFidelity.WeekEntry(id: UUID(), date: .now, title: "Memphis", text: "moon", isCreative: true)
        #expect(ReflectFidelity.weekPrompt([poem]).contains(AskContextBuilder.creativeMarker))
        let life = ReflectFidelity.WeekEntry(id: poem.id, date: poem.date, title: poem.title, text: poem.text)
        #expect(ReflectSummaryStore.fingerprint([poem]) != ReflectSummaryStore.fingerprint([life]), "flipping it rewrites a running week")
    }
}
