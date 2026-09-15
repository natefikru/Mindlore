import Foundation
import Testing
@testable import Mindlore

final class FakeKeyValueStore: KeyValueStore {
    var values: [String: Any] = [:]

    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
}

@MainActor
struct SettingsStoreTests {
    @Test func usesDefaultsWhenNothingIsStored() {
        let settings = SettingsStore(store: FakeKeyValueStore())

        #expect(settings.keepAudioAfterTranscription == true)
        #expect(settings.defaultEntryMode == .voice)
    }

    @Test func storedFalseIsNotMistakenForMissing() {
        let store = FakeKeyValueStore()
        store.values[SettingsStore.Key.keepAudioAfterTranscription] = false

        #expect(SettingsStore(store: store).keepAudioAfterTranscription == false)
    }

    @Test func changesAreWrittenToTheStore() {
        let store = FakeKeyValueStore()
        let settings = SettingsStore(store: store)

        settings.keepAudioAfterTranscription = false
        settings.defaultEntryMode = .typed

        #expect(store.values[SettingsStore.Key.keepAudioAfterTranscription] as? Bool == false)
        #expect(store.values[SettingsStore.Key.defaultEntryMode] as? String == "typed")
    }

    @Test func changesAreLoggedWithoutAffectingStoredValues() throws {
        let file = DiagnosticsFile()
        let settings = SettingsStore(store: FakeKeyValueStore(), diagnostics: DiagnosticsLog(fileURL: file.url))

        settings.keepAudioAfterTranscription = false
        settings.defaultEntryMode = .typed

        let events = try file.events()
        #expect(events.map { $0["event"] as? String } == ["settings.changed", "settings.changed"])
        #expect(events[0]["key"] as? String == "keepAudioAfterTranscription")
        #expect(events[0]["value"] as? Bool == false)
        #expect(events[1]["value"] as? String == "typed")
    }

    @Test func initDoesNotWriteDefaultsBack() {
        let store = FakeKeyValueStore()
        _ = SettingsStore(store: store)

        #expect(store.values.isEmpty)
    }

    @Test func unknownEntryModeFallsBackToVoice() {
        let store = FakeKeyValueStore()
        store.values[SettingsStore.Key.defaultEntryMode] = "telepathy"

        #expect(SettingsStore(store: store).defaultEntryMode == .voice)
    }

    @Test func wrongTypeFallsBackToDefault() {
        let store = FakeKeyValueStore()
        store.values[SettingsStore.Key.keepAudioAfterTranscription] = "no"

        #expect(SettingsStore(store: store).keepAudioAfterTranscription == true)
    }

    @Test func valuesSurviveANewStoreInstanceWithRealUserDefaults() throws {
        let suite = "SettingsStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = SettingsStore(store: defaults)
        first.keepAudioAfterTranscription = false
        first.defaultEntryMode = .typed

        let second = SettingsStore(store: defaults)
        #expect(second.keepAudioAfterTranscription == false)
        #expect(second.defaultEntryMode == .typed)
    }
    @Test func aiSettingsDefaults() {
        let settings = SettingsStore(store: FakeKeyValueStore())

        #expect(settings.aiEnabled == false)
        #expect(settings.aiEnabledAt == nil)
        #expect(settings.automationStartedAt == nil)
        #expect(settings.providerAccounts.isEmpty)
        #expect(settings.speechEngine == .cloud)
        #expect(settings.speechModel == "gpt-transcribe")
        #expect(settings.pageModel == "gpt-5.6-terra")
        #expect(settings.textModel == "gpt-5.6-luna")
        #expect(settings.fallBackToOnDevice)
        #expect(settings.insightsTrigger == .automatic)
        #expect(settings.insightSummary && settings.insightMoods && settings.insightThemes && settings.insightTags)
        #expect(settings.insightMentions && settings.insightOpenThreads && settings.insightCleanedText)
        #expect(settings.autoApplyCleanedText == false)
        #expect(settings.suggestEntryDates)
        #expect(settings.customInsightPrompts.isEmpty)
    }

