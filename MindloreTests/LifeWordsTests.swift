import Foundation
import SwiftData
import Testing
@testable import Mindlore

struct LifePromptsTests {
    private let run = LifePrompts.Entry(id: UUID(), date: .now, title: "Morning", text: "Ran by the river before work. My knee held up the whole way, which I did not expect at all.")
    private let call = LifePrompts.Entry(id: UUID(), date: .now, title: "Call", text: "Called Dad about the move. He went quiet and I felt like I was letting him down again.")

    @Test func aQuoteSurvivesOnlyIfItsWordsAreInTheEntryItsHandleNames() {
        let handles = ["E1": run, "E2": call]
        let answer = """
        {"paragraph": "Health has been about getting back to running.",
         "quotes": [
           {"handle": "E1", "text": "my knee held up the whole way"},
           {"handle": "E2", "text": "my knee held up the whole way"},
           {"handle": "E2", "text": "I felt like I disappointed him"},
           {"handle": "E9", "text": "He went quiet and I felt"},
           {"handle": "e2", "text": "\\"He went quiet and I felt like I was letting him down again.\\""}
         ]}
        """
        let words = LifePrompts.parseArea(answer, handles: handles, onDevice: false)
        #expect(words?.paragraph == "Health has been about getting back to running.")
        #expect(words?.quotes.map(\.entryID) == [run.id, call.id])
        #expect(words?.quotes.first?.text == "My knee held up the whole way", "the entry's own casing, not the model's")
        #expect(words?.quotes.last?.text == "He went quiet and I felt like I was letting him down again")
    }

    @Test func aTooShortQuoteIsDropped() {
        #expect(LifePrompts.verbatim("the river", in: run.text) == nil)
    }

    @Test func onDeviceProseIsTheParagraphAlone() {
        let words = LifePrompts.parseArea("Work has been busy and tense.", handles: [:], onDevice: true)
        #expect(words == LifePrompts.AreaWords(paragraph: "Work has been busy and tense.", quotes: []))
        #expect(LifePrompts.parseArea("not json", handles: [:], onDevice: false) == nil)
    }

    @Test func theAreaRequestFencesEntriesAndHandlesEachOnce() {
        let planned = LifePrompts.areaRequest(area: "Health", windowPhrase: "these three months", entries: [run, call], model: "m", onDevice: false)
        #expect(planned.handles.count == 2)
        #expect(planned.request.user.components(separatedBy: AskContextBuilder.openDelimiter).count == 3)
        #expect(planned.request.system.contains("never diagnose"))
        #expect(planned.request.system.contains("No advice"))
    }

    @Test func thePortraitMapsHandlesToEntriesAndCapsEachPart() throws {
        let a = UUID(), b = UUID()
        let answer = """
        {"lifts": [{"text": "Saturday runs with Maya.", "handles": ["D1", "D2", "D1", "D40"]}, {"text": "Two", "handles": []}, {"text": "Three", "handles": []}],
         "weighs": [{"text": "Sunday nights before a deadline.", "handles": ["d2"]}],
         "returns": [], "selfTalk": [], "values": [], "concern": false}
        """
        let portrait = try #require(LifePrompts.parsePortrait(answer, handles: ["D1": a, "D2": b]))
        #expect(portrait.lines.filter { $0.section == .lifts }.count == 2)
        #expect(portrait.lines.first?.entryIDs == [a, b], "unknown handles dropped, repeats once")
        #expect(portrait.lines.last?.entryIDs == [b])
        #expect(!portrait.concern)
    }

