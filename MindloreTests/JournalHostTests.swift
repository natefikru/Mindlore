import Foundation
import SwiftData
import Testing
@testable import Mindlore

@MainActor
struct JournalHostTests {
    struct Refused: Error {}

    private let defaults: UserDefaults
    private let folder: URL

    init() {
        let suite = "JournalHostTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
    }

    // Records whether each open asked for CloudKit; always opens in memory.
    final class Opener {
        var calls: [Bool] = []
        var refuseCloudKit = false
        var prepared = 0

        func open(_ cloudKit: Bool) throws -> ModelContainer {
            calls.append(cloudKit)
            if cloudKit, refuseCloudKit { throw Refused() }
            return try ModelContainerFactory.make(.inMemory)
        }
    }

    private func host(isJournal: Bool = true, opener: Opener, mirror: MirroredKeyValueStore? = nil, diagnostics: DiagnosticsLog = .shared) -> JournalHost {
        JournalHost(
            isJournal: isJournal,
            recovery: JournalRecovery(backups: EntryBackups(folder: folder), enabled: false, defaults: defaults, observesResets: false),
            settingsMirror: mirror,
            defaults: defaults,
            diagnostics: diagnostics,
            releaseTimeout: .seconds(2),
            openStore: opener.open,
            prepare: { _ in opener.prepared += 1 }
        )
    }

    private func status(_ host: JournalHost) -> SyncStatus? {
        if case .open(let journal) = host.phase { journal.sync.status } else { nil }
    }

    private func generation(_ host: JournalHost) -> Int? {
        if case .open(let journal) = host.phase { journal.generation } else { nil }
    }

    @Test func theJournalSyncsUntilTheSwitchSaysOtherwise() {
        let opener = Opener()
        let journal = host(opener: opener)

        #expect(opener.calls == [true])
        #expect(journal.syncOn)
        #expect(opener.prepared == 1)
        #expect(status(journal) == .checking)
    }

    @Test func aJournalSwitchedOffOpensWithoutCloudKit() {
        SyncSwitch.set(false, in: defaults)
        let opener = Opener()
        let journal = host(opener: opener)

        #expect(opener.calls == [false])
        #expect(status(journal) == .off)
    }

    @Test func aStoreThatIsNotTheJournalNeverSyncsOrSwitches() {
        let opener = Opener()
        let other = host(isJournal: false, opener: opener)

        other.requestSync(false)

        #expect(opener.calls == [false])
        #expect(status(other) == .notSynced)
        #expect(!other.hasPendingSwitch)
        #expect(SyncSwitch.isOn(in: defaults))
    }

    @Test func aStoreThatWontOpenWithCloudKitOpensHere() {
        let opener = Opener()
        opener.refuseCloudKit = true
        let journal = host(opener: opener)

        #expect(opener.calls == [true, false])
        #expect(status(journal) == .storeFailed)
    }

    @Test func theSwitchIsSavedAtOnceAndAppliedLater() async throws {
        let opener = Opener()
        let file = DiagnosticsFile()
        let journal = host(opener: opener, diagnostics: DiagnosticsLog(fileURL: file.url))

        journal.requestSync(false)
        #expect(!SyncSwitch.isOn(in: defaults))
        #expect(journal.hasPendingSwitch)
        #expect(opener.calls == [true])
        #expect(generation(journal) == 1)

        await journal.applyPendingSwitch()

        #expect(opener.calls == [true, false])
        #expect(generation(journal) == 2)
        #expect(opener.prepared == 2)
        #expect(!journal.hasPendingSwitch)
        #expect(status(journal) == .off)
        let switched = try #require(try file.events().first { $0["event"] as? String == "sync.switched" })
        #expect(switched["on"] as? Bool == false)
        // Nothing else held the old container, so it was gone before the new one opened.
        #expect(switched["released"] as? Bool == true)
    }

    @Test func switchingBackBeforeItAppliesIsNoSwitch() async {
        let opener = Opener()
        let journal = host(opener: opener)

        journal.requestSync(false)
        journal.requestSync(true)
        await journal.applyPendingSwitch()

        #expect(!journal.hasPendingSwitch)
        #expect(opener.calls == [true])
        #expect(generation(journal) == 1)
    }

    @Test func aChoiceNotAppliedBeforeAKillHoldsAtNextLaunch() {
        let first = host(opener: Opener())
        first.requestSync(false)

        let opener = Opener()
        let relaunched = host(opener: opener)

        #expect(opener.calls == [false])
        #expect(!relaunched.hasPendingSwitch)
    }

    @Test func theSettingsMirrorFollowsTheSwitch() async {
        let cloud = FakeCloudKeyValues()
        let local = FakeKeyValueStore()
        let mirror = MirroredKeyValueStore(local: local, cloud: cloud, keys: ["shared"], isEnabled: true)
        let journal = host(opener: Opener(), mirror: mirror)

        journal.requestSync(false)
        await journal.applyPendingSwitch()
        mirror.set("mine", forKey: "shared")
        #expect(cloud.values["shared"] == nil)

        cloud.values["shared"] = "theirs"
        journal.requestSync(true)
        await journal.applyPendingSwitch()
        #expect(mirror.isEnabled)
        #expect(local.values["shared"] as? String == "theirs")
    }
}
