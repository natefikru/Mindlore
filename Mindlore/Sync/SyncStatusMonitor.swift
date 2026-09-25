import CloudKit
import CoreData
import Foundation

// Watches the two things the iCloud row reports: the account, refreshed at launch and whenever iOS
// says it changed, and the mirroring's own events, which SwiftData's CloudKit store posts through
// NSPersistentCloudKitContainer. Reads nothing from the journal.
@Observable
final class SyncStatusMonitor {
    // One sync event, reduced to what the status needs; the real ones come from Core Data.
    nonisolated struct Event: Sendable {
        enum Kind: String, Sendable { case setup, `import`, export }
        let id: UUID
        let kind: Kind
        let started: Date
        let ended: Date?
        let succeeded: Bool
        let problem: SyncProblem?
    }

    private(set) var status: SyncStatus

    private let mirrors: Bool
    private let switchedOff: Bool
    private let storeFailed: Bool
    private let accountStatus: @Sendable () async throws -> CKAccountStatus
    private let userRecordName: @Sendable () async throws -> String?
    // Told the account's record name once it is known to be signed in, or nil once it is known to
    // be signed out; never for an account iCloud couldn't answer about.
    var onAccountChecked: ((String?) -> Void)?
    private let diagnostics: DiagnosticsLog
    private var account: SyncAccount?
    private var inFlight: Set<UUID> = []
    private var lastSuccess: Date?
    private var lastProblem: SyncProblem?
    private var started = false

    init(
        mirrors: Bool,
        switchedOff: Bool = false,
        storeFailed: Bool = false,
        containerID: String? = AppConfig.cloudKitContainerID,
        accountStatus: (@Sendable () async throws -> CKAccountStatus)? = nil,
        userRecordName: (@Sendable () async throws -> String?)? = nil,
        diagnostics: DiagnosticsLog = .shared
    ) {
        self.mirrors = mirrors
        self.switchedOff = switchedOff
        self.storeFailed = storeFailed
        self.diagnostics = diagnostics
        // Only a store that mirrors ever asks CloudKit anything; a test run or a demo journal never does.
        self.accountStatus = accountStatus ?? { [containerID] in
            guard let containerID else { return .couldNotDetermine }
            return try await CKContainer(identifier: containerID).accountStatus()
        }
        self.userRecordName = userRecordName ?? { [containerID] in
            guard let containerID else { return nil }
            return try await CKContainer(identifier: containerID).userRecordID().recordName
        }
        status = SyncStatus.derive(mirrors: mirrors, switchedOff: switchedOff, storeFailed: storeFailed, account: nil, inFlight: false, lastSuccess: nil, lastProblem: nil)
    }

    // Idempotent; the root view calls it from a task.
    func start() {
        guard mirrors, !started else { return }
        started = true
        Task { await refreshAccount() }
        Task {
            for await _ in NotificationCenter.default.notifications(named: .CKAccountChanged) {
                await refreshAccount()
            }
        }
        Task {
            for await note in NotificationCenter.default.notifications(named: NSPersistentCloudKitContainer.eventChangedNotification) {
                guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else { continue }
                apply(Event(event))
            }
        }
    }

    func refreshAccount() async {
        let refreshed: SyncAccount
        do {
            refreshed = SyncAccount(try await accountStatus())
        } catch {
            refreshed = .unknown
        }
        switch refreshed {
        case .available:
            if let name = try? await userRecordName() { onAccountChecked?(name) }
        case .noAccount:
            onAccountChecked?(nil)
        default:
            break
        }
        account = refreshed
        // A sign-in is a fresh start; an old "signed out" failure shouldn't outlive it.
        if refreshed == .available, lastProblem == .signedOut { lastProblem = nil }
        update()
    }

    func apply(_ event: Event) {
        guard let ended = event.ended else {
            inFlight.insert(event.id)
            update()
            return
        }
        inFlight.remove(event.id)
        if event.succeeded {
            lastSuccess = ended
            lastProblem = nil
        } else {
            lastProblem = event.problem ?? .failed("unknown")
        }
        var fields: [String: DiagnosticValue] = [
            "kind": .string(event.kind.rawValue),
            "succeeded": .bool(event.succeeded),
            "milliseconds": .int(Int(ended.timeIntervalSince(event.started) * 1000)),
        ]
        if !event.succeeded, let problem = event.problem {
            fields["problem"] = .string(SyncStatus.paused(problem).diagnosticName)
            if case .failed(let code) = problem { fields["error"] = .string(code) }
        }
        diagnostics.record("sync.event", fields)
        update()
    }

    private func update() {
        let next = SyncStatus.derive(
            mirrors: mirrors,
            switchedOff: switchedOff,
            storeFailed: storeFailed,
            account: account,
            inFlight: !inFlight.isEmpty,
            lastSuccess: lastSuccess,
            lastProblem: lastProblem
        )
        if next.diagnosticName != status.diagnosticName {
            diagnostics.record("sync.status", ["status": .string(next.diagnosticName)])
        }
        status = next
    }
}

extension SyncStatusMonitor.Event {
    init(_ event: NSPersistentCloudKitContainer.Event) {
        let kind: Kind = switch event.type {
        case .setup: .setup
        case .import: .import
        default: .export
        }
        self.init(
            id: event.identifier,
            kind: kind,
            started: event.startDate,
            ended: event.endDate,
            succeeded: event.succeeded,
            problem: event.error.map(SyncProblem.init)
        )
    }
}
