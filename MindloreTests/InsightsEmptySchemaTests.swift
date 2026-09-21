import Foundation
import SwiftData
import Testing
@testable import Mindlore

// Turning every insight section off used to send a request with an empty schema, which the provider
// rejects (docs/remaining-work.md). The guard sits on the built request rather than on
// InsightSections, because which sections reach the schema depends on the entry: cleanup is only
// offered for voice and photo, and the written date only for typed. A settings-level predicate is
// wrong in both directions, and these tests are the two directions.
@MainActor
struct InsightsEmptySchemaTests {
    private func sections(everythingOff: Bool = true) -> InsightSections {
        var sections = InsightSections()
        sections.summary = false
        sections.moods = false
        sections.lifeAreas = false
        sections.tags = false
        sections.mentions = false
        sections.looseEnds = false
        sections.cleanedText = false
        sections.suggestEntryDates = false
        sections.customPrompts = []
        return sections
    }

    private func coordinator(_ generator: FakeTextGenerator, _ sections: @escaping () -> InsightSections) -> InsightsCoordinator {
        InsightsCoordinator(
            resolve: { .success(.init(generator: generator, model: "m", label: "test:m")) },
            sections: sections,
            autoApplyCleanedText: { false },
            presence: EditorPresence()
        )
    }

    @Test func nothingIsSentWhenTheSchemaWouldBeEmpty() async throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let generator = FakeTextGenerator()
        let insights = coordinator(generator) { self.sections() }

        let entry = Entry(source: .voice, text: "I walked to the river.")
        context.insert(entry)
        entry.insightsPending = true
        try context.save()

        await insights.processQueue(context: context)

        #expect(generator.requests.isEmpty)
        #expect(entry.insights == nil)
        // No attempt counted: nothing was sent, so nothing failed.
        #expect(entry.insightsAttempts == 0)
        // Still pending, so turning a section back on runs it rather than skipping it forever.
        #expect(entry.insightsPending)
    }

    @Test func turningASectionBackOnRunsTheEntryThatWasSkipped() async throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let generator = FakeTextGenerator()
        var enabled = false
        let insights = coordinator(generator) {
            var sections = self.sections()
            sections.summary = enabled
            return sections
        }

        let entry = Entry(source: .voice, text: "I walked to the river.")
        context.insert(entry)
        entry.insightsPending = true
        try context.save()

        await insights.processQueue(context: context)
        #expect(generator.requests.isEmpty)

        generator.results = [.success(#"{"summary":"A walk."}"#)]
        enabled = true
        await insights.processQueue(context: context)

        #expect(generator.requests.count == 1)
        #expect(entry.insights?.summary == "A walk.")
    }

    // The case the first draft of the spec called safe. Cleanup keeps InsightSections.isEmpty false,
    // so a settings-level guard would have let this through, and the schema is empty all the same
    // because cleanup is never offered for typed text.
    @Test func cleanupOnlyIsEmptyForATypedEntryThoughTheSectionsAreNotEmpty() async throws {
        var sections = self.sections()
        sections.cleanedText = true
        #expect(!sections.isEmpty)

        let typed = InsightsPromptBuilder.plan(text: "x", source: .typed, sections: sections, vocabulary: .empty, model: "m")
        #expect(typed.asksForNothing)

        let voice = InsightsPromptBuilder.plan(text: "x", source: .voice, sections: sections, vocabulary: .empty, model: "m")
        #expect(!voice.asksForNothing)
    }

    // The other direction. Only the written date is asked for, which InsightSections.isEmpty does
    // not count, so a settings-level guard would have blocked a request that is perfectly valid.
    @Test func entryDatesOnlyIsAValidRequestForATypedEntry() async throws {
        var sections = self.sections()
        sections.suggestEntryDates = true
        #expect(sections.isEmpty)

        let typed = InsightsPromptBuilder.plan(text: "x", source: .typed, sections: sections, vocabulary: .empty, model: "m")
        #expect(!typed.asksForNothing)

        // The same settings give a voice entry nothing, because the written date is typed-only.
        let voice = InsightsPromptBuilder.plan(text: "x", source: .voice, sections: sections, vocabulary: .empty, model: "m")
        #expect(voice.asksForNothing)
    }

    // Run AI is the one path that spends the entry's automatic pass before the request is built,
    // so it short-circuits too rather than burning the pass on a request nothing will send.
    @Test func runAIDoesNotSpendTheAutomaticPassWhenThereIsNothingToAsk() async throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let generator = FakeTextGenerator()
        let insights = coordinator(generator) { self.sections() }

        let entry = Entry(source: .voice, text: "I walked to the river.")
        context.insert(entry)
        try context.save()

        await insights.runAI(for: entry, context: context)

        #expect(generator.requests.isEmpty)
        #expect(!entry.automaticAIPassUsed)
    }

    // The review of the first version of this guard: runAI short-circuited on InsightSections.isEmpty,
    // which is true here, so Run AI on this entry did nothing at all while the request it would have
    // made is valid. It asks the builder now.
    @Test func runAIStillRunsATypedEntryWhenOnlyEntryDatesAreOn() async throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let generator = FakeTextGenerator()
        generator.results = [.success(#"{"writtenDate":null}"#)]
        let insights = coordinator(generator) {
            var sections = self.sections()
            sections.suggestEntryDates = true
            return sections
        }

        let entry = Entry(source: .typed, text: "Monday 3 March 2025. Rain again.")
        context.insert(entry)
        try context.save()

        await insights.runAI(for: entry, context: context)

        #expect(generator.requests.count == 1)
        #expect(entry.automaticAIPassUsed)
    }
}
