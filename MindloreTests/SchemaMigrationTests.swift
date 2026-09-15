import Foundation
import SwiftData
import Testing
@testable import Mindlore

// Fixtures/v1-store.bundle was written by the app before entry dates, pages, and insights existed.
// Opening a copy proves the lightweight migration keeps real user data.
@MainActor
struct SchemaMigrationTests {
    private final class BundleToken {}

    // Bundled as an opaque .bundle so its hidden external-storage folder is copied intact.
    // Reading it from the source tree would hang: the simulator can't read ~/Documents.
    private static var fixtureDirectory: URL {
        Bundle(for: BundleToken.self).url(forResource: "v1-store", withExtension: "bundle")!
    }

    private func copyOfFixture() throws -> (store: URL, cleanup: () -> Void) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.copyItem(at: Self.fixtureDirectory, to: directory)
        return (directory.appendingPathComponent("entries.store"), { try? FileManager.default.removeItem(at: directory) })
    }

    private func date(_ string: String) throws -> Date {
        try Date(string, strategy: .iso8601)
    }

    @Test func existingEntriesSurviveTheNewSchema() throws {
        let fixture = try copyOfFixture()
        defer { fixture.cleanup() }
        let container = try ModelContainerFactory.make(.file(fixture.store))
        let entries = try container.mainContext.fetch(FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.createdAt)]))

        try #require(entries.count == 3)
        let typed = entries[0], voice = entries[1], awaiting = entries[2]

        #expect(typed.id == UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        #expect(typed.source == .typed)
        #expect(typed.text == "Typed fixture entry")
        #expect(typed.createdAt == (try date("2026-09-01T09:15:00Z")))
        #expect(typed.updatedAt == (try date("2026-09-01T09:16:00Z")))

        #expect(voice.source == .voice)
        #expect(voice.text == "Voice fixture entry")
        #expect(voice.textWasGenerated)
        #expect(!voice.awaitingText)
        #expect(voice.audioData == Data(repeating: 0xA5, count: 300_000))
        #expect(voice.audioDuration == 12.5)

        #expect(awaiting.awaitingText)
        #expect(awaiting.audioData?.count == 150_000)
        #expect(awaiting.audioDuration == 4.0)

        for entry in entries {
            #expect(entry.title == "")
            #expect(!entry.entryDateIsDayOnly)
            #expect(entry.suggestedEntryDate == nil)
            #expect(!entry.automaticAIPassUsed)
            #expect(!entry.isDraft)
            #expect(!entry.titlePending && !entry.insightsPending)
            #expect(entry.textAttempts == 0 && entry.textFailureRaw == nil)
            #expect(entry.pages?.isEmpty ?? true)
            #expect(entry.insights == nil)
        }
    }

    @Test func repairSetsEveryMigratedEntryDateToItsCreationTime() throws {
        let fixture = try copyOfFixture()
        defer { fixture.cleanup() }

        do {
            let container = try ModelContainerFactory.make(.file(fixture.store))
            let repaired = try EntryDateRepair.run(in: container.mainContext)
            #expect(repaired == 3)
        }

        // Reopen to prove the repair was saved, and that a second run has nothing to do.
        let reopened = try ModelContainerFactory.make(.file(fixture.store))
        let entries = try reopened.mainContext.fetch(FetchDescriptor<Entry>())
        #expect(entries.allSatisfy { $0.entryDate == $0.createdAt })
        #expect(try EntryDateRepair.run(in: reopened.mainContext) == 0)
    }

    @Test func repairLeavesDaysTheUserPickedAlone() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let picked = Entry(createdAt: Date(timeIntervalSince1970: 1_000_000), text: "backdated")
        picked.entryDate = Date(timeIntervalSince1970: 5_000)
        picked.entryDateIsDayOnly = true
        let untouched = Entry(createdAt: Date(timeIntervalSince1970: 2_000_000), text: "new")
        context.insert(picked)
        context.insert(untouched)
        try context.save()

        #expect(try EntryDateRepair.run(in: context) == 0)
        #expect(picked.entryDate == Date(timeIntervalSince1970: 5_000))
        #expect(untouched.entryDate == untouched.createdAt)
    }

    @Test func deletingAnEntryDeletesItsPagesAndInsightsFromAFileStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("entries.store")

        do {
            let container = try ModelContainerFactory.make(.file(url))
            let context = container.mainContext
            let entry = Entry(source: .photo)
            context.insert(entry)
            let page = EntryPage(index: 0, imageData: Data(repeating: 1, count: 200_000), thumbnailData: Data([1, 2]), pixelWidth: 10, pixelHeight: 20, origin: .library)
            page.entry = entry
            let insights = EntryInsights(modelUsed: "test")
            insights.entry = entry
            try context.save()
            #expect(try context.fetchCount(FetchDescriptor<EntryPage>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<EntryInsights>()) == 1)

            Entry.delete(entry, in: context)
            try context.save()
        }

        let reopened = try ModelContainerFactory.make(.file(url))
        #expect(try reopened.mainContext.fetchCount(FetchDescriptor<Entry>()) == 0)
        #expect(try reopened.mainContext.fetchCount(FetchDescriptor<EntryPage>()) == 0)
        #expect(try reopened.mainContext.fetchCount(FetchDescriptor<EntryInsights>()) == 0)
    }
}
