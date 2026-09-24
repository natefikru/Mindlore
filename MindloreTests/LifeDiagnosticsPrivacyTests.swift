import Foundation
import SwiftData
import Testing
@testable import Mindlore

// Every Life event, driven through the real component with the sentinel as the entry text, a tag,
// an area's own name, a model's answer, and the author's note. Counts and literals only may reach
// the log.
@MainActor
struct LifeDiagnosticsPrivacyTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let sentinel = DiagnosticsPrivacyTests.sentinel

    init() throws {
        container = try ModelContainerFactory.make(.inMemory)
    }

    @Test func lifeNeverLogsEntryTextTagsNamesAnswersOrNotes() async throws {
        let file = DiagnosticsFile()
        let log = DiagnosticsLog(fileURL: file.url)

        var ids: [UUID] = []
        for index in 0..<4 {
            let entry = Entry(text: "\(sentinel) wrote this, day \(index), and it was long enough to quote from.")
            entry.title = sentinel
            let insights = EntryInsights()
            insights.areasRaw = ["work"]
            insights.tags = [sentinel]
            entry.insights = insights
            context.insert(entry)
            ids.append(entry.id)
        }
        try context.save()

        let facts = (0..<25).map { LifeSignals.EntryFact(date: Date.now.addingTimeInterval(-Double($0) * 3 * 86_400 - 3_600), areas: [.work], valence: 1, tags: [sentinel]) }
        let reading = try #require(LifeSignals.reading(entries: facts, threads: [], window: .year, now: .now))
        LifeDiagnostics.rendered(reading: reading, progress: LifeSignals.progress(facts), started: .now, diagnostics: log)
        LifeDiagnostics.areaOpened(.work, window: .year, diagnostics: log)

        let fake = FakeTextGenerator()
        fake.results = [
            .success(#"{"paragraph": "\#(sentinel)", "quotes": [{"handle": "E1", "text": "wrote this, day 3, and it was long"}]}"#),
            .success(#"{"lifts": [{"text": "\#(sentinel)", "handles": ["D1"]}], "weighs": [], "returns": [], "selfTalk": [], "values": [], "concern": false}"#),
        ]
        let provider: () -> Result<AskProvider, AIJobFailure> = { .success(AskProvider(generator: fake, model: "m", label: "t", kind: .openAI)) }
        _ = await LifeWords.writeAreaIfNeeded(.work, window: .year, name: sentinel, entryIDs: ids, resolve: provider, in: context, diagnostics: log)
        _ = await LifeWords.writePortrait(reading: reading, priorities: [], name: { _ in sentinel }, resolve: provider, in: context, diagnostics: log)
        LifeWords.give(false, on: sentinel, note: sentinel, in: context, diagnostics: log)
        let suggestion = LifeSignals.Suggestion(subject: .tag(sentinel), lighterWith: 4, lighterWeeks: 5, heavierWith: 0, heavierWeeks: 4)
        LifeExperiments.accept(suggestion, threadText: sentinel, in: context, diagnostics: log)
        LifeExperiments.decline(.tag(sentinel), in: context, diagnostics: log)

        let contents = file.contents()
        for event in ["life.rendered", "life.areaOpened", "life.areaWords", "life.portrait", "life.feedback", "life.experiment"] {
            #expect(contents.contains(event), "\(event) was written")
        }
        #expect(!contents.contains(sentinel))
        #expect(fake.requests.count == 2, "both requests really went out")
    }
}
