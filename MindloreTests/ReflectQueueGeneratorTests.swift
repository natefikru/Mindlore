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

    // An answer that can't be read is a failed generation, not "nothing to say": caching it as
    // all caught up is how every period on the phone ended up permanently blank.
    @Test func malformedJSONIsRetriedNotCached() async {
        let fake = FakeTextGenerator()
        fake.results = [.success("not json at all")]

        let items = await ReflectQueueGenerator.generate(kind: .week, title: "t", prompt: "p", provider: provider(fake), voice: .default)

        #expect(items == nil)
    }

    // The on-device model ignores the schema, so it's asked for the paragraph and a "Question:"
    // line, and that's what gets read back.
    @Test func theOnDeviceModelsProseIsReadAsASummaryAndAQuestion() async throws {
        let fake = FakeTextGenerator()
        fake.results = [.success("**Summary:** Danny opened El Primo and I worked the window.\n\nQuestion: What did the first customer order?")]
        let onDevice = AskProvider(generator: fake, model: "", label: "apple", kind: .onDevice)

        let items = await ReflectQueueGenerator.generate(kind: .week, title: "t", prompt: "p", provider: onDevice, voice: .default)

        let item = try #require(items?.first)
        #expect(item.body == "Danny opened El Primo and I worked the window.")
        #expect(item.prompt == "What did the first customer order?")
        #expect(fake.requests.first?.schema == nil)
    }

    @Test func aQuestionRunOnTheEndOfTheParagraphStillCounts() {
        let plain = ReflectQueueGenerator.plainText("Rosa got married and I saw Maya. Question: What did I want to say to her?")
        #expect(plain?.summary == "Rosa got married and I saw Maya.")
        #expect(plain?.prompt == "What did I want to say to her?")
    }

    @Test func onDeviceProseWithNoQuestionIsRetried() async {
        let fake = FakeTextGenerator()
        fake.results = [.success("A long week at work.")]
        let onDevice = AskProvider(generator: fake, model: "", label: "apple", kind: .onDevice)

        let items = await ReflectQueueGenerator.generate(kind: .week, title: "t", prompt: "p", provider: onDevice, voice: .default)

        #expect(items == nil)
    }

    @Test func onlyTheOnDeviceModelGetsAPromptLimit() {
        let fake = FakeTextGenerator()
        #expect(ReflectQueueGenerator.promptLimit(for: provider(fake)) == nil)
        #expect(ReflectQueueGenerator.promptLimit(for: AskProvider(generator: fake, model: "", label: "apple", kind: .onDevice)) == ReflectQueueGenerator.onDevicePromptLimit)
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
