import Foundation
import SwiftData
import Testing
@testable import Mindlore

struct MoodTests {
    // Renaming or removing a stored raw value orphans old insights. Add new moods at the end of this list.
    @Test func moodRawValuesArePinned() {
        #expect(Mood.allCases.map(\.rawValue) == [
            "joyful", "excited", "energized", "proud", "confident", "inspired",
            "content", "calm", "grateful", "relieved", "hopeful",
            "loved", "connected", "supported", "compassionate",
            "reflective", "curious", "nostalgic", "uncertain", "conflicted",
            "anxious", "stressed", "overwhelmed", "restless", "afraid", "insecure",
            "frustrated", "irritated", "angry", "resentful", "jealous",
            "sad", "lonely", "disappointed", "hurt", "guilty", "ashamed", "hopeless",
            "tired", "numb", "bored", "unmotivated", "burnedOut",
        ])
        #expect(MentionKind.allCases.map(\.rawValue) == ["person", "place", "organization", "project", "event", "other"])
    }

    @Test func categoriesCarryValenceAndEnergy() {
        #expect(Mood.allCases.count == 43)
        #expect(MoodCategory.allCases.count == 8)
        #expect(Mood.anxious.category == .anxious && MoodCategory.anxious.valence == -1 && MoodCategory.anxious.energy == .high)
        #expect(Mood.grateful.category == .calm && MoodCategory.calm.valence == 1 && MoodCategory.calm.energy == .low)
        #expect(Mood.reflective.category.valence == 0)
        #expect(Mood.burnedOut.name == "burned out")
        #expect(Mood.allCases.allSatisfy { !$0.meaning.isEmpty })
    }
}

struct InsightsPromptBuilderTests {
    private func schemaProperties(_ plan: InsightsRequestPlan) throws -> [String: [String: Any]] {
        let schema = try #require(plan.request.schema)
        let json = try #require(JSONSerialization.jsonObject(with: try schema.jsonData()) as? [String: Any])
        return try #require(json["properties"] as? [String: [String: Any]])
    }

    @Test func allSectionsForAVoiceEntry() throws {
        let plan = InsightsPromptBuilder.plan(text: "I walked to the river.", source: .voice, sections: InsightSections(), existingTags: ["work", "family"], model: "gpt-test")
        let properties = try schemaProperties(plan)

        #expect(Set(properties.keys) == ["summary", "primaryMood", "secondaryMoods", "themes", "tags", "mentions", "openThreads", "cleanedText"])
        #expect((properties["primaryMood"]?["enum"] as? [Any])?.count == Mood.allCases.count + 1)
        #expect(plan.asksForCleanedText && !plan.asksForWrittenDate)
        #expect(plan.request.schemaName == "journal_insights")
        #expect(plan.request.user == "I walked to the river.")
        #expect(plan.request.system.contains("do not give advice"))
        #expect(plan.request.system.contains("burnedOut (worn down over a long stretch)"))
        #expect(plan.request.system.contains("work, family"))
    }

    @Test func typedEntriesAskForTheWrittenDateAndNeverCleanup() throws {
        let typed = try schemaProperties(InsightsPromptBuilder.plan(text: "x", source: .typed, sections: InsightSections(), existingTags: [], model: "m"))
        #expect(typed["writtenDate"] != nil)
        #expect(typed["cleanedText"] == nil)

        let photo = try schemaProperties(InsightsPromptBuilder.plan(text: "x", source: .photo, sections: InsightSections(), existingTags: [], model: "m"))
        #expect(photo["writtenDate"] == nil)
        #expect(photo["cleanedText"] == nil)

        var noDates = InsightSections()
        noDates.suggestEntryDates = false
        #expect(try schemaProperties(InsightsPromptBuilder.plan(text: "x", source: .typed, sections: noDates, existingTags: [], model: "m"))["writtenDate"] == nil)
    }

