import Foundation
import SwiftData
import Testing
@testable import Mindlore

@MainActor
struct ReflectSummaryStoreTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    init() throws {
        container = try ModelContainerFactory.make(.inMemory)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @discardableResult
    private func entry(_ text: String = "some entry text", on day: Date, title: String = "", isDraft: Bool = false) -> Entry {
        let entry = Entry(text: text)
        entry.title = title
        entry.entryDate = day
        entry.isDraft = isDraft
        context.insert(entry)
        return entry
    }

    private func resolve(_ fake: FakeTextGenerator) -> () -> Result<AskProvider, AIJobFailure> {
        { .success(AskProvider(generator: fake, model: "test", label: "test", kind: .openAI)) }
    }

    // MARK: - Generate once, cache, read back

    @Test func generateOnceAndCacheIsIdempotent() async throws {
        let week = utc.dateInterval(of: .weekOfYear, for: date(2026, 9, 8))!
        entry("wrote about the new job", on: week.start)
        try context.save()

        let fake = FakeTextGenerator()
        fake.results = [.success(#"{"summary":"A new job came up.","prompt":"How's the new job going?"}"#)]

        let first = await ReflectSummaryStore.generateIfNeeded(
            kind: .week, interval: week, resolve: resolve(fake), voice: .default, calendar: utc, in: context
        )
        #expect(first?.items.first?.body == "A new job came up.")
        #expect(fake.requests.count == 1)

        // A second call finds the cache and makes no request.
        let second = await ReflectSummaryStore.generateIfNeeded(
            kind: .week, interval: week, resolve: resolve(fake), voice: .default, calendar: utc, in: context
        )
        #expect(fake.requests.count == 1, "a cached period is read back, never asked about again")
        #expect(second?.items == first?.items)
    }

    // A week or month with nothing eligible is cached as an empty summary without ever calling the
    // provider, so an empty stretch of the journal costs nothing.
    @Test func aWeekWithNoEligibleEntriesIsCachedWithoutARequest() async throws {
        let week = utc.dateInterval(of: .weekOfYear, for: date(2026, 9, 8))!
        let fake = FakeTextGenerator()

        let summary = await ReflectSummaryStore.generateIfNeeded(
            kind: .week, interval: week, resolve: resolve(fake), voice: .default, calendar: utc, in: context
        )

        #expect(summary?.items == [])
        #expect(fake.requests.isEmpty)
    }

    @Test func aFailedGenerationWritesNothingAndIsRetriedNextTime() async throws {
        let week = utc.dateInterval(of: .weekOfYear, for: date(2026, 9, 8))!
        entry("wrote about the new job", on: week.start)
        try context.save()

        let failing = FakeTextGenerator()
        failing.results = [.failure(AIError.invalidResponse)]
        let firstAttempt = await ReflectSummaryStore.generateIfNeeded(
            kind: .week, interval: week, resolve: resolve(failing), voice: .default, calendar: utc, in: context
        )
        #expect(firstAttempt == nil)
        #expect(ReflectSummaryStore.summary(kind: .week, periodStart: week.start, in: context) == nil, "a failure writes nothing")

        let succeeding = FakeTextGenerator()
        succeeding.results = [.success(#"{"summary":"noticed","prompt":"ask?"}"#)]
        let retried = await ReflectSummaryStore.generateIfNeeded(
            kind: .week, interval: week, resolve: resolve(succeeding), voice: .default, calendar: utc, in: context
        )
        #expect(retried?.items.first?.body == "noticed", "the next call tries again rather than remembering the failure")
    }

    // MARK: - The running week (owner, 2026-09-22)

    private func rows(for week: DateInterval) -> Int {
        let start = week.start
        return (try? context.fetchCount(FetchDescriptor<ReflectSummary>(predicate: #Predicate { $0.periodStart == start }))) ?? -1
    }

    private func reply(_ body: String) -> Result<String, any Error> {
        .success(#"{"summary":"\#(body)","prompt":"ask?"}"#)
    }

    @Test func aBurstOfChangesRewritesTheRunningWeekOnceInTheBackground() async throws {
        let week = utc.dateInterval(of: .weekOfYear, for: .now)!
        entry("something this week", on: min(.now, week.start.addingTimeInterval(3_600)))
        try context.save()
        let fake = FakeTextGenerator()
        fake.results = [reply("Busy week.")]
        for _ in 0..<5 {
            ReflectSummaryStore.scheduleCurrentWeekRefresh(resolve: resolve(fake), voice: { .default }, isEditing: { false }, quiet: .milliseconds(20), calendar: utc, in: context)
        }
        await ReflectSummaryStore.pendingRefresh?.value
        #expect(fake.requests.count == 1)
        #expect(ReflectSummaryStore.summary(kind: .week, periodStart: week.start, in: context)?.items.first?.body == "Busy week.")
    }

    @Test func theBackgroundRewriteWaitsWhileAnEditorIsOpen() async throws {
        let week = utc.dateInterval(of: .weekOfYear, for: .now)!
        entry("something this week", on: min(.now, week.start.addingTimeInterval(3_600)))
        try context.save()
        let fake = FakeTextGenerator()
        ReflectSummaryStore.scheduleCurrentWeekRefresh(resolve: resolve(fake), voice: { .default }, isEditing: { true }, quiet: .milliseconds(20), calendar: utc, in: context)
        await ReflectSummaryStore.pendingRefresh?.value
        #expect(fake.requests.isEmpty)
    }

    @Test func theRunningWeekIsRewrittenWhenItsEntriesChange() async throws {
        let week = utc.dateInterval(of: .weekOfYear, for: .now)!
        entry("first thing this week", on: week.start)
        try context.save()
        let fake = FakeTextGenerator()
        fake.results = [reply("one"), reply("two")]

        let first = await ReflectSummaryStore.generateIfNeeded(kind: .week, interval: week, resolve: resolve(fake), voice: .default, calendar: utc, in: context)
        #expect(first?.items.first?.body == "one")
        _ = await ReflectSummaryStore.generateIfNeeded(kind: .week, interval: week, resolve: resolve(fake), voice: .default, calendar: utc, in: context)
        #expect(fake.requests.count == 1, "nothing changed, nothing asked")

        entry("second thing this week", on: week.start)
        try context.save()
        let second = await ReflectSummaryStore.generateIfNeeded(kind: .week, interval: week, resolve: resolve(fake), voice: .default, calendar: utc, in: context)
        #expect(fake.requests.count == 2)
        #expect(second?.items.first?.body == "two")
        #expect(rows(for: week) == 1, "a rewrite replaces the row rather than adding one")
    }

    @Test func aWeekSummedUpAfterItEndedIsFinal() async throws {
        let week = utc.dateInterval(of: .weekOfYear, for: date(2026, 9, 8))!
        entry("wrote about the new job", on: week.start)
        try context.save()
        let fake = FakeTextGenerator()
        fake.results = [reply("done")]
        _ = await ReflectSummaryStore.generateIfNeeded(kind: .week, interval: week, resolve: resolve(fake), voice: .default, calendar: utc, in: context)

        entry("a late addition to that week", on: week.start)
        try context.save()
        let again = await ReflectSummaryStore.generateIfNeeded(kind: .week, interval: week, resolve: resolve(fake), voice: .default, calendar: utc, in: context)

        #expect(fake.requests.count == 1)
        #expect(again?.items.first?.body == "done")
    }

    // Written on the Wednesday, then more entries: once the week is over it is summed up one last
    // time from everything, and that one stands.
    @Test func aMidWeekSummaryIsRewrittenOnceAfterTheWeekEnds() async throws {
        let week = utc.dateInterval(of: .weekOfYear, for: date(2026, 9, 8))!
        entry("wrote about the new job", on: week.start)
        context.insert(ReflectSummary(
            kind: .week, periodStart: week.start, generatedAt: week.start.addingTimeInterval(86_400),
            items: [ReflectQueueItem(id: "old", source: .generated, title: "t", body: "partial", prompt: "p")],
            sourceFingerprint: "an earlier set of entries"
        ))
        try context.save()
        let fake = FakeTextGenerator()
        fake.results = [reply("whole week")]

        let final = await ReflectSummaryStore.generateIfNeeded(kind: .week, interval: week, resolve: resolve(fake), voice: .default, calendar: utc, in: context)
        _ = await ReflectSummaryStore.generateIfNeeded(kind: .week, interval: week, resolve: resolve(fake), voice: .default, calendar: utc, in: context)

        #expect(final?.items.first?.body == "whole week")
        #expect(fake.requests.count == 1)
        #expect(rows(for: week) == 1)
    }

    @Test func aFailedRewriteKeepsTheSummaryItHad() async throws {
        let week = utc.dateInterval(of: .weekOfYear, for: .now)!
        entry("first thing this week", on: week.start)
        try context.save()
        let fake = FakeTextGenerator()
        fake.results = [reply("one"), .failure(AIError.invalidResponse)]
        _ = await ReflectSummaryStore.generateIfNeeded(kind: .week, interval: week, resolve: resolve(fake), voice: .default, calendar: utc, in: context)

        entry("second thing this week", on: week.start)
        try context.save()
        let kept = await ReflectSummaryStore.generateIfNeeded(kind: .week, interval: week, resolve: resolve(fake), voice: .default, calendar: utc, in: context)

        #expect(kept?.items.first?.body == "one")
    }

    // MARK: - The launch sweep's scope

    @Test func sweepOnlyTouchesTheMostRecentlyCompletedWeekAndMonth() async {
        let now = date(2026, 9, 21)
        let fake = FakeTextGenerator()
        fake.results = Array(repeating: .success(#"{"summary":"","prompt":""}"#), count: 10)

        await ReflectSummaryStore.sweepMostRecentlyCompleted(resolve: resolve(fake), voice: .default, now: now, calendar: utc, in: context)

        let allSummaries = (try? context.fetch(FetchDescriptor<ReflectSummary>())) ?? []
        #expect(allSummaries.count == 2, "exactly one week and one month, nothing older backfilled")
        #expect(allSummaries.contains { $0.kind == .week })
        #expect(allSummaries.contains { $0.kind == .month })

        let previousWeek = utc.dateInterval(of: .weekOfYear, for: utc.date(byAdding: .weekOfYear, value: -1, to: now)!)!
        let previousMonth = utc.dateInterval(of: .month, for: utc.date(byAdding: .month, value: -1, to: now)!)!
        #expect(allSummaries.contains { $0.kind == .week && $0.periodStart == previousWeek.start })
        #expect(allSummaries.contains { $0.kind == .month && $0.periodStart == previousMonth.start })
    }

    // MARK: - Tiered fidelity

    @Test func aWeeksPromptCarriesFullSanitizedTextAndExcludesADraft() async throws {
        let week = utc.dateInterval(of: .weekOfYear, for: date(2026, 9, 8))!
        entry("A specific thing that happened at work.", on: week.start, title: "Work day")
        entry("Something still unfinished, typed but not done.", on: week.start.addingTimeInterval(3600), isDraft: true)
        try? context.save()

        let fake = FakeTextGenerator()
        fake.results = [.success(#"{"summary":"","prompt":""}"#)]
        _ = await ReflectSummaryStore.generateIfNeeded(
            kind: .week, interval: week, resolve: resolve(fake), voice: .default, calendar: utc, in: context
        )

        let sent = try #require(fake.requests.first).user
        #expect(sent.contains("A specific thing that happened at work."))
        #expect(!sent.contains("Something still unfinished"), "a draft is never eligible")
    }

    @Test func aMonthsPromptCarriesCachedWeekItemsPlusDigestLinesNeverRawMonthText() async throws {
        let month = utc.dateInterval(of: .month, for: date(2026, 6, 15))!
        let coveredWeek = try #require(ReflectSource.weeksStarting(in: month, calendar: utc).first)
        // A week inside the month that already has a cached summary: its items feed the month's
        // prompt for free.
        let cached = ReflectSummary(
            kind: .week,
            periodStart: coveredWeek.start,
            generatedAt: .now,
            items: [ReflectQueueItem(id: "generated:0", source: .generated, title: "This week", body: "A cached week observation.", prompt: "ask?")]
        )
        context.insert(cached)

        // An entry later in the month, in a week that was never individually visited: it should
        // reach the prompt only as a digest line, never as a whole fenced block of its own text.
        let uncoveredDate = utc.date(byAdding: .day, value: 20, to: month.start)!
        let longText = "A long paragraph of raw text, well past the ninety-character digest limit, that should never leave the phone whole for a month, only as a short clipped line."
        entry(longText, on: uncoveredDate, title: "Later entry")
        try context.save()

        let fake = FakeTextGenerator()
        fake.results = [.success(#"{"summary":"","prompt":""}"#)]
        _ = await ReflectSummaryStore.generateIfNeeded(
            kind: .month, interval: month, resolve: resolve(fake), voice: .default, calendar: utc, in: context
        )

        let sent = try #require(fake.requests.first).user
        #expect(sent.contains("A cached week observation."))
        #expect(sent.contains("Later entry"))
        #expect(!sent.contains(longText), "only a 90-character digest line, never the whole entry")
    }
}
