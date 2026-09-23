import CloudKit
import Foundation

// What the iCloud row in Settings says, decided from facts the monitor gathers: whether this store
// mirrors at all, the account, the sync events in flight, and how the last one ended. No
// SwiftData, no CloudKit calls, so every sentence it can produce is tested without a device.
nonisolated enum SyncAccount: Equatable, Sendable {
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case unknown

    init(_ status: CKAccountStatus) {
        switch status {
        case .available: self = .available
        case .noAccount: self = .noAccount
        case .restricted: self = .restricted
        case .temporarilyUnavailable: self = .temporarilyUnavailable
        default: self = .unknown
        }
    }
}

nonisolated enum SyncProblem: Equatable, Sendable {
    case storageFull
    case offline
    case signedOut
    // An error code for diagnostics only; the user is never shown it.
    case failed(String)

    init(_ error: any Error) {
        let nsError = error as NSError
        if nsError.domain == CKError.errorDomain {
            switch CKError.Code(rawValue: nsError.code) {
            case .quotaExceeded: self = .storageFull; return
            case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
                self = .offline; return
            case .notAuthenticated: self = .signedOut; return
            default: break
            }
        }
        if nsError.domain == NSURLErrorDomain {
            self = .offline
            return
        }
        self = .failed("\(nsError.domain) \(nsError.code)")
    }
}

nonisolated enum SyncStatus: Equatable, Sendable {
    // This store never mirrors: a test run, a demo journal, or a build with no container.
    case notSynced
    // The mirrored store failed to open, so the journal opened on this iPhone alone.
    case storeFailed
    case checking
    case deviceOnly(SyncAccount)
    case syncing
    case upToDate(lastSynced: Date?)
    case paused(SyncProblem)

    static func derive(
        mirrors: Bool,
        storeFailed: Bool,
        account: SyncAccount?,
        inFlight: Bool,
        lastSuccess: Date?,
        lastProblem: SyncProblem?
    ) -> SyncStatus {
        if storeFailed { return .storeFailed }
        guard mirrors else { return .notSynced }
        guard let account else { return .checking }
        guard account == .available else { return .deviceOnly(account) }
        if let lastProblem {
            return lastProblem == .signedOut ? .deviceOnly(.noAccount) : .paused(lastProblem)
        }
        if inFlight { return .syncing }
        return .upToDate(lastSynced: lastSuccess)
    }

    // The short value on the row.
    var summary: String {
        switch self {
        case .notSynced, .storeFailed, .deviceOnly: "Off"
        case .checking: "Checking…"
        case .syncing: "Syncing…"
        case .upToDate: "On"
        case .paused(.offline): "Waiting"
        case .paused: "Paused"
        }
    }

    // The sentence under it. Every one says where the journal is, since that is what someone
    // looking here wants to know.
    var explanation: String {
        switch self {
        case .notSynced:
            "This journal stays on this iPhone."
        case .storeFailed:
            "Mindlore couldn't start iCloud sync, so your journal is on this iPhone only for now. It tries again the next time Mindlore opens."
        case .checking:
            "Checking your iCloud account."
        case .deviceOnly(.noAccount):
            "Sign in to iCloud in the Settings app to keep your journal in iCloud and on your other devices. Until then it stays on this iPhone."
        case .deviceOnly(.restricted):
            "iCloud is restricted on this iPhone, so your journal stays here."
        case .deviceOnly:
            "iCloud isn't available right now. Your journal is safe on this iPhone and syncs once it is."
        case .syncing:
            "Your journal is kept in your private iCloud and on every device signed in to your Apple Account. Syncing now."
        case .upToDate(let lastSynced):
            "Your journal is kept in your private iCloud and on every device signed in to your Apple Account." + (lastSynced.map { " Last synced \($0.formatted(.relative(presentation: .named, unitsStyle: .wide)))." } ?? "")
        case .paused(.storageFull):
            "Your iCloud storage is full, so new changes stay on this iPhone until there's room."
        case .paused(.offline):
            "Waiting for a connection. Changes stay on this iPhone and sync when it's back."
        case .paused:
            "Syncing hit a problem. Your journal is safe on this iPhone, and Mindlore keeps trying."
        }
    }

    // One word for diagnostics, never a sentence.
    var diagnosticName: String {
        switch self {
        case .notSynced: "notSynced"
        case .storeFailed: "storeFailed"
        case .checking: "checking"
        case .deviceOnly: "deviceOnly"
        case .syncing: "syncing"
        case .upToDate: "upToDate"
        case .paused(.storageFull): "storageFull"
        case .paused(.offline): "offline"
        case .paused(.signedOut): "signedOut"
        case .paused(.failed): "failed"
        }
    }

    // Whether a delete here also leaves iCloud and the other devices.
    var reachesICloud: Bool {
        switch self {
        case .syncing, .upToDate, .paused: true
        case .notSynced, .storeFailed, .checking, .deviceOnly: false
        }
    }
}