    @Test func aConcernIsKeptEvenWithNoLines() {
        let portrait = LifePrompts.parsePortrait(#"{"lifts": [], "concern": true}"#, handles: [:])
        #expect(portrait?.concern == true)
        #expect(LifePrompts.parsePortrait(#"{"lifts": []}"#, handles: [:]) == nil)
    }

    @Test func thePortraitRequestCarriesFeedbackAndNoLabels() {
        let planned = LifePrompts.portraitRequest(
            facts: "12 entries.",
            monthSummaries: ["March 2026: A quiet month."],
            entries: [run, call],
            feedback: [LifePrompts.Feedback(line: "You avoid your dad.", right: false, note: "It's the move, not him")],
            model: "m"
        )
        #expect(planned.handles.count == 2)
        #expect(planned.request.user.contains("not quite right"))
        #expect(planned.request.user.contains("It's the move, not him"))
        #expect(planned.request.system.contains("never labels or diagnoses"))
        #expect(planned.request.schemaName == "life_portrait")
    }
}

@MainActor
struct LifeWordsTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        container = try ModelContainerFactory.make(.inMemory)
    }

    private func provider(_ fake: FakeTextGenerator, kind: AskProviderKind = .openAI) -> () -> Result<AskProvider, AIJobFailure> {
        { .success(AskProvider(generator: fake, model: "m", label: "test", kind: kind)) }
    }

    private func entries(_ count: Int) throws -> [UUID] {
        (0..<count).map { index in
            let entry = Entry(text: "Work was loud today, number \(index), and I stayed late to finish the deck.")
            entry.title = "Day \(index)"
            let insights = EntryInsights()
            insights.areasRaw = ["work"]
            entry.insights = insights
            context.insert(entry)
            return entry.id
        }
    }

    @Test func anAreasWordsAreWrittenOnceAndReadBackUntilTheyGoStale() async throws {
        let ids = try entries(4)
        try context.save()
        let fake = FakeTextGenerator()
        fake.results = [.success(#"{"paragraph": "Work has run long.", "quotes": [{"handle": "E1", "text": "I stayed late to finish the deck"}]}"#)]

        let first = await LifeWords.writeAreaIfNeeded(.work, window: .quarter, name: "Work", entryIDs: ids, resolve: provider(fake), in: context)
        #expect(first?.paragraph == "Work has run long.")
        #expect(first?.quotes.count == 1)
        let again = await LifeWords.writeAreaIfNeeded(.work, window: .quarter, name: "Work", entryIDs: ids, resolve: provider(fake), in: context)
        #expect(again == first)
        #expect(fake.requests.count == 1, "the same entries never ask twice")
        #expect(LifeWords.areaWords(.work, .quarter, in: context)?.paragraph == "Work has run long.")
    }

    @Test func aChangedAreaWaitsAWeekBeforeItIsRewritten() {
        let now = Date.now
        #expect(LifeWords.areaIsCurrent(generatedAt: now.addingTimeInterval(-86_400), fingerprint: "old", current: "new", now: now))
        #expect(!LifeWords.areaIsCurrent(generatedAt: now.addingTimeInterval(-8 * 86_400), fingerprint: "old", current: "new", now: now))
        #expect(LifeWords.areaIsCurrent(generatedAt: now.addingTimeInterval(-30 * 86_400), fingerprint: "same", current: "same", now: now))
    }

    @Test func theOnDeviceModelNeverWritesAnAreasWords() async throws {
        let ids = try entries(4)
        try context.save()
        let fake = FakeTextGenerator()
        let words = await LifeWords.writeAreaIfNeeded(.work, window: .quarter, name: "Work", entryIDs: ids, resolve: provider(fake, kind: .onDevice), in: context)
        #expect(words == nil)
        #expect(fake.requests.isEmpty)
    }

    @Test func draftsAndTooFewEntriesAreNeverSent() async throws {
        let ids = try entries(2)
        try context.save()
        let fake = FakeTextGenerator()
        let words = await LifeWords.writeAreaIfNeeded(.work, window: .quarter, name: "Work", entryIDs: ids, resolve: provider(fake), in: context)
        #expect(words == nil)
        #expect(fake.requests.isEmpty)
    }

    @Test func thePortraitNeedsOpenAIAndKeepsOnePerMonth() async throws {
        _ = try entries(5)
        try context.save()
        let reading = LifeSignals.Reading(window: .year, interval: DateInterval(start: .distantPast, end: .now), entries: 5, baseline: 0, areas: [], headline: nil, recurring: [], quiet: [], changes: [], followThrough: [], contrast: nil, openThreads: 0)
        let onDevice = FakeTextGenerator()
        let refused = await LifeWords.writePortrait(reading: reading, priorities: [], name: \.defaultName, resolve: provider(onDevice, kind: .onDevice), in: context)
        #expect(refused == .needsCloud)
        #expect(onDevice.requests.isEmpty)

        let fake = FakeTextGenerator()
        fake.results = [
            .success(#"{"lifts": [{"text": "Finishing things.", "handles": ["D1"]}], "weighs": [], "returns": [], "selfTalk": [], "values": [], "concern": false}"#),
            .success(#"{"lifts": [{"text": "Finishing things, again.", "handles": []}], "weighs": [], "returns": [], "selfTalk": [], "values": [], "concern": false}"#),
        ]
        _ = await LifeWords.writePortrait(reading: reading, priorities: [], name: \.defaultName, resolve: provider(fake), in: context)
        _ = await LifeWords.writePortrait(reading: reading, priorities: [], name: \.defaultName, resolve: provider(fake), in: context)
        let portraits = LifeWords.portraits(in: context)
        #expect(portraits.count == 1)
        #expect(portraits.first?.lines.first?.text == "Finishing things, again.")
        #expect(LifeWords.portraitForThisMonth(in: context) != nil)
    }

    @Test func aVerdictReplacesTheLastOneOnTheSameLineAndReachesTheNextPortrait() {
        LifeWords.give(true, on: "You love Saturdays.", in: context)
        LifeWords.give(false, on: "You love Saturdays.", note: "Only some", in: context)
        LifeWords.give(true, on: "Work weighs on you.", in: context)
        #expect(LifeWords.verdict(on: "You love Saturdays.", in: context) == false)
        let all = LifeWords.feedback(in: context)
        #expect(all.count == 2)
        #expect(all.first { $0.line == "You love Saturdays." }?.note == "Only some")
        #expect(LifeWords.rows(LifeWords.feedbackKind, in: context).count == 1, "one row holds them")
    }
}
