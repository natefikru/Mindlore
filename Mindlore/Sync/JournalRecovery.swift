import CloudKit
import CryptoKit
import Foundation
import SwiftData

// Decides when to offer the safety copy back, and does the restoring.
//
// A restore is only offered after something that can empty the store: the iCloud account changed
// or went away, Core Data announced it is resetting sync, or the journal is empty while backups
// exist. Outside those, an entry missing from the store was deleted on another device, and its
// backup is dropped instead of offered, so a later restore can't bring a deliberate delete back.
//
// Nothing is offered until sync has settled (up to date, device only, or paused): offered earlier,
// a restore races the import that was about to bring the same entries back.
@Observable
final class JournalRecovery {
    private(set) var missing: [EntryBackup] = []
    var bannerDismissed = false

    // False for a store that never syncs (tests, demo journals): nothing is backed up or offered.
    let enabled: Bool
    private let backups: EntryBackups
    private let defaults: UserDefaults
    private let diagnostics: DiagnosticsLog

    static let pendingKey = "sync.pendingRecoveryCheck"
    static let fingerprintKey = "sync.accountFingerprint"
    // Posted by Core Data's CloudKit mirroring before it deletes synced data (reason AccountLogout,
    // AccountChange, and others). Observed by name; it has no public constant.
    static let willResetSync = Notification.Name("NSCloudKitMirroringDelegateWillResetSyncNotificationName")

    private var resetObserver: (any NSObjectProtocol)?

    // Built before the store opens, so a reset Core Data announces while it sets up is heard.
    init(backups: EntryBackups, enabled: Bool = true, defaults: UserDefaults = .standard, diagnostics: DiagnosticsLog = .shared, observesResets: Bool = true) {
        self.enabled = enabled
        self.backups = backups
        self.defaults = defaults
        self.diagnostics = diagnostics
        guard enabled, observesResets else { return }
        resetObserver = NotificationCenter.default.addObserver(forName: Self.willResetSync, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.markPending("syncReset") }
        }
    }

    var isPending: Bool { defaults.bool(forKey: Self.pendingKey) }
    var showsBanner: Bool { !missing.isEmpty && !bannerDismissed }

    func markPending(_ reason: String) {
        guard !isPending else { return }
        defaults.set(true, forKey: Self.pendingKey)
        diagnostics.record("recovery.pending", ["reason": .string(reason)])
    }

    // The account as an opaque hash of its record name: never a name or an email.
    static func fingerprint(of recordName: String?) -> String? {
        recordName.map { SHA256.hash(data: Data($0.utf8)).map { String(format: "%02x", $0) }.joined() }
    }

    // A signed-in account that differs from the last one seen, or none where there was one, is
    // the moment Core Data purges. The first account ever seen only gets remembered.
    func accountSeen(recordName: String?) {
        guard enabled else { return }
        let current = Self.fingerprint(of: recordName)
        let previous = defaults.string(forKey: Self.fingerprintKey)
        if let previous, previous != current {
            markPending(current == nil ? "signedOut" : "accountChanged")
        }
        if let current { defaults.set(current, forKey: Self.fingerprintKey) }
    }

    // Called at launch and whenever sync settles or remote changes land.
    func check(in context: ModelContext, status: SyncStatus) {
        guard enabled else { return }
        let entryCount = (try? context.fetchCount(FetchDescriptor<Entry>())) ?? 0
        if entryCount == 0, !backups.storedIDs().isEmpty {
            markPending("emptyStore")
        }
        guard status.isSettled else { return }
        if let merged = try? EntryDuplicates.merge(in: context), merged > 0 {
            diagnostics.record("recovery.duplicatesMerged", ["count": .int(merged)])
        }
        let gone = (try? backups.missing(from: context)) ?? []
        if isPending {
            missing = gone
            if gone.isEmpty { defaults.set(false, forKey: Self.pendingKey) }
        } else if case .upToDate = status, entryCount > 0, !gone.isEmpty {
            // Deleted on another device: drop the copies so a later restore can't undo it.
            backups.apply(EntryBackups.Pending(removed: gone.map(\.id)))
            diagnostics.record("recovery.pruned", ["count": .int(gone.count)])
        }
    }

    func restoreAll(in context: ModelContext) {
        let toRestore = missing
        guard !toRestore.isEmpty else { return }
        for backup in toRestore {
            context.insert(Entry.restored(from: backup))
        }
        do {
            try context.saveStampingEntries(at: .now, except: [])
            missing = []
            defaults.set(false, forKey: Self.pendingKey)
            diagnostics.record("recovery.restored", ["count": .int(toRestore.count)])
        } catch {
            diagnostics.record("recovery.failed", ["error": .errorCode(error)])
        }
    }
}
