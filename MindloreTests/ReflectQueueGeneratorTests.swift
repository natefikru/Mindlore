import Foundation
import Testing
@testable import Mindlore

@MainActor
struct ReflectQueueGeneratorTests {
    private func provider(_ generator: FakeTextGenerator) -> AskProvider {
        AskProvider(generator: generator, model: "test-model", label: "test", kind: .openAI)
    }

    @Test func parsesASingleSummaryItemWithAKindSpecificTitle() async throws {
        let fake = FakeTextGenerator()
        fake.results = [.success(#"{"summary":"Money came up a lot this week.","prompt":"What changed with money?"}"#)]

        let items = await ReflectQueueGenerator.generate(
            kind: .week,
            title: "Week of 14 September 2026",
            prompt: "<<<entry\n2026-09-15 A day\nSome text\nentry>>>",
            provider: provider(fake),
            voice: .default
        )

        let item = try #require(items?.first)
        #expect(items?.count == 1)
        #expect(item.source == .generated)
        #expect(item.title == "This week")
        #expect(item.body == "Money came up a lot this week.")
        #expect(item.prompt == "What changed with money?")
    }

    @Test func aMonthsItemIsTitledThisMonth() async throws {
        let fake = FakeTextGenerator()
        fake.results = [.success(#"{"summary":"A steady month.","prompt":"What made it steady?"}"#)]

        let items = await ReflectQueueGenerator.generate(kind: .month, title: "June 2026", prompt: "p", provider: provider(fake), voice: .default)

        #expect(try #require(items?.first).title == "This month")
    }

    @Test func anEmptySummaryIsCachedAsAllCaughtUp() async {
        let fake = FakeTextGenerator()
        fake.results = [.success(#"{"summary":"","prompt":""}"#)]

        let items = await ReflectQueueGenerator.generate(kind: .week, title: "t", prompt: "p", provider: provider(fake), voice: .default)

        #expect(items == [])
    }

    // A summary with no prompt (or the reverse) is treated the same as nothing to say: half a
    // card is worse than none.
    @Test func aSummaryWithNoPromptIsDropped() async {
        let fake = FakeTextGenerator()
        fake.results = [.success(#"{"summary":"Something happened.","prompt":""}"#)]

        let items = await ReflectQueueGenerator.generate(kind: .week, title: "t", prompt: "p", provider: provider(fake), voice: .default)

        #expect(items == [])
    }

    // Malformed JSON degrades to "nothing to say," not a crash: the same tolerant-parsing rule
    // Insights follows.
    @Test func malformedJSONYieldsAnEmptyList() async {
        let fake = FakeTextGenerator()
        fake.results = [.success("not json at all")]

        let items = await ReflectQueueGenerator.generate(kind: .week, title: "t", prompt: "p", provider: provider(fake), voice: .default)

        #expect(items == [])
    }

    // A failed request is a failed generation, not an empty one: the caller must be able to tell
    // "nothing to say" (cache it) apart from "the request didn't go through" (retry later).
    @Test func aProviderErrorReturnsNilRatherThanAnEmptyList() async {
        let fake = FakeTextGenerator()
        fake.results = [.failure(AIError.invalidResponse)]

        let items = await ReflectQueueGenerator.generate(kind: .week, title: "t", prompt: "p", provider: provider(fake), voice: .default)

        #expect(items == nil)
    }
}