    @Test func disabledSectionsAreLeftOut() throws {
        var sections = InsightSections()
        sections.moods = false
        sections.tags = false
        sections.cleanedText = false
        let plan = InsightsPromptBuilder.plan(text: "x", source: .voice, sections: sections, existingTags: ["work"], model: "m")
        let properties = try schemaProperties(plan)

        #expect(Set(properties.keys) == ["summary", "themes", "mentions", "openThreads"])
        #expect(!plan.request.system.contains("Moods come only"))
        #expect(!plan.request.system.contains("work"))
    }

    @Test func longVoiceEntriesSkipCleanupWithAReason() throws {
        let long = String(repeating: "word ", count: 3_000)
        let plan = InsightsPromptBuilder.plan(text: long, source: .voice, sections: InsightSections(), existingTags: [], model: "m")
        #expect(try schemaProperties(plan)["cleanedText"] == nil)
        #expect(plan.cleanedTextSkippedReason == "tooLong")
    }

    @Test func existingTagsAreCappedAtFifty() {
        let tags = (1...80).map { "tag\($0)" }
        let plan = InsightsPromptBuilder.plan(text: "x", source: .typed, sections: InsightSections(), existingTags: tags, model: "m")
        #expect(plan.request.system.contains("tag50"))
        #expect(!plan.request.system.contains("tag51"))
    }

    @Test func customKeysAreStableAcrossReorderAndDelete() throws {
        let first = CustomInsightPrompt(id: UUID(), name: "Gratitude", instructions: "What am I grateful for?", enabled: true)
        let second = CustomInsightPrompt(id: UUID(), name: "Wins", instructions: "What went well?", enabled: true)
        let off = CustomInsightPrompt(id: UUID(), name: "Off", instructions: "nope", enabled: false)
        var sections = InsightSections()
        sections.customPrompts = [first, second, off]
        let before = InsightsPromptBuilder.plan(text: "x", source: .typed, sections: sections, existingTags: [], model: "m")
        sections.customPrompts = [second]
        let after = InsightsPromptBuilder.plan(text: "x", source: .typed, sections: sections, existingTags: [], model: "m")

        let secondKey = try #require(before.customKeys.first { $0.value.id == second.id }?.key)
        #expect(after.customKeys[secondKey]?.id == second.id)
        #expect(before.customKeys.count == 2)
        #expect(before.customKeyOrder.map { before.customKeys[$0]?.name } == ["Gratitude", "Wins"])
        #expect(try schemaProperties(before)[secondKey]?["description"] as? String == "Wins: What went well? Null if the entry gives nothing to say.")
    }

    @Test func parsingNormalizesAndDropsUnknownValues() throws {
        let prompt = CustomInsightPrompt(id: UUID(), name: "Gratitude", instructions: "?", enabled: true)
        var sections = InsightSections()
        sections.customPrompts = [prompt]
        let plan = InsightsPromptBuilder.plan(text: "x", source: .voice, sections: sections, existingTags: [], model: "m")
        let key = try #require(plan.customKeyOrder.first)
        let response = """
        ```json
        {"summary":"  A walk.  ","primaryMood":"calm","secondaryMoods":["calm","grateful","ecstatic","hopeful","tired"],
         "themes":["river","River","walking","sleep","work","extra"],"tags":["Nature","nature","  WALKS "],
         "mentions":[{"name":"Sarah","kind":"person"},{"name":"sarah","kind":"person"},{"name":"Mars","kind":"planet"},{"name":"","kind":"place"}],
         "openThreads":[],"cleanedText":"I walked.","\(key)":"The light","writtenDate":"2025-03-03"}
        ```
        """
        let result = try InsightsPromptBuilder.parse(response, plan: plan)

        #expect(result.summary == "A walk.")
        #expect(result.primaryMood == .calm)
        #expect(result.secondaryMoods == [.grateful, .hopeful])
        #expect(result.themes == ["river", "walking", "sleep", "work"])
        #expect(result.tags == ["nature", "walks"])
        #expect(result.mentions == [Mention(name: "Sarah", kindRaw: "person")])
        #expect(result.openThreads.isEmpty)
        #expect(result.cleanedText == "I walked.")
        // Voice entries don't ask for a written date, so one in the response is ignored.
        #expect(result.writtenDate == nil)
        #expect(result.custom == [CustomInsightResult(promptID: prompt.id, name: "Gratitude", content: "The light")])
    }

