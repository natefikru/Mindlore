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
}
