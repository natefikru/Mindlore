import Foundation

// "Sync with iCloud" (owner, 2026-09-23: on by default). This phone's choice alone, so it lives in
// plain UserDefaults and is never mirrored: turning it off here must not turn it off everywhere.
enum SyncSwitch {
    static let key = "sync.enabled"

    static func isOn(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }

    static func set(_ on: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(on, forKey: key)
    }
}
