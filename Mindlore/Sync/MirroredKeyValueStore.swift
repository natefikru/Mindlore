import Foundation

// iCloud's key-value store, behind a protocol so tests never touch it.
nonisolated protocol CloudKeyValues: AnyObject {
    func object(forKey key: String) -> Any?
    // Not `set(_:forKey:)`: the real store already has one, and an extension of the same name
    // would be calling itself.
    func write(_ value: Any?, forKey key: String)
    @discardableResult func synchronize() -> Bool
}

nonisolated extension NSUbiquitousKeyValueStore: CloudKeyValues {
    func write(_ value: Any?, forKey key: String) {
        if let value { set(value, forKey: key) } else { removeObject(forKey: key) }
    }
}

// The settings that describe the journal itself (area names, your name, the font, what insights
// ask for) follow the journal to every phone; everything about this phone stays here. Reads are
// always local, so a setting never waits on iCloud. A key nobody has set is missing on both sides,
// which `SettingsStore` reads as "use the default", so a fresh phone never pushes its defaults over
// the real ones.
final class MirroredKeyValueStore: KeyValueStore {
    // Why the cloud's copy changed, from `NSUbiquitousKeyValueStoreChangeReasonKey`.
    enum ChangeReason: String {
        case server, initialSync, accountChange, quotaExceeded

        init?(_ code: Int) {
            switch code {
            case NSUbiquitousKeyValueStoreServerChange: self = .server
            case NSUbiquitousKeyValueStoreInitialSyncChange: self = .initialSync
            case NSUbiquitousKeyValueStoreAccountChange: self = .accountChange
            case NSUbiquitousKeyValueStoreQuotaViolationChange: self = .quotaExceeded
            default: return nil
            }
        }
    }

    private let local: any KeyValueStore
    private let cloud: any CloudKeyValues
    private let keys: Set<String>
    private let diagnostics: DiagnosticsLog
    private var observer: (any NSObjectProtocol)?

    // Off with the sync switch: nothing goes up and nothing comes down.
    var isEnabled: Bool
    // Told which mirrored keys now hold a different value locally.
    var onChange: (([String]) -> Void)?

    init(local: any KeyValueStore, cloud: any CloudKeyValues, keys: Set<String>, isEnabled: Bool, diagnostics: DiagnosticsLog = .shared) {
        self.local = local
        self.cloud = cloud
        self.keys = keys
        self.isEnabled = isEnabled
        self.diagnostics = diagnostics
    }

    func object(forKey key: String) -> Any? {
        local.object(forKey: key)
    }

    func set(_ value: Any?, forKey key: String) {
        local.set(value, forKey: key)
        if isEnabled, keys.contains(key) {
            cloud.write(value, forKey: key)
        }
    }

    // Once at launch, and again when the switch comes back on. The cloud wins where it has a
    // value, since that is what the other phones already show.
    func start(observing center: NotificationCenter? = .default) {
        if observer == nil, let center {
            observer = center.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: nil, queue: .main) { [weak self] note in
                let reason = (note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int).flatMap(ChangeReason.init)
                let changed = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
                MainActor.assumeIsolated { self?.cloudChanged(reason: reason, keys: changed) }
            }
        }
        guard isEnabled else { return }
        cloud.synchronize()
        apply(reconciling: Array(keys), reason: "start")
    }

    func cloudChanged(reason: ChangeReason?, keys changed: [String]) {
        guard isEnabled, let reason else { return }
        let mirrored = changed.filter(keys.contains)
        switch reason {
        case .quotaExceeded:
            diagnostics.record("settings.quotaExceeded", [:])
        case .server:
            // Another phone changed these, removals included.
            var updated: [String] = []
            for key in mirrored {
                let value = cloud.object(forKey: key)
                guard !Self.same(value, local.object(forKey: key)) else { continue }
                local.set(value, forKey: key)
                updated.append(key)
            }
            finish(updated, reason: reason.rawValue)
        case .initialSync, .accountChange:
            apply(reconciling: mirrored.isEmpty ? Array(keys) : mirrored, reason: reason.rawValue)
        }
    }

    // What the cloud has comes down; what only this phone has goes up.
    private func apply(reconciling candidates: [String], reason: String) {
        var updated: [String] = []
        for key in candidates.sorted() {
            let mine = local.object(forKey: key)
            if let theirs = cloud.object(forKey: key) {
                guard !Self.same(theirs, mine) else { continue }
                local.set(theirs, forKey: key)
                updated.append(key)
            } else if let mine {
                cloud.write(mine, forKey: key)
            }
        }
        finish(updated, reason: reason)
    }

    private func finish(_ updated: [String], reason: String) {
        guard !updated.isEmpty else { return }
        diagnostics.record("settings.mirrored", ["reason": .string(reason), "count": .int(updated.count)])
        onChange?(updated)
    }

    private static func same(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case (let a?, let b?): (a as? NSObject)?.isEqual(b) ?? false
        default: false
        }
    }
}