    @Test func nullsLeaveFieldsEmptyAndBadJSONThrows() throws {
        let plan = InsightsPromptBuilder.plan(text: "x", source: .typed, sections: InsightSections(), existingTags: [], model: "m")
        let result = try InsightsPromptBuilder.parse(#"{"summary":null,"primaryMood":null,"secondaryMoods":[],"themes":[],"tags":[],"mentions":[],"openThreads":[],"writtenDate":null}"#, plan: plan)
        #expect(result == InsightsResult())
        #expect(throws: AIError.invalidResponse) { try InsightsPromptBuilder.parse("no json", plan: plan) }
    }
}

@MainActor
final class InsightsHarness {
    let container: ModelContainer
    let presence = EditorPresence()
    let generator = FakeTextGenerator()
    var sections = InsightSections()
    var autoApply = false
    var unavailable: AIJobFailure?
    private(set) var coordinator: InsightsCoordinator!

    var context: ModelContext { container.mainContext }

    init() throws {
        container = try ModelContainerFactory.make(.inMemory)
        coordinator = makeCoordinator()
    }

    func makeCoordinator() -> InsightsCoordinator {
        InsightsCoordinator(
            resolve: { [unowned self] in
                if let unavailable = self.unavailable { return .failure(unavailable) }
                return .success(.init(generator: self.generator, model: "insights-model", label: "openai:insights-model"))
            },
            sections: { [unowned self] in self.sections },
            autoApplyCleanedText: { [unowned self] in self.autoApply },
            presence: presence,
            diagnostics: .disabled,
            calendar: { var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!; return calendar }()
        )
    }

    @discardableResult
    func entry(_ text: String, source: EntrySource = .typed, pending: Bool = true) throws -> Entry {
        let entry = Entry(createdAt: Date(timeIntervalSince1970: 5_000), source: source, text: text)
        entry.insightsPending = pending
        context.insert(entry)
        try context.save()
        return entry
    }

    static let fullResponse = #"{"summary":"A river walk.","primaryMood":"calm","secondaryMoods":["grateful"],"themes":["walking"],"tags":["nature"],"mentions":[{"name":"Sarah","kind":"person"}],"openThreads":["Call Sarah"],"cleanedText":"I walked to the river, and it was calm.","writtenDate":"2025-03-03"}"#
}

@MainActor
struct InsightsCoordinatorTests {
    @Test func writesInsightsForAPendingEntryWithoutTouchingItsText() async throws {
        let harness = try InsightsHarness()
        let entry = try harness.entry("i walked to the river and it was calm")
        let updatedAt = entry.updatedAt
        harness.generator.results = [.success(InsightsHarness.fullResponse)]

        await harness.coordinator.processQueue(context: harness.context)

        let insights = try #require(entry.insights)
        #expect(insights.summary == "A river walk.")
        #expect(insights.primaryMood == .calm && insights.secondaryMoods == [.grateful])
        #expect(insights.themes == ["walking"] && insights.tags == ["nature"])
        #expect(insights.mentions == [Mention(name: "Sarah", kindRaw: "person")])
        #expect(insights.openThreads == ["Call Sarah"])
        #expect(insights.modelUsed == "openai:insights-model")
        #expect(insights.isCurrent(for: entry))
        #expect(entry.text == "i walked to the river and it was calm")
        #expect(!entry.insightsPending && entry.insightsAttempts == 0)
        #expect(entry.updatedAt == updatedAt)
        #expect(harness.generator.requests.first?.model == "insights-model")
    }

