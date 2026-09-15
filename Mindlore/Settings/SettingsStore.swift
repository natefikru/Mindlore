import Foundation
import Observation

@Observable
final class SettingsStore {
    enum Key {
        static let keepAudioAfterTranscription = "keepAudioAfterTranscription"
        static let defaultEntryMode = "defaultEntryMode"
    }

    @ObservationIgnored private let store: any KeyValueStore
    @ObservationIgnored private let diagnostics: DiagnosticsLog

    var keepAudioAfterTranscription: Bool {
        didSet {
            store.set(keepAudioAfterTranscription, forKey: Key.keepAudioAfterTranscription)
            diagnostics.record("settings.changed", ["key": .string(Key.keepAudioAfterTranscription), "value": .bool(keepAudioAfterTranscription)])
        }
    }

    var defaultEntryMode: EntrySource {
        didSet {
            store.set(defaultEntryMode.rawValue, forKey: Key.defaultEntryMode)
            diagnostics.record("settings.changed", ["key": .string(Key.defaultEntryMode), "value": .string(defaultEntryMode.rawValue)])
        }
    }

    // Reads go through object(forKey:) so a missing key means "use the default" rather than false.
    init(store: any KeyValueStore = UserDefaults.standard, diagnostics: DiagnosticsLog = .shared) {
        self.store = store
        self.diagnostics = diagnostics
        keepAudioAfterTranscription = store.object(forKey: Key.keepAudioAfterTranscription) as? Bool ?? true
        defaultEntryMode = (store.object(forKey: Key.defaultEntryMode) as? String).flatMap(EntrySource.init(rawValue:)) ?? .voice
    }
}
