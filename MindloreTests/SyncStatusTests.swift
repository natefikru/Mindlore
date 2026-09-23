import CloudKit
import Foundation
import SwiftData
import Testing
@testable import Mindlore

struct SyncStatusTests {
    private func derive(
        mirrors: Bool = true,
        storeFailed: Bool = false,
        account: SyncAccount? = .available,
        inFlight: Bool = false,
        lastSuccess: Date? = nil,
        lastProblem: SyncProblem? = nil
    ) -> SyncStatus {
        SyncStatus.derive(mirrors: mirrors, storeFailed: storeFailed, account: account, inFlight: inFlight, lastSuccess: lastSuccess, lastProblem: lastProblem)
    }

    @Test func aStoreThatDoesNotMirrorIsNeverAskedAbout() {
        #expect(derive(mirrors: false, account: nil) == .notSynced)
        #expect(derive(mirrors: false, account: .available, inFlight: true) == .notSynced)
    }

    @Test func aFailedStoreWinsOverEverything() {
        #expect(derive(storeFailed: true, inFlight: true) == .storeFailed)
    }

    @Test func theAccountDecidesBeforeAnyEvent() {
        #expect(derive(account: nil) == .checking)
        #expect(derive(account: .noAccount, inFlight: true) == .deviceOnly(.noAccount))
        #expect(derive(account: .restricted) == .deviceOnly(.restricted))
    }

    @Test func aProblemShowsUntilASuccessClearsIt() {
        #expect(derive(inFlight: true, lastProblem: .storageFull) == .paused(.storageFull))
        #expect(derive(lastProblem: .signedOut) == .deviceOnly(.noAccount))
        #expect(derive(inFlight: true) == .syncing)
        let last = Date(timeIntervalSince1970: 1_000)
        #expect(derive(lastSuccess: last) == .upToDate(lastSynced: last))
    }

    @Test func cloudKitErrorsBecomeProblemsWithoutText() {
        #expect(SyncProblem(CKError(.quotaExceeded)) == .storageFull)
        #expect(SyncProblem(CKError(.networkUnavailable)) == .offline)
        #expect(SyncProblem(URLError(.notConnectedToInternet)) == .offline)
        #expect(SyncProblem(CKError(.notAuthenticated)) == .signedOut)
        #expect(SyncProblem(CKError(.partialFailure)) == .failed("\(CKError.errorDomain) \(CKError.Code.partialFailure.rawValue)"))
    }

    @Test func everyStatusSaysWhereTheJournalIs() {
        let statuses: [SyncStatus] = [
            .notSynced, .storeFailed, .checking, .deviceOnly(.noAccount), .deviceOnly(.restricted),
            .deviceOnly(.temporarilyUnavailable), .syncing, .upToDate(lastSynced: nil), .upToDate(lastSynced: .now),
            .paused(.storageFull), .paused(.offline), .paused(.failed("x 1")),
        ]
        for status in statuses {
            #expect(!status.summary.isEmpty)
            #expect(status.explanation.contains("iPhone") || status.explanation.contains("iCloud"), "\(status.diagnosticName)")
            #expect(!status.explanation.contains("x 1"), "an error code reached the user")
        }
    }

    @Test func onlyAStoreThatReachesICloudWarnsThatDeletesGoThere() {
        #expect(SyncStatus.upToDate(lastSynced: nil).reachesICloud)
        #expect(SyncStatus.paused(.offline).reachesICloud)
        #expect(!SyncStatus.deviceOnly(.noAccount).reachesICloud)
        #expect(!SyncStatus.notSynced.reachesICloud)
    }
}

@MainActor
struct SyncStatusMonitorTests {
    private func event(_ id: UUID, ended: Date? = nil, succeeded: Bool = true, problem: SyncProblem? = nil) -> SyncStatusMonitor.Event {
        SyncStatusMonitor.Event(id: id, kind: .export, started: Date(timeIntervalSince1970: 0), ended: ended, succeeded: succeeded, problem: problem)
    }

    @Test func eventsMoveTheStatusThroughSyncingToUpToDate() async {
        let monitor = SyncStatusMonitor(mirrors: true, accountStatus: { .available })
        #expect(monitor.status == .checking)
        await monitor.refreshAccount()
        #expect(monitor.status == .upToDate(lastSynced: nil))

        let id = UUID()
        monitor.apply(event(id))
        #expect(monitor.status == .syncing)
        let done = Date(timeIntervalSince1970: 5)
        monitor.apply(event(id, ended: done))
        #expect(monitor.status == .upToDate(lastSynced: done))
    }

    @Test func aFailureHoldsUntilTheNextSuccess() async {
        let monitor = SyncStatusMonitor(mirrors: true, accountStatus: { .available })
        await monitor.refreshAccount()
        let first = UUID()
        monitor.apply(event(first))
        monitor.apply(event(first, ended: .now, succeeded: false, problem: .storageFull))
        #expect(monitor.status == .paused(.storageFull))

        let second = UUID()
        monitor.apply(event(second))
        #expect(monitor.status == .paused(.storageFull))
        let done = Date(timeIntervalSince1970: 9)
        monitor.apply(event(second, ended: done))
        #expect(monitor.status == .upToDate(lastSynced: done))
    }

    @Test func anAccountLookupThatThrowsIsUnknownNotAvailable() async {
        struct Failure: Error {}
        let monitor = SyncStatusMonitor(mirrors: true, accountStatus: { throw Failure() })
        await monitor.refreshAccount()
        #expect(monitor.status == .deviceOnly(.unknown))
    }

    @Test func aStoreThatDoesNotMirrorNeverLooksUpTheAccount() async {
        let monitor = SyncStatusMonitor(mirrors: false, accountStatus: {
            Issue.record("looked up the account for a store that doesn't mirror")
            return .available
        })
        monitor.start()
        #expect(monitor.status == .notSynced)
    }
}

// The real check on the schema: SwiftData refuses to open a CloudKit store whose models CloudKit
// can't hold, whatever CloudKitSchemaRules thinks. Needs the iCloud entitlement, which the app
// the tests run in carries; no account is needed to open the store.
@MainActor
struct CloudKitStoreTests {
    @Test func theAppSchemaOpensAsACloudKitStore() throws {
        let id = try #require(AppConfig.cloudKitContainerID)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let configuration = ModelConfiguration(schema: ModelContainerFactory.schema, url: folder.appendingPathComponent("cloud.store"), cloudKitDatabase: .private(id))
        let container = try ModelContainer(for: ModelContainerFactory.schema, configurations: [configuration])

        #expect(container.configurations.first?.cloudKitContainerIdentifier == id)
    }
}