    @Test func turningAIOnStampsTheTimeEachTime() {
        let store = FakeKeyValueStore()
        var clock = Date(timeIntervalSince1970: 1_000)
        let settings = SettingsStore(store: store, now: { clock })

        settings.aiEnabled = true
        #expect(settings.aiEnabledAt == Date(timeIntervalSince1970: 1_000))

        clock = Date(timeIntervalSince1970: 2_000)
        settings.aiEnabled = true
        #expect(settings.aiEnabledAt == Date(timeIntervalSince1970: 1_000))

        settings.aiEnabled = false
        settings.aiEnabled = true
        #expect(settings.aiEnabledAt == Date(timeIntervalSince1970: 2_000))
        #expect(SettingsStore(store: store).aiEnabledAt == Date(timeIntervalSince1970: 2_000))
    }

    @Test func automationStartIsWrittenOnceAndNeverMoves() {
        let store = FakeKeyValueStore()
        var clock = Date(timeIntervalSince1970: 1_000)
        let settings = SettingsStore(store: store, now: { clock })
        settings.recordAutomationStartIfNeeded()
        clock = Date(timeIntervalSince1970: 9_000)
        settings.recordAutomationStartIfNeeded()

        let relaunched = SettingsStore(store: store, now: { clock })
        relaunched.recordAutomationStartIfNeeded()
        #expect(relaunched.automationStartedAt == Date(timeIntervalSince1970: 1_000))
    }

    @Test func titleGeneratorDefaultFollowsOnDeviceAvailabilityUntilChosen() {
        let store = FakeKeyValueStore()
        #expect(SettingsStore(store: store, onDeviceTitlesAvailable: { true }).titleGenerator == .onDevice)
        #expect(SettingsStore(store: store, onDeviceTitlesAvailable: { false }).titleGenerator == .off)
        #expect(store.values[SettingsStore.Key.titleGenerator] == nil)

        SettingsStore(store: store, onDeviceTitlesAvailable: { true }).titleGenerator = .openAI
        #expect(SettingsStore(store: store, onDeviceTitlesAvailable: { false }).titleGenerator == .openAI)
    }

    @Test func jsonSettingsRoundTripAndFallBackOnBadData() {
        let store = FakeKeyValueStore()
        let settings = SettingsStore(store: store)
        let prompt = CustomInsightPrompt(id: UUID(), name: "Gratitude", instructions: "What am I grateful for?", enabled: true)
        let account = ProviderAccount.openAI()
        settings.customInsightPrompts = [prompt]
        settings.providerAccounts = [account]
        settings.speechAccountID = account.id

        let reloaded = SettingsStore(store: store)
        #expect(reloaded.customInsightPrompts == [prompt])
        #expect(reloaded.providerAccounts == [account])
        #expect(reloaded.account(for: .speech) == account)
        #expect(reloaded.account(for: .text) == nil)

        store.values[SettingsStore.Key.customInsightPrompts] = Data("garbage".utf8)
        store.values[SettingsStore.Key.speechEngine] = "warp"
        let fallback = SettingsStore(store: store)
        #expect(fallback.customInsightPrompts.isEmpty)
        #expect(fallback.speechEngine == .cloud)
    }

    @Test func promptAndAccountChangesAreLoggedWithoutTheirContents() throws {
        let file = DiagnosticsFile()
        let settings = SettingsStore(store: FakeKeyValueStore(), diagnostics: DiagnosticsLog(fileURL: file.url))

        settings.customInsightPrompts = [CustomInsightPrompt(id: UUID(), name: "SECRET-NAME", instructions: "SECRET-INSTRUCTIONS", enabled: true)]
        settings.providerAccounts = [.openAI()]

        let contents = try String(contentsOf: file.url, encoding: .utf8)
        #expect(!contents.contains("SECRET-NAME"))
        #expect(!contents.contains("SECRET-INSTRUCTIONS"))
        #expect(!contents.contains("api.openai.com"))
        #expect(try file.events().compactMap { $0["key"] as? String } == ["customInsightPrompts", "providerAccounts"])
    }
}
