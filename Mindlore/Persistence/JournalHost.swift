import Foundation
import SwiftData

// Opens the journal's store and holds it, with the sync status that watches it, so the sync switch
// can close it and open it again the other way (owner, 2026-09-25). Mirroring can't be turned on or
// off on a live container, so the switch drops the whole root, waits for the old container to go,
// and opens a new one: two containers never work one file at once.
@Observable
final class JournalHost {
    enum Phase {
        case open(Journal)
        case switching(on: Bool)
        case failed(any Error)
    }

    struct Journal {
        let container: ModelContainer
        let sync: SyncStatusMonitor
        // The root view is keyed on it, so a reopened journal builds every coordinator afresh.
        let generation: Int
    }

    private(set) var phase: Phase
    let recovery: JournalRecovery
    // The user's own journal, the one that can sync: not a test's store or a demo journal.
    let isJournal: Bool
    // Whether the open store was opened to sync. Always false off the journal.
    private(set) var syncOn: Bool
    // What the switch says: saved at once, applied when Settings closes or at the next launch.
    private(set) var requestedSyncOn: Bool

    private let openStore: (_ cloudKit: Bool) throws -> ModelContainer
    private let prepare: (ModelContainer) -> Void
    private let settingsMirror: MirroredKeyValueStore?
    private let defaults: UserDefaults
    private let diagnostics: DiagnosticsLog
    private let releaseTimeout: Duration
    private var generation = 0

    // `openStore` opens with CloudKit or without; `prepare` runs the launch repairs and
    // registrations on each container it returns.
    init(
        isJournal: Bool,
        recovery: JournalRecovery,
        settingsMirror: MirroredKeyValueStore? = nil,
        defaults: UserDefaults = .standard,
        diagnostics: DiagnosticsLog = .shared,
        releaseTimeout: Duration = .seconds(5),
        openStore: @escaping (_ cloudKit: Bool) throws -> ModelContainer,
        prepare: @escaping (ModelContainer) -> Void
    ) {
        self.isJournal = isJournal
        self.recovery = recovery
        self.settingsMirror = settingsMirror
        self.defaults = defaults
        self.diagnostics = diagnostics
        self.releaseTimeout = releaseTimeout
        self.openStore = openStore
        self.prepare = prepare
        let on = isJournal && SyncSwitch.isOn(in: defaults)
        syncOn = on
        requestedSyncOn = on
        // A placeholder until every property is set and `open` can run.
        phase = .switching(on: on)
        phase = open(syncOn: on)
    }

    var hasPendingSwitch: Bool { isJournal && requestedSyncOn != syncOn }

    var isSwitching: Bool {
        if case .switching = phase { true } else { false }
    }

    // The toggle. Nothing closes yet: the Settings sheet it sits in would go with the root.
    func requestSync(_ on: Bool) {
        guard isJournal, on != requestedSyncOn else { return }
        requestedSyncOn = on
        SyncSwitch.set(on, in: defaults)
    }

    // When Settings closes. The caller flushes its saver first.
    func applyPendingSwitch() async {
        guard hasPendingSwitch, let old = openContainer.map(WeakContainer.init) else { return }
        let on = requestedSyncOn
        let started = ContinuousClock.now
        ReflectSummaryStore.cancelPendingRefresh()
        settingsMirror?.isEnabled = on
        phase = .switching(on: on)
        // Every view, task, and coordinator of the old root lets go of it once the root is gone.
        let deadline = started + releaseTimeout
        while old.container != nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        let released = old.container == nil
        syncOn = on
        if on { settingsMirror?.start() }
        phase = open(syncOn: on)
        diagnostics.record("sync.switched", [
            "on": .bool(on),
            "released": .bool(released),
            "milliseconds": .int(Int((ContinuousClock.now - started) / .milliseconds(1))),
        ])
    }

    private var openContainer: ModelContainer? {
        if case .open(let journal) = phase { journal.container } else { nil }
    }

    private func open(syncOn on: Bool) -> Phase {
        let mirrors = isJournal && on
        var storeFailed = false
        var opened = Result { try openStore(mirrors) }
        // A journal that can't open its iCloud store still opens, on this iPhone alone, rather than
        // leaving the app on an error screen; Settings says so and the next launch tries again.
        // Only a store that opens without CloudKit makes this a sync failure: one that fails both
        // ways failed for another reason (a migration, most likely), and the original error is the
        // one worth reading.
        if mirrors, case .failure(let error) = opened, case .success(let local) = Result(catching: { try openStore(false) }) {
            diagnostics.record("sync.storeFailed", ["error": .errorCode(error)])
            storeFailed = true
            opened = .success(local)
        }
        switch opened {
        case .success(let container):
            prepare(container)
            let monitor = SyncStatusMonitor(mirrors: mirrors, switchedOff: isJournal && !on, storeFailed: storeFailed, diagnostics: diagnostics)
            monitor.onAccountChecked = { [recovery] name in recovery.accountSeen(recordName: name) }
            generation += 1
            return .open(Journal(container: container, sync: monitor, generation: generation))
        case .failure(let error):
            diagnostics.record("store.openFailed", ["error": .errorCode(error)])
            return .failed(error)
        }
    }

    private final class WeakContainer {
        weak var container: ModelContainer?
        init(_ container: ModelContainer) { self.container = container }
    }
}
