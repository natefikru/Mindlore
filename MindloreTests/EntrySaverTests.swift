import Foundation
import SwiftData
import Testing
@testable import Mindlore

struct SaveFailure: Error {}

// Changes made in one synchronous turn can't be interrupted by the scheduled save,
// so awaiting the scheduled task keeps these tests deterministic with a tiny interval.
@MainActor
final class SaverHarness {
    let container: ModelContainer
    var saveCount = 0
    var failNextSave = false
    var clock = Date(timeIntervalSince1970: 1_000)
    private(set) var saver: EntrySaver!

    var context: ModelContext { container.mainContext }

    init() throws {
        container = try ModelContainerFactory.make(.inMemory)
        saver = EntrySaver(
            context: container.mainContext,
            interval: .milliseconds(10),
            now: { [unowned self] in self.clock },
            save: { [unowned self] context in
                if self.failNextSave {
                    self.failNextSave = false
                    throw SaveFailure()
                }
                self.saveCount += 1
                try context.save()
            }
        )
    }

    func elapseInterval() async {
        await saver.scheduledSave?.value
    }

    func persistedTexts() throws -> [String] {
        let fresh = ModelContext(container)
        return try fresh.fetch(FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.createdAt)])).map(\.text)
    }
}

@MainActor
struct EntrySaverTests {
    @Test func disablesAutosaveOnItsContext() throws {
        let harness = try SaverHarness()
        #expect(harness.context.autosaveEnabled == false)
    }

    @Test func oneChangeSavesOnceAfterTheInterval() async throws {
        let harness = try SaverHarness()
        harness.context.insert(Entry(text: "hello"))
        harness.saver.noteChange()

        #expect(harness.saveCount == 0)
        await harness.elapseInterval()

        #expect(harness.saveCount == 1)
        #expect(try harness.persistedTexts() == ["hello"])
        #expect(harness.saver.scheduledSave == nil)
    }

    @Test func rapidChangesInsideOneIntervalProduceOneSave() async throws {
        let harness = try SaverHarness()
        let entry = Entry(text: "")
        harness.context.insert(entry)
        for character in "typing fast" {
            entry.text.append(character)
            harness.saver.noteChange()
        }

        await harness.elapseInterval()

        #expect(harness.saveCount == 1)
        #expect(try harness.persistedTexts() == ["typing fast"])
    }

    @Test func continuousTypingStillSavesEveryInterval() async throws {
        let harness = try SaverHarness()
        let entry = Entry(text: "")
        harness.context.insert(entry)

        for word in ["one ", "two ", "three "] {
            entry.text.append(word)
            harness.saver.noteChange()
            entry.text.append("more ")
            harness.saver.noteChange()
            await harness.elapseInterval()
        }

        #expect(harness.saveCount == 3)
        #expect(try harness.persistedTexts() == ["one more two more three more "])
    }

    // Changes keep arriving faster than the interval and the test never waits on the scheduled save.
    // A debounce would restart its timer every time and save nothing until typing stopped.
    @Test func savesDuringUninterruptedTypingNotOnlyAfterItStops() async throws {
        let harness = try SaverHarness()
        let entry = Entry(text: "")
        harness.context.insert(entry)

        for _ in 0..<40 {
            entry.text.append("a")
            harness.saver.noteChange()
            try await Task.sleep(for: .milliseconds(3))
        }
        let savesWhileTyping = harness.saveCount

        #expect(savesWhileTyping >= 2)
    }

    @Test func flushSavesImmediatelyAndCancelsTheScheduledSave() async throws {
        let harness = try SaverHarness()
        harness.context.insert(Entry(text: "leaving now"))
        harness.saver.noteChange()
        let scheduled = harness.saver.scheduledSave

        harness.saver.flush()

        #expect(harness.saveCount == 1)
        #expect(try harness.persistedTexts() == ["leaving now"])
        #expect(harness.saver.scheduledSave == nil)
        await scheduled?.value
        #expect(harness.saveCount == 1)
    }

    @Test func flushWithNothingPendingDoesNotSave() throws {
        let harness = try SaverHarness()
        harness.saver.flush()
        #expect(harness.saveCount == 0)
    }

    @Test func flushSavesChangesMadeWithoutNoteChange() throws {
        let harness = try SaverHarness()
        harness.context.insert(Entry(text: "inserted elsewhere"))

        harness.saver.flush()

        #expect(try harness.persistedTexts() == ["inserted elsewhere"])
    }

    @Test func saveStampsUpdatedAtOnEditedEntries() async throws {
        let harness = try SaverHarness()
        let entry = Entry(createdAt: Date(timeIntervalSince1970: 500), text: "first")
        harness.context.insert(entry)
        harness.saver.flush()
        #expect(entry.updatedAt == Date(timeIntervalSince1970: 500))

        harness.clock = Date(timeIntervalSince1970: 2_000)
        entry.text = "second"
        harness.saver.noteChange()
        await harness.elapseInterval()

        #expect(entry.updatedAt == Date(timeIntervalSince1970: 2_000))
    }

    @Test func failedSaveIsReportedAndRetriedOnTheNextChange() async throws {
        let harness = try SaverHarness()
        harness.failNextSave = true
        harness.context.insert(Entry(text: "keep me"))
        harness.saver.noteChange()
        await harness.elapseInterval()

        #expect(harness.saver.lastError is SaveFailure)
        #expect(try harness.persistedTexts() == [])

        harness.saver.noteChange()
        await harness.elapseInterval()

        #expect(harness.saver.lastError == nil)
        #expect(try harness.persistedTexts() == ["keep me"])
    }

    @Test func deletionIsSavedOnFlush() throws {
        let harness = try SaverHarness()
        let entry = Entry(text: "delete me")
        harness.context.insert(entry)
        harness.saver.flush()

        Entry.delete(entry, in: harness.context)
        harness.saver.flush()

        #expect(try harness.persistedTexts() == [])
    }
}
