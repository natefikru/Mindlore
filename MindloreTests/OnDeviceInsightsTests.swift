import Foundation
import FoundationModels
import Testing
@testable import Mindlore

// Insights on Apple's model: a smaller prompt, the same schema held by guided generation, and an
// engine setting that defaults the way titles do (owner, 2026-09-22).
struct OnDeviceInsightsTests {
    private func properties(_ plan: InsightsRequestPlan) throws -> [String: [String: Any]] {
        let schema = try #require(plan.request.schema)
        let json = try #require(JSONSerialization.jsonObject(with: try schema.jsonData()) as? [String: Any])
        return try #require(json["properties"] as? [String: [String: Any]])
    }

    private func sections() -> InsightSections {
        var sections = InsightSections()
        sections.customPrompts = [CustomInsightPrompt(id: UUID(), name: "Gratitude", instructions: "What was I grateful for?", enabled: true)]
        return sections
    }

    @Test func theOnDeviceBudgetFitsTheSmallModel() throws {
        let long = String(repeating: "walked to the river and back again. ", count: 400)
        let vocabulary = InsightsPromptBuilder.JournalVocabulary(
            tags: (1...40).map { "tag\($0)" },
            looseEnds: (1...10).map { .init(id: UUID(), text: "thread \($0)", own: false) }
        )

        let plan = InsightsPromptBuilder.plan(text: long, source: .voice, sections: sections(), vocabulary: vocabulary, model: "", budget: .onDevice)
        let fields = try properties(plan)

        #expect(plan.request.user.count == InsightsPromptBuilder.Budget.onDevice.inputCharacters)
        #expect(fields["cleanedText"] == nil, "a whole rewritten entry doesn't fit")
        #expect(plan.cleanedTextSkippedReason == "onDevice")
        #expect(plan.customKeys.isEmpty, "custom prompts are OpenAI's")
        #expect(plan.vocabularySent.tags.count == 15)
        #expect(plan.vocabularySent.looseEnds.count == 5)
        #expect(plan.request.maxOutputTokens == 700)
        #expect(!plan.request.system.contains("(\(Mood.calm.meaning))"), "moods go without their glosses")
    }

    @Test func theCloudBudgetIsUnchanged() throws {
        let plan = InsightsPromptBuilder.plan(text: "I walked to the river.", source: .voice, sections: sections(), vocabulary: .empty, model: "gpt")
        let fields = try properties(plan)
        #expect(fields["cleanedText"] != nil)
        #expect(plan.customKeys.count == 1)
        #expect(plan.request.system.contains("(\(Mood.calm.meaning))"))
    }

    // Guided generation needs a schema it accepts; every section, handles included, has to convert.
    @Test func theInsightsAndReflectSchemasConvertForGuidedGeneration() throws {
        let vocabulary = InsightsPromptBuilder.JournalVocabulary(looseEnds: [.init(id: UUID(), text: "call the landlord", own: false)])
        let plan = InsightsPromptBuilder.plan(text: "x", source: .typed, sections: InsightSections(), vocabulary: vocabulary, model: "", budget: .onDevice)
        let schema = try #require(plan.request.schema)
        _ = try FoundationModelsTextGenerator.generationSchema(schema, name: plan.request.schemaName)

        let reflect = JSONSchema.object([.init("summary", .string()), .init("prompt", .string())])
        _ = try FoundationModelsTextGenerator.generationSchema(reflect, name: "reflect_summary")
    }

    @Test func nullableFieldsBecomeOptionalProperties() {
        #expect(JSONSchema.string(nullable: true).isNullable)
        #expect(!JSONSchema.array(.string()).isNullable)
        #expect(JSONSchema.enumeration(["a"], description: "pick one").summary == "pick one")
    }
}

@MainActor
struct InsightsGeneratorSettingTests {
    @Test func defaultsLikeTitles() {
        let store = FakeKeyValueStore()
        let onDevice = SettingsStore(store: store, diagnostics: .disabled, onDeviceTitlesAvailable: { true })
        #expect(onDevice.insightsGenerator == .onDevice, "no key, a capable phone: the phone reads entries")

        let neither = SettingsStore(store: FakeKeyValueStore(), diagnostics: .disabled, onDeviceTitlesAvailable: { false })
        #expect(neither.insightsGenerator == .off)

        onDevice.providerAccounts = [.openAI()]
        onDevice.aiEnabled = true
        #expect(onDevice.insightsGenerator == .openAI, "a key moves insights to OpenAI until the user picks")

        onDevice.insightsGenerator = .onDevice
        #expect(SettingsStore(store: store, diagnostics: .disabled, onDeviceTitlesAvailable: { true }).insightsGenerator == .onDevice, "a choice sticks")
    }

    // With no key the phone runs insights, but bios still need OpenAI and must not start trying.
    @Test func biosKeepNeedingAKey() {
        let settings = SettingsStore(store: FakeKeyValueStore(), diagnostics: .disabled, onDeviceTitlesAvailable: { true })
        let accounts = ProviderAccountStore(settings: settings, secrets: FakeSecretStore(), diagnostics: .disabled)
        #expect(!AIServices.automaticBiosUsable(settings: settings, accounts: accounts))

        settings.insightsGenerator = .off
        let readiness = AIServices.insightsReadiness(settings: settings, accounts: accounts)
        #expect(!readiness.enabled && !readiness.ready)
    }
}

// The whole path against Apple's real model, when this machine has it: the on-device prompt, the
// schema through guided generation, and the ordinary parser. Skipped where the model isn't there.
struct OnDeviceInsightsLiveTests {
    @Test(.enabled(if: FoundationModelsAvailability.isAvailable), .timeLimit(.minutes(1)))
    func aRealEntryComesBackAsInsights() async throws {
        let text = """
        Coffee with Maya at Blue Door this morning. She's moving to Denver in March and I still \
        haven't decided whether to take the lead role Priya offered. Need to call the landlord \
        about the lease before Friday. Felt calm walking home along the river.
        """
        let plan = InsightsPromptBuilder.plan(text: text, source: .typed, sections: InsightSections(), vocabulary: .empty, model: "", entryDate: Date(timeIntervalSince1970: 1_789_000_000), budget: .onDevice)
        let started = ContinuousClock.now
        let answer = try await FoundationModelsTextGenerator().generate(plan.request)
        let result = try InsightsPromptBuilder.parse(answer.text, plan: plan)
        print("ON-DEVICE INSIGHTS \(started.duration(to: .now)): \(answer.text)")

        #expect(result.summary != nil)
        #expect(result.primaryMood != nil)
        #expect(!result.areas.isEmpty)
        #expect(result.mentions.contains { $0.name.contains("Maya") })
    }
}