    @Test func typedEntriesGetADateSuggestionVoiceEntriesDont() async throws {
        let harness = try InsightsHarness()
        let typed = try harness.entry("March 3, 2025. Dear diary.")
        harness.generator.results = [.success(InsightsHarness.fullResponse)]
        await harness.coordinator.processQueue(context: harness.context)
        #expect(typed.suggestedEntryDate != nil)
        #expect(typed.insights?.cleanedText == nil)

        let voice = try harness.entry("march third", source: .voice)
        harness.generator.results = [.success(InsightsHarness.fullResponse)]
        await harness.coordinator.processQueue(context: harness.context)
        #expect(voice.suggestedEntryDate == nil)
        #expect(voice.insights?.cleanedText == "I walked to the river, and it was calm.")
    }

    @Test func textChangedDuringTheRequestStoresStaleInsightsWithoutCleanupOrDate() async throws {
        let harness = try InsightsHarness()
        harness.autoApply = true
        let entry = try harness.entry("first version", source: .voice)
        harness.generator.suspends = true

        let task = Task { await harness.coordinator.processQueue(context: harness.context) }
        await harness.generator.waitForRequest(number: 1)
        entry.text = "second version"
        entry.userDidEditText()
        harness.generator.answer(.success(InsightsHarness.fullResponse))
        await task.value

        let insights = try #require(entry.insights)
        #expect(!insights.isCurrent(for: entry))
        #expect(entry.text == "second version")
        #expect(entry.originalText == nil)
        #expect(entry.suggestedEntryDate == nil)
    }

    @Test func deletedEntryDuringTheRequestIsIgnored() async throws {
        let harness = try InsightsHarness()
        let entry = try harness.entry("text")
        harness.generator.suspends = true

        let task = Task { await harness.coordinator.processQueue(context: harness.context) }
        await harness.generator.waitForRequest(number: 1)
        Entry.delete(entry, in: harness.context)
        try harness.context.save()
        harness.generator.answer(.success(InsightsHarness.fullResponse))
        await task.value

        #expect(try harness.context.fetchCount(FetchDescriptor<EntryInsights>()) == 0)
    }

    @Test func restartDuringTheRequestDropsTheResult() async throws {
        let harness = try InsightsHarness()
        let entry = try harness.entry("text")
        harness.generator.suspends = true

        let task = Task { await harness.coordinator.processQueue(context: harness.context) }
        await harness.generator.waitForRequest(number: 1)
        entry.contentRevision += 1
        harness.generator.answer(.success(InsightsHarness.fullResponse))
        await task.value

        #expect(entry.insights == nil)
    }

    @Test func waitsWhileOpen() async throws {
        let harness = try InsightsHarness()
        let entry = try harness.entry("text")
        harness.presence.open(entry.id)
        await harness.coordinator.processQueue(context: harness.context)
        #expect(harness.generator.requests.isEmpty)
    }

    @Test func retryableFailuresRetryOncePerLaunchUpToTwo() async throws {
        let harness = try InsightsHarness()
        let entry = try harness.entry("text")
        harness.generator.results = Array(repeating: .failure(AIError.serverError(status: 500)), count: 5)

        await harness.coordinator.processQueue(context: harness.context)
        await harness.coordinator.processQueue(context: harness.context)
        #expect(harness.generator.requests.count == 1)

        for _ in 0..<3 {
            await harness.makeCoordinator().processQueue(context: harness.context)
        }
        #expect(harness.generator.requests.count == 2)
        #expect(!entry.insightsPending)
    }

    @Test func permanentFailuresAndBadResponsesWaitForRunAI() async throws {
        let harness = try InsightsHarness()
        let entry = try harness.entry("text")
        harness.generator.results = [.success("not json")]

        await harness.coordinator.processQueue(context: harness.context)
        await harness.makeCoordinator().processQueue(context: harness.context)

        #expect(harness.generator.requests.count == 1)
        #expect(entry.insightsFailureRaw == "ai.invalidResponse")
        #expect(!entry.insightsPending)
    }

