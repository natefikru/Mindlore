import Foundation
import Testing
@testable import Mindlore

@MainActor
struct ReflectNarratorTests {
    private func provider(_ generator: FakeTextGenerator) -> AskProvider {
        AskProvider(generator: generator, model: "test-model", label: "test", kind: .openAI)
    }

    private func period(
        entryCount: Int = 3,
        moodCounts: [MoodCategory: Int] = [.calm: 2],
        areaCounts: [LifeArea: Int] = [.work: 1],
        topTags: [ReflectAggregator.TagCount] = []
    ) -> ReflectAggregator.Period {
        ReflectAggregator.Period(
            interval: DateInterval(start: .now, duration: 86_400 * 7),
            entryCount: entryCount,
            moodCounts: moodCounts,
            areaCounts: areaCounts,
            topTags: topTags,
            looseEndsOpened: 0,
            looseEndsClosed: 0
        )
    }

    @Test func returnsTheGeneratedTextTrimmed() async throws {
        let generator = FakeTextGenerator()
        generator.results = [.success("  A quiet week, mostly at work.  ")]
        let text = await ReflectNarrator.narrate(
            period: period(),
            kind: .week,
            title: "Week of 14 September 2026",
            provider: provider(generator),
            voice: .default,
            areaName: \.defaultName
        )
        #expect(text == "A quiet week, mostly at work.")
    }

    @Test func anEmptyPeriodNeverCallsTheGenerator() async {
        let generator = FakeTextGenerator()
        _ = await ReflectNarrator.narrate(
            period: period(entryCount: 0, moodCounts: [:], areaCounts: [:]),
            kind: .week,
            title: "Week of 14 September 2026",
            provider: provider(generator),
            voice: .default,
            areaName: \.defaultName
        )
        #expect(generator.requests.isEmpty)
    }

    @Test func aFailureReturnsNilRatherThanThrowing() async {
        let generator = FakeTextGenerator()
        generator.results = [.failure(AIError.network(.notConnectedToInternet))]
        let text = await ReflectNarrator.narrate(
            period: period(),
            kind: .month,
            title: "September 2026",
            provider: provider(generator),
            voice: .default,
            areaName: \.defaultName
        )
        #expect(text == nil)
    }

    // The prompt is meant to carry top tags (owner decision 3); this pins that on purpose, apart
    // from the diagnostics test below which pins the opposite for the log.
    @Test func thePromptCarriesTopTags() async throws {
        let generator = FakeTextGenerator()
        generator.results = [.success("Summary.")]
        _ = await ReflectNarrator.narrate(
            period: period(topTags: [.init(tag: "deadline", count: 3)]),
            kind: .week,
            title: "Week of 14 September 2026",
            provider: provider(generator),
            voice: .default,
            areaName: \.defaultName
        )
        let request = try #require(generator.requests.first)
        #expect(request.user.contains("deadline"))
        #expect(request.model == "test-model")
    }

    @Test func diagnosticsNeverCarryATagOrAnyOtherFreeText() async throws {
        let sentinel = "PRIVATE-SENTINEL-7Q2X"
        let file = DiagnosticsFile()
        let log = DiagnosticsLog(fileURL: file.url)
        let generator = FakeTextGenerator()
        generator.results = [.success("Summary with \(sentinel) in it.")]

        _ = await ReflectNarrator.narrate(
            period: period(topTags: [.init(tag: sentinel, count: 1)]),
            kind: .week,
            title: "Week \(sentinel)",
            provider: provider(generator),
            voice: PromptVoice(voice: .name, name: sentinel),
            areaName: { _ in sentinel },
            diagnostics: log
        )

        let contents = file.contents()
        #expect(contents.contains("reflect.narrated"))
        #expect(contents.contains(sentinel) == false)
    }
}
