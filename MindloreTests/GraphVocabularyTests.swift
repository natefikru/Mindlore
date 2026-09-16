import Foundation
import SwiftData
import Testing
@testable import Mindlore

// What the journal already calls things, handed to the next insights request so the model
// reuses the user's words instead of inventing a near-duplicate.
struct JournalVocabularyPromptTests {
    private func plan(_ vocabulary: InsightsPromptBuilder.JournalVocabulary) -> InsightsRequestPlan {
        InsightsPromptBuilder.plan(text: "x", source: .typed, sections: InsightSections(), vocabulary: vocabulary, model: "m")
    }

    @Test func knownNamesAreSentWithTheirKind() {
        let system = plan(.init(named: [
            .init(name: "Sarah Kim", kind: .person),
            .init(name: "Acme", kind: .organization),
        ])).request.system

        #expect(system.contains("Sarah Kim (person)"))
        #expect(system.contains("Acme (organization)"))
        #expect(system.contains("use this exact name and kind rather than a variation"))
    }

    @Test func knownThemesAreSent() {
        let system = plan(.init(themes: ["career anxiety", "moving house"])).request.system
        #expect(system.contains("career anxiety, moving house"))
        #expect(system.contains("Themes already used in this journal"))
    }

    @Test func eachListIsCappedAtFifty() {
        let many = (1...80).map { "item \($0)" }
        let system = plan(.init(
            tags: many,
            themes: many,
            named: many.map { .init(name: $0, kind: .person) }
        )).request.system

        #expect(system.contains("item 50"))
        #expect(!system.contains("item 51"))
    }

    @Test func nothingIsSaidWhenTheJournalIsEmpty() {
        let system = plan(.empty).request.system
        #expect(!system.contains("already used in this journal"))
        #expect(!system.contains("Named things already in this journal"))
    }

    // A section that is switched off should not carry its vocabulary either.
    @Test func aDisabledSectionSendsNoVocabulary() {
        var sections = InsightSections()
        sections.mentions = false
        sections.themes = false
        let system = InsightsPromptBuilder.plan(
            text: "x", source: .typed, sections: sections,
            vocabulary: .init(themes: ["career anxiety"], named: [.init(name: "Sarah Kim", kind: .person)]),
            model: "m"
        ).request.system

        #expect(!system.contains("Sarah Kim"))
        #expect(!system.contains("career anxiety"))
    }
}

@MainActor
struct GraphVocabularyTests {
    let harness: GraphHarness

    init() throws {
        harness = try GraphHarness()
    }

    @Test func theVocabularyComesFromTheGraphMostUsedFirst() throws {
        try harness.entry(tags: ["work"], themes: ["moving house"], mentions: [("Sarah Kim", .person)])
        try harness.entry(tags: ["work", "family"], mentions: [("Sarah Kim", .person), ("Acme", .organization)])
        harness.indexer.sweep(in: harness.context)

        let vocabulary = harness.indexer.vocabulary(in: harness.context)

        #expect(vocabulary.tags == ["work", "family"], "the busier tag comes first")
        #expect(vocabulary.themes == ["moving house"])
        #expect(vocabulary.named.map(\.name) == ["Sarah Kim", "Acme"])
        #expect(vocabulary.named.first?.kind == .person)
        // Tags and themes are their own lists, never mixed into the names.
        #expect(!vocabulary.named.contains { $0.kind == .tag || $0.kind == .theme })
    }

    // Hidden is the user saying they do not want to see it. Steering the model towards it
    // would bring it back through the front door.
    @Test func hiddenAndMergedEntitiesAreLeftOut() throws {
        try harness.entry(tags: ["work"], mentions: [("Sarah Kim", .person), ("Sarah K", .person)])
        harness.indexer.sweep(in: harness.context)
        let editor = GraphEditor(diagnostics: .disabled)

        editor.setHidden(true, on: try harness.entity("work"))
        editor.merge(try harness.entity("Sarah K"), into: try harness.entity("Sarah Kim"), in: harness.context)
        try harness.context.save()

        let vocabulary = harness.indexer.vocabulary(in: harness.context)
        #expect(vocabulary.tags.isEmpty)
        #expect(vocabulary.named.map(\.name) == ["Sarah Kim"], "the loser's name is already an alias of the winner")
    }

    @Test func anEmptyGraphGivesAnEmptyVocabulary() throws {
        #expect(harness.indexer.vocabulary(in: harness.context) == .empty)
    }
}

@MainActor
struct InsightsUseTheJournalVocabularyTests {
    // The coordinator has to actually ask for it and put it in the request, not just be
    // handed one. This is the wiring RootView relies on.
    @Test func theRequestCarriesTheNamesTheJournalKnows() async throws {
        let harness = try InsightsHarness()
        harness.vocabulary = .init(themes: ["moving house"], named: [.init(name: "Sarah Kim", kind: .person)])
        harness.generator.results = [.success(InsightsHarness.fullResponse)]
        try harness.entry("Lunch with Sarah.")

        await harness.coordinator.processQueue(context: harness.context)

        let system = try #require(harness.generator.requests.first).system
        #expect(system.contains("Sarah Kim (person)"))
        #expect(system.contains("moving house"))
    }
}
