import Foundation
import SwiftData
import Testing
@testable import Mindlore

// Redo insights on every entry (owner, 2026-09-23): the whole journal through the one queue,
// oldest first, one at a time, keeping what the user decided by hand.
@MainActor
struct RedoInsightsTests {
    private func dated(_ harness: InsightsHarness, _ text: String, day: Double) throws -> Entry {
        let entry = try harness.entry(text, pending: false)
        entry.entryDate = Date(timeIntervalSince1970: day * 86_400)
        try harness.context.save()
        return entry
    }

    @Test func everyEntryRunsOldestFirstAndDraftsAndUnapprovedPagesWait() async throws {
        let harness = try InsightsHarness()
        _ = try dated(harness, "second", day: 20)
        _ = try dated(harness, "first", day: 10)
        let draft = try dated(harness, "half a thou", day: 5)
        draft.isDraft = true
        let pages = try dated(harness, "page text not yet approved", day: 6)
        pages.sourceRaw = EntrySource.photo.rawValue
        try harness.context.save()
        harness.generator.results = [.success(InsightsHarness.fullResponse), .success(InsightsHarness.fullResponse)]

        await harness.coordinator.redoAll(context: harness.context)

        #expect(harness.generator.requests.map(\.user) == ["first", "second"])
        #expect(!draft.insightsPending && draft.insights == nil)
        #expect(!pages.insightsPending && pages.insights == nil)
        #expect(harness.coordinator.redo == nil, "the count clears when the queue empties")
    }

    @Test func progressCountsAndStopTakesBackWhatHasNotStarted() async throws {
        let harness = try InsightsHarness()
        let first = try dated(harness, "first", day: 1)
        let second = try dated(harness, "second", day: 2)
        let third = try dated(harness, "third", day: 3)
        harness.generator.suspends = true

        let run = Task { await harness.coordinator.redoAll(context: harness.context) }
        await harness.generator.waitForRequest(number: 1)
        #expect(harness.coordinator.redo == .init(total: 3, done: 0))

        harness.coordinator.stopRedo(context: harness.context)
        #expect(!second.insightsPending && !third.insightsPending)
        #expect(harness.coordinator.redo != nil, "the entry in flight still finishes")

        harness.generator.answer(.success(InsightsHarness.fullResponse))
        await run.value

        #expect(harness.generator.requests.count == 1)
        #expect(first.insights?.summary == "A river walk.")
        #expect(second.insights == nil && third.insights == nil)
        #expect(harness.coordinator.redo == nil)
    }

    // Redoing a whole journal must not undo every correction in it.
    @Test func aMoodPickedByHandSurvivesButASummaryIsRewritten() async throws {
        let harness = try InsightsHarness()
        let entry = try dated(harness, "a long day", day: 1)
        let insights = EntryInsights()
        harness.context.insert(insights)
        insights.entry = entry
        insights.summary = "Old summary."
        insights.setMoods(primary: .sad, secondary: [], editedByUser: true)
        try harness.context.save()
        harness.generator.results = [.success(InsightsHarness.fullResponse)]

        await harness.coordinator.redoAll(context: harness.context)

        #expect(entry.insights?.summary == "A river walk.")
        #expect(entry.insights?.primaryMood == .sad)
        #expect(entry.insights?.moodsEditedByUser == true)
    }

    @Test func aKindPickedByHandSurvives() async throws {
        let harness = try InsightsHarness()
        let poem = try dated(harness, "the river, the river", day: 1)
        poem.kind = .creative
        poem.creativeSetByUser = true
        try harness.context.save()
        harness.generator.results = [.success(InsightsHarness.fullResponse)]

        await harness.coordinator.redoAll(context: harness.context)

        #expect(poem.kind == .creative)
    }

    // Offline, a redo waits rather than failing every entry in a second.
    @Test func offlineTheRestWaitForTheNetwork() async throws {
        let harness = try InsightsHarness()
        let first = try dated(harness, "first", day: 1)
        let second = try dated(harness, "second", day: 2)
        harness.generator.results = [.failure(AIError.offline(.notConnectedToInternet))]

        await harness.coordinator.redoAll(context: harness.context)

        #expect(harness.generator.requests.count == 1)
        #expect(first.insightsPending && second.insightsPending)
        #expect(harness.coordinator.redo == .init(total: 2, done: 0))

        harness.generator.results = [.success(InsightsHarness.fullResponse), .success(InsightsHarness.fullResponse)]
        await harness.coordinator.networkBecameAvailable(context: harness.context)

        #expect(first.insights != nil && second.insights != nil)
        #expect(harness.coordinator.redo == nil)
    }

    // The entries' own flags are the queue: a run cut short finishes after a relaunch.
    @Test func aRunCutShortFinishesAfterARelaunch() async throws {
        let harness = try InsightsHarness()
        let first = try dated(harness, "first", day: 1)
        let second = try dated(harness, "second", day: 2)
        harness.generator.results = [.failure(AIError.offline(.notConnectedToInternet))]
        await harness.coordinator.redoAll(context: harness.context)

        harness.generator.results = [.success(InsightsHarness.fullResponse), .success(InsightsHarness.fullResponse)]
        let relaunched = harness.makeCoordinator()
        await relaunched.processQueue(context: harness.context)

        #expect(first.insights != nil && second.insights != nil)
        #expect(!first.insightsPending && !second.insightsPending)
    }

    @Test func nothingEligibleStartsNothing() async throws {
        let harness = try InsightsHarness()
        let draft = try dated(harness, "half", day: 1)
        draft.isDraft = true
        try harness.context.save()

        await harness.coordinator.redoAll(context: harness.context)

        #expect(harness.generator.requests.isEmpty)
        #expect(harness.coordinator.redo == nil)
    }

    @Test func theLogCarriesCountsOnly() async throws {
        let file = URL.temporaryDirectory.appending(path: "redo-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        let harness = try InsightsHarness()
        harness.diagnostics = DiagnosticsLog(fileURL: file)
        let coordinator = harness.makeCoordinator()
        let sentinel = "SENTINEL-redo-7f3a"
        _ = try dated(harness, sentinel, day: 1)
        _ = try dated(harness, sentinel + " again", day: 2)
        harness.generator.suspends = true

        let run = Task { await coordinator.redoAll(context: harness.context) }
        await harness.generator.waitForRequest(number: 1)
        coordinator.stopRedo(context: harness.context)
        harness.generator.answer(.success(InsightsHarness.fullResponse))
        await run.value

        let written = try String(contentsOf: file, encoding: .utf8)
        #expect(written.contains("insights.redoAll"))
        #expect(written.contains("insights.redoStopped"))
        #expect(!written.contains(sentinel))
    }
}
