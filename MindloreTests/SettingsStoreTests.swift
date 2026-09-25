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

        #expect(store.values[SettingsStore.Key.keepAudioAfterTranscription] as? Bool == false)
    }

    @Test func changesAreLoggedWithoutAffectingStoredValues() throws {
        let file = DiagnosticsFile()
        let settings = SettingsStore(store: FakeKeyValueStore(), diagnostics: DiagnosticsLog(fileURL: file.url))

        settings.keepAudioAfterTranscription = false

        let events = try file.events()
        #expect(events.map { $0["event"] as? String } == ["settings.changed"])
        #expect(events[0]["key"] as? String == "keepAudioAfterTranscription")
        #expect(events[0]["value"] as? Bool == false)
    }

    @Test func resurfacingIsOnUntilItIsTurnedOff() {
        let store = FakeKeyValueStore()
        #expect(SettingsStore(store: store).resurfacingEnabled == true)

        store.values[SettingsStore.Key.resurfacingEnabled] = false
        #expect(SettingsStore(store: store).resurfacingEnabled == false)
    }

    @Test func aDismissedTodayCardSurvivesARelaunch() {
        let store = FakeKeyValueStore()
        let settings = SettingsStore(store: store)

        settings.dismissTodayCard("onThisDay", on: "2026-09-19")

        #expect(SettingsStore(store: store).dismissedTodayCards(on: "2026-09-19") == ["onThisDay"])
        #expect(SettingsStore(store: store).dismissedTodayCards(on: "2026-09-20").isEmpty)
    }

    // The keys can name an entity or a loose end, so the value never reaches the log.
    @Test func dismissingACardLogsTheKeyAndNotTheCards() throws {
        let file = DiagnosticsFile()
        let settings = SettingsStore(store: FakeKeyValueStore(), diagnostics: DiagnosticsLog(fileURL: file.url))

        settings.dismissTodayCard("beenAWhile:Sarah Kim", on: "2026-09-19")

        let events = try file.events()
        #expect(events.map { $0["event"] as? String } == ["settings.changed"])
        #expect(events[0]["key"] as? String == "todayDismissed")
        #expect(events[0]["value"] == nil)
        #expect(!(try String(contentsOf: file.url, encoding: .utf8)).contains("Sarah Kim"))
    }

    @Test func dismissingTheSameCardTwiceWritesOnce() {
        let store = FakeKeyValueStore()
        let settings = SettingsStore(store: store)
        settings.dismissTodayCard("onThisDay", on: "2026-09-19")
        let written = store.values[SettingsStore.Key.todayDismissed] as? Data

        settings.dismissTodayCard("onThisDay", on: "2026-09-19")

        #expect(store.values[SettingsStore.Key.todayDismissed] as? Data == written)
    }

    @Test func aCorruptDismissalBlobReadsAsNothingDismissed() {
        let store = FakeKeyValueStore()
        store.values[SettingsStore.Key.todayDismissed] = Data("not json".utf8)

        #expect(SettingsStore(store: store).dismissedTodayCards(on: "2026-09-19").isEmpty)
    }

    @Test func initDoesNotWriteDefaultsBack() {
        let store = FakeKeyValueStore()
        _ = SettingsStore(store: store)

        #expect(store.values.isEmpty)
    }

    @Test func unknownStoredChoiceFallsBackToItsDefault() {
        let store = FakeKeyValueStore()
        store.values[SettingsStore.Key.insightsTrigger] = "telepathy"
        store.values[SettingsStore.Key.titleGenerator] = "telepathy"

        let settings = SettingsStore(store: store, onDeviceTitlesAvailable: { true })
        #expect(settings.insightsTrigger == .automatic)
        #expect(settings.titleGenerator == .onDevice)
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
        first.insightsTrigger = .manual

        let second = SettingsStore(store: defaults)
        #expect(second.keepAudioAfterTranscription == false)
        #expect(second.insightsTrigger == .manual)
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
        #expect(settings.insightSummary && settings.insightMoods && settings.insightLifeAreas && settings.insightTags)
        #expect(settings.insightMentions && settings.insightLooseEnds && settings.insightCleanedText)
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

    @Test func titleGeneratorDefaultsToTheProviderOnceAIIsSetUp() {
        let store = FakeKeyValueStore()
        let settings = SettingsStore(store: store, diagnostics: .disabled, onDeviceTitlesAvailable: { true })
        #expect(settings.titleGenerator == .onDevice)

        settings.providerAccounts = [.openAI()]
        settings.aiEnabled = true
        #expect(settings.titleGenerator == .openAI)

        // Turning AI off hands titles back to the phone rather than stopping them.
        settings.aiEnabled = false
        #expect(settings.titleGenerator == .onDevice)
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

    // Apple's live transcription is free, private, and shows text as you talk, so it leads on any
    // phone that can run it. Phones that can't start on OpenAI instead of on something broken.
    @Test func speechDefaultsToLiveWhereThePhoneSupportsIt() {
        #expect(SettingsStore(store: FakeKeyValueStore(), onDeviceSpeechAvailable: { true }).speechEngine == .onDeviceLive)
        #expect(SettingsStore(store: FakeKeyValueStore(), onDeviceSpeechAvailable: { false }).speechEngine == .cloud)
    }

    @Test func aStoredSpeechChoiceBeatsWhatTheDeviceCanDo() {
        let store = FakeKeyValueStore()
        let settings = SettingsStore(store: store, onDeviceSpeechAvailable: { true })
        settings.speechEngine = .cloud

        #expect(SettingsStore(store: store, onDeviceSpeechAvailable: { true }).speechEngine == .cloud)

        let onDevice = SettingsStore(store: store, onDeviceSpeechAvailable: { false })
        onDevice.speechEngine = .onDevice
        #expect(SettingsStore(store: store, onDeviceSpeechAvailable: { false }).speechEngine == .onDevice)
    }

    @Test func onlyLiveStartsASession() {
        #expect(SpeechEngine.onDeviceLive.wantsLiveSession)
        #expect(SpeechEngine.onDevice.wantsLiveSession == false)
        #expect(SpeechEngine.cloud.wantsLiveSession == false)
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

@MainActor
struct SettingsMirroringTests {
    final class CountingStore: KeyValueStore {
        var values: [String: Any] = [:]
        var writes = 0
        func object(forKey key: String) -> Any? { values[key] }
        func set(_ value: Any?, forKey key: String) {
            values[key] = value
            writes += 1
        }
    }

    @Test func everyMirroredKeyIsReloaded() {
        #expect(Set(SettingsStore.mirroredCopies.keys) == SettingsStore.Key.mirrored)
    }

    @Test func nothingAboutThisPhoneIsMirrored() {
        let perPhone: [String] = [
            SettingsStore.Key.aiEnabled, SettingsStore.Key.aiEnabledAt, SettingsStore.Key.providerAccounts,
            SettingsStore.Key.speechAccountID, SettingsStore.Key.textAccountID, SettingsStore.Key.pageAccountID,
            SettingsStore.Key.titleGenerator, SettingsStore.Key.insightsGenerator, SettingsStore.Key.askGenerator,
            SettingsStore.Key.appearance, SettingsStore.Key.recordOnOpen, SettingsStore.Key.reminderEnabled,
            SettingsStore.Key.appLockEnabled, SettingsStore.Key.welcomeSeen, SettingsStore.Key.todayDismissed,
        ]
        #expect(SettingsStore.Key.mirrored.isDisjoint(with: perPhone))
    }

    @Test func aChangeFromAnotherPhoneShowsWithoutBeingWrittenBack() throws {
        let store = CountingStore()
        let settings = SettingsStore(store: store)

        store.values[SettingsStore.Key.lifeAreaNames] = try JSONEncoder().encode(["work": "Studio"])
        store.values[SettingsStore.Key.journalFont] = JournalFont.rounded.rawValue
        store.values[SettingsStore.Key.insightMoods] = false
        store.values[SettingsStore.Key.appearance] = AppearancePreference.dark.rawValue
        settings.reloadMirrored()

        #expect(settings.name(of: .work) == "Studio")
        #expect(settings.journalFont == .rounded)
        #expect(settings.insightMoods == false)
        // Appearance is this phone's own; a value arriving in the store is not picked up here.
        #expect(settings.appearance == .system)
        #expect(store.writes == 0)
    }

    @Test func aRemovedKeyGoesBackToTheDefault() {
        let store = FakeKeyValueStore()
        let settings = SettingsStore(store: store)
        settings.setUserName("Teo")

        store.values[SettingsStore.Key.userName] = nil
        settings.reloadMirrored()

        #expect(settings.userName == "")
    }

    @Test func writesAfterAReloadStillGoOut() {
        let store = CountingStore()
        let settings = SettingsStore(store: store)
        settings.reloadMirrored()

        settings.insightTags = false

        #expect(store.values[SettingsStore.Key.insightTags] as? Bool == false)
        #expect(store.writes == 1)
    }
}
