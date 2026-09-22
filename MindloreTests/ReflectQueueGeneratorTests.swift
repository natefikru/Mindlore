import Foundation
import Testing
@testable import Mindlore

@MainActor
struct ReflectQueueGeneratorTests {
    private func provider(_ generator: FakeTextGenerator) -> AskProvider {
        AskProvider(generator: generator, model: "test-model", label: "test", kind: .openAI)
    }

    @Test func parsesItemsAndAssignsAFixedTitleAndSource() async throws {
        let fake = FakeTextGenerator()
        fake.results = [.success(#"{"items":[{"body":"Money came up a lot.","prompt":"What changed with money?"}]}"#)]

        let items = await ReflectQueueGenerator.generate(
            kind: .week,
            title: "Week of 14 September 2026",
            prompt: "<<<entry\n2026-09-15 A day\nSome text\nentry>>>",
            provider: provider(fake),
            voice: .default
        )

        let item = try #require(items?.first)
        #expect(item.source == .generated)
        #expect(item.title == "Worth asking")
        #expect(item.body == "Money came up a lot.")
        #expect(item.prompt == "What changed with money?")
    }

    @Test func anEmptyItemsListIsCachedAsAllCaughtUp() async {
        let fake = FakeTextGenerator()
        fake.results = [.success(#"{"items":[]}"#)]

        let items = await ReflectQueueGenerator.generate(kind: .week, title: "t", prompt: "p", provider: provider(fake), voice: .default)

        #expect(items == [])
    }

    @Test func itemsMissingABodyOrPromptAreDropped() async {
        let fake = FakeTextGenerator()
        fake.results = [.success(#"{"items":[{"body":"","prompt":"a question"},{"body":"a fact","prompt":""},{"body":"good","prompt":"good?"}]}"#)]

        let items = await ReflectQueueGenerator.generate(kind: .week, title: "t", prompt: "p", provider: provider(fake), voice: .default)

        #expect(items?.count == 1)
        #expect(items?.first?.body == "good")
    }

    @Test func itemsAreCappedAtMaxItems() async {
        let fake = FakeTextGenerator()
        let many = (0..<10).map { "{\"body\":\"note \($0)\",\"prompt\":\"question \($0)\"}" }.joined(separator: ",")
        fake.results = [.success("{\"items\":[\(many)]}")]

        let items = await ReflectQueueGenerator.generate(kind: .month, title: "t", prompt: "p", provider: provider(fake), voice: .default)

        #expect(items?.count == ReflectQueueGenerator.maxItems)
    }

    // Malformed JSON degrades to "nothing to ask about," not a crash: the same tolerant-parsing
    // rule Insights follows.
    @Test func malformedJSONYieldsAnEmptyList() async {
        let fake = FakeTextGenerator()
        fake.results = [.success("not json at all")]

        let items = await ReflectQueueGenerator.generate(kind: .week, title: "t", prompt: "p", provider: provider(fake), voice: .default)

        #expect(items == [])
    }

    // A failed request is a failed generation, not an empty one: the caller must be able to tell
    // "nothing to ask about" (cache it) apart from "the request didn't go through" (retry later).
    @Test func aProviderErrorReturnsNilRatherThanAnEmptyList() async {
        let fake = FakeTextGenerator()
        fake.results = [.failure(AIError.invalidResponse)]

        let items = await ReflectQueueGenerator.generate(kind: .week, title: "t", prompt: "p", provider: provider(fake), voice: .default)

        #expect(items == nil)
    }
}
