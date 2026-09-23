import Foundation
import SwiftData
import Testing
@testable import Mindlore

// The safety copy stands between a user and a journal CloudKit mirroring has purged, so every
// rule it follows is pinned here: what gets copied, what a delete removes, when a restore is
// offered and when it must not be, and that a restore followed by iCloud's own copy ends as one
// entry.
@MainActor
final class SafetyCopyTests {
    let container: ModelContainer
    let context: ModelContext
    let folder: URL
    let backups: EntryBackups
    let defaults: UserDefaults
    let suite = "safety-\(UUID().uuidString)"

    init() throws {
        container = try ModelContainerFactory.make(.inMemory)
        context = container.mainContext
        folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        backups = EntryBackups(folder: folder)
        defaults = UserDefaults(suiteName: suite)!
        EntryBackups.register(backups, for: container)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
        UserDefaults().removePersistentDomain(forName: suite)
    }

    private func recovery() -> JournalRecovery {
        JournalRecovery(backups: backups, defaults: defaults, observesResets: false)
    }

    @discardableResult
    private func write(_ text: String, title: String = "") throws -> Entry {
        let entry = Entry(text: text)
        entry.title = title
        context.insert(entry)
        try context.saveStampingEntries()
        return entry
    }

    @Test func aSaveCopiesTheEntryAndAnEditRewritesIt() throws {
        let entry = try write("First draft")
        #expect(backups.all().map(\.text) == ["First draft"])

        entry.text = "Second draft"
        try context.saveStampingEntries()
        #expect(backups.all().map(\.text) == ["Second draft"])
    }

    @Test func theSaverCopiesToo() async throws {
        let saver = EntrySaver(context: context, interval: .milliseconds(10))
        let entry = Entry(text: "Typed in the editor")
        context.insert(entry)
        saver.noteChange()
        saver.flush()
        #expect(backups.storedIDs() == [entry.id])
    }

    @Test func aBlankEntryIsNotCopied() throws {
        try write("   ")
        #expect(backups.storedIDs().isEmpty)
    }

    @Test func deletingAnEntryDeletesItsCopy() throws {
        let entry = try write("Soon gone")
        Entry.delete(entry, in: context)
        try context.saveStampingEntries()
        #expect(backups.storedIDs().isEmpty)
    }

    @Test func deleteAllDataDeletesEveryCopy() throws {
        try write("One")
        try write("Two")
        try JournalWipe.deleteEverything(in: context)
        #expect(backups.storedIDs().isEmpty)
    }

    @Test func launchFillsInEntriesThatHaveNoCopy() throws {
        EntryBackups.register(nil, for: container)
        context.insert(Entry(text: "Written before the safety copy existed"))
        try context.save()
        EntryBackups.register(backups, for: container)
        #expect(backups.storedIDs().isEmpty)

        #expect(try backups.fillIn(from: context) == 1)
        #expect(try backups.fillIn(from: context) == 0)
    }

    @Test func aRestoreBringsBackWordsDatesAndKindUnderTheSameID() throws {
        let entry = try write("Walked by the river", title: "River")
        entry.isNote = true
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        entry.entryDate = day
        entry.entryDateIsDayOnly = true
        try context.saveStampingEntries()
        let id = entry.id

        // What a purge does: the entry leaves the store without the app deleting it.
        EntryBackups.register(nil, for: container)
        context.delete(entry)
        try context.save()
        EntryBackups.register(backups, for: container)

        let recovery = recovery()
        recovery.markPending("test")
        recovery.check(in: context, status: .upToDate(lastSynced: nil))
        #expect(recovery.missing.map(\.id) == [id])
        #expect(recovery.showsBanner)

        recovery.restoreAll(in: context)
        let back = try #require(try context.fetch(FetchDescriptor<Entry>()).first)
        #expect(back.id == id && back.text == "Walked by the river" && back.title == "River")
        #expect(back.isNote && back.entryDateIsDayOnly && back.entryDate == day)
        #expect(recovery.missing.isEmpty && !recovery.isPending)
    }

    @Test func nothingIsOfferedWhileSyncIsStillBringingEntriesIn() throws {
        let entry = try write("Arriving")
        EntryBackups.register(nil, for: container)
        context.delete(entry)
        try context.save()

        let recovery = recovery()
        recovery.markPending("test")
        recovery.check(in: context, status: .syncing)
        #expect(recovery.missing.isEmpty)
    }

    @Test func anEntryDeletedOnAnotherDeviceIsDroppedNotOffered() throws {
        try write("Kept")
        let elsewhere = try write("Deleted on the iPad")
        // A remote delete arrives through the store, not through this app's delete path.
        EntryBackups.register(nil, for: container)
        context.delete(elsewhere)
        try context.save()

        let recovery = recovery()
        recovery.check(in: context, status: .upToDate(lastSynced: nil))
        #expect(recovery.missing.isEmpty)
        #expect(backups.storedIDs().count == 1)
    }

    @Test func anEmptyStoreWithCopiesIsAlwaysOffered() throws {
        let entry = try write("The only entry")
        EntryBackups.register(nil, for: container)
        context.delete(entry)
        try context.save()

        let recovery = recovery()
        recovery.check(in: context, status: .upToDate(lastSynced: nil))
        #expect(recovery.isPending)
        #expect(recovery.missing.count == 1)
    }

    @Test func theAccountChangingOrGoingAwayMarksARecoveryCheck() {
        let first = recovery()
        first.accountSeen(recordName: "_abc")
        #expect(!first.isPending, "the first account is only remembered")
        first.accountSeen(recordName: "_abc")
        #expect(!first.isPending)
        first.accountSeen(recordName: nil)
        #expect(first.isPending)

        defaults.set(false, forKey: JournalRecovery.pendingKey)
        first.accountSeen(recordName: "_other")
        #expect(first.isPending)
    }

    @Test func theFingerprintNeverHoldsTheRecordName() throws {
        let print = try #require(JournalRecovery.fingerprint(of: "_secret-record-name"))
        #expect(!print.contains("secret"))
        #expect(print.count == 64)
    }

    @Test func aRestoreFollowedByICloudsCopyEndsAsOneEntry() throws {
        let original = try write("Same entry twice")
        let twin = Entry.restored(from: EntryBackups.snapshot(original))
        twin.updatedAt = original.updatedAt.addingTimeInterval(-60)
        context.insert(twin)
        try context.save()

        #expect(try EntryDuplicates.merge(in: context) == 1)
        let left = try context.fetch(FetchDescriptor<Entry>())
        #expect(left.count == 1 && left[0] === original)
        #expect(backups.storedIDs() == [original.id])
    }

    @Test func aStoreThatNeverSyncsIsNeverChecked() throws {
        let entry = try write("Demo")
        EntryBackups.register(nil, for: container)
        context.delete(entry)
        try context.save()

        let disabled = JournalRecovery(backups: backups, enabled: false, defaults: defaults, observesResets: false)
        disabled.markPending("test")
        disabled.check(in: context, status: .upToDate(lastSynced: nil))
        #expect(disabled.missing.isEmpty)
    }
}