    @Test func runAICreatesRetriesAndReplacesInsights() async throws {
        let harness = try InsightsHarness()
        let never = try harness.entry("old entry", pending: false)
        harness.generator.results = [.success(#"{"summary":"First"}"#)]
        await harness.coordinator.runAI(for: never, context: harness.context)
        #expect(never.insights?.summary == "First")

        harness.generator.results = [.failure(AIError.invalidKey)]
        await harness.coordinator.runAI(for: never, context: harness.context)
        #expect(never.insightsFailureRaw == "ai.invalidKey")
        #expect(never.insights?.summary == "First")

        harness.generator.results = [.success(#"{"summary":"Second"}"#)]
        await harness.coordinator.runAI(for: never, context: harness.context)
        #expect(never.insights?.summary == "Second")
        #expect(never.insightsFailureRaw == nil)
        #expect(try harness.context.fetchCount(FetchDescriptor<EntryInsights>()) == 1)
    }

    @Test func runAIIsRefusedWhileRunningOrBeforeTheTextIsFinal() async throws {
        let harness = try InsightsHarness()
        let unapproved = try harness.entry("page text", source: .photo, pending: false)
        unapproved.pagesConfirmed = true
        unapproved.textReviewPending = true
        await harness.coordinator.runAI(for: unapproved, context: harness.context)

        let transcribing = try harness.entry("", source: .voice, pending: false)
        transcribing.awaitingText = true
        await harness.coordinator.runAI(for: transcribing, context: harness.context)
        #expect(harness.generator.requests.isEmpty)

        let entry = try harness.entry("text", pending: false)
        harness.generator.suspends = true
        let task = Task { await harness.coordinator.runAI(for: entry, context: harness.context) }
        await harness.generator.waitForRequest(number: 1)
        #expect(harness.coordinator.isRunning(entry))
        await harness.coordinator.runAI(for: entry, context: harness.context)
        harness.generator.answer(.success(#"{"summary":"once"}"#))
        await task.value
        #expect(harness.generator.requests.count == 1)
    }

    @Test func autoApplyCleanupWhenEnabledCurrentAndClosed() async throws {
        let harness = try InsightsHarness()
        harness.autoApply = true
        let entry = try harness.entry("i walked to the river and it was calm", source: .voice)
        harness.generator.results = [.success(InsightsHarness.fullResponse)]

        await harness.coordinator.processQueue(context: harness.context)

        #expect(entry.text == "I walked to the river, and it was calm.")
        #expect(entry.originalText == "i walked to the river and it was calm")
        #expect(entry.insights?.isCurrent(for: entry) == true)
    }

    @Test func existingTagsAreSentWithTheRequest() async throws {
        let harness = try InsightsHarness()
        let tagged = try harness.entry("one", pending: false)
        let insights = EntryInsights()
        harness.context.insert(insights)
        insights.entry = tagged
        insights.tags = ["running", "family"]
        try harness.entry("two")
        harness.generator.results = [.success(#"{"summary":"x"}"#)]

        await harness.coordinator.processQueue(context: harness.context)

        #expect(harness.generator.requests.first?.system.contains("family, running") == true)
    }
}

@MainActor
struct CleanupTests {
    private func voiceEntry(with cleaned: String, in context: ModelContext) -> Entry {
        let entry = Entry(source: .voice, text: "raw words")
        context.insert(entry)
        let insights = EntryInsights(sourceTextHash: TextHash.of("raw words"))
        context.insert(insights)
        insights.entry = entry
        insights.cleanedText = cleaned
        return entry
    }

    @Test func applyAndRevertKeepTheFirstOriginal() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let entry = voiceEntry(with: "Raw words.", in: container.mainContext)

        #expect(entry.applyCleanedText("Raw words."))
        #expect(entry.text == "Raw words." && entry.originalText == "raw words")
        #expect(!entry.textChangedSinceCleanup)

        // A second cleanup of the cleaned text keeps the very first original.
        entry.insights?.sourceTextHash = TextHash.of("Raw words.")
        #expect(entry.applyCleanedText("Raw, words."))
        #expect(entry.originalText == "raw words")

        entry.text += " more"
        #expect(entry.textChangedSinceCleanup)
        #expect(entry.revertToOriginalText())
        #expect(entry.text == "raw words" && entry.originalText == nil)
        #expect(!entry.revertToOriginalText())
    }

    @Test func refusedOnChangedTextAndNonVoiceEntries() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let changed = voiceEntry(with: "Raw words.", in: container.mainContext)
        changed.text = "raw words, edited"
        #expect(!changed.applyCleanedText("Raw words."))

        let typed = voiceEntry(with: "Raw words.", in: container.mainContext)
        typed.source = .typed
        #expect(!typed.applyCleanedText("Raw words."))
        typed.source = .photo
        #expect(!typed.applyCleanedText("Raw words."))
        #expect(typed.originalText == nil)
    }
}

@MainActor
struct AutomaticInsightsTriggerTests {
    private func trigger(insights: Bool, started: Date = Date(timeIntervalSince1970: 1_000)) -> AIPassTrigger {
        let settings = SettingsStore(store: FakeKeyValueStore(), diagnostics: .disabled, now: { started })
        settings.recordAutomationStartIfNeeded()
        return AIPassTrigger(settings: settings, presence: EditorPresence(), titleUsable: { false }, insightsUsable: { insights }, diagnostics: .disabled)
    }

    @Test func passFlagsInsightsWhenUsableAndOnlyOnce() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let entry = Entry(createdAt: Date(timeIntervalSince1970: 5_000), text: "text")
        container.mainContext.insert(entry)
        let pass = trigger(insights: true)

        #expect(pass.fire(for: entry, at: .editorClosed))
        #expect(entry.insightsPending)
        entry.insightsPending = false
        entry.text += " edited"
        #expect(!pass.fire(for: entry, at: .editorClosed))
        #expect(!entry.insightsPending)
    }

    @Test func manualModeOrNoKeyNeverFlags() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let entry = Entry(createdAt: Date(timeIntervalSince1970: 5_000), text: "text")
        container.mainContext.insert(entry)
        #expect(trigger(insights: false).fire(for: entry, at: .editorClosed))
        #expect(!entry.insightsPending)
    }

    @Test func existingEntriesAreNeverFlaggedWhenAIIsTurnedOn() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let old = Entry(createdAt: Date(timeIntervalSince1970: 10), text: "from before")
        container.mainContext.insert(old)
        let pass = trigger(insights: true)
        #expect(pass.sweep(context: container.mainContext) == 0)
        #expect(!old.insightsPending)
    }

    @Test func automaticUsabilityFollowsSettings() throws {
        let settings = SettingsStore(store: FakeKeyValueStore(), diagnostics: .disabled)
        let accounts = ProviderAccountStore(settings: settings, secrets: FakeSecretStore(), http: FakeHTTPClient(), diagnostics: .disabled)
        #expect(!AIServices.automaticInsightsUsable(settings: settings, accounts: accounts))
        try accounts.saveOpenAIKey("sk")
        settings.aiEnabled = true
        #expect(AIServices.automaticInsightsUsable(settings: settings, accounts: accounts))
        settings.insightsTrigger = .manual
        #expect(!AIServices.automaticInsightsUsable(settings: settings, accounts: accounts))
        settings.insightsTrigger = .automatic
        for keyPath in [\SettingsStore.insightSummary, \.insightMoods, \.insightThemes, \.insightTags, \.insightMentions, \.insightOpenThreads, \.insightCleanedText] {
            settings[keyPath: keyPath] = false
        }
        #expect(!AIServices.automaticInsightsUsable(settings: settings, accounts: accounts))
    }
}
