import Foundation
import SwiftData
import Testing
@testable import Mindlore

@MainActor
struct StoreTests {
    @Test func repairResetsADriftedDateTheUserNeverPicked() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let drifted = Entry(createdAt: Date(timeIntervalSince1970: 1_000_000), text: "drifted")
        drifted.entryDate = Date(timeIntervalSince1970: 42)
        context.insert(drifted)
        try context.save()

        #expect(try EntryDateRepair.run(in: context) == 1)
        #expect(drifted.entryDate == drifted.createdAt)
        #expect(try EntryDateRepair.run(in: context) == 0)
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
            let entity = Entity(name: "Sarah Kim", key: "sarah kim", kind: .person)
            context.insert(entity)
            let link = EntityLink(surface: "Sarah", kind: .person)
            context.insert(link)
            link.attach(to: entry, entity: entity)
            try context.save()
            #expect(try context.fetchCount(FetchDescriptor<EntryPage>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<EntryInsights>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<EntityLink>()) == 1)

            Entry.delete(entry, in: context)
            try context.save()
        }

        let reopened = try ModelContainerFactory.make(.file(url))
        #expect(try reopened.mainContext.fetchCount(FetchDescriptor<Entry>()) == 0)
        #expect(try reopened.mainContext.fetchCount(FetchDescriptor<EntryPage>()) == 0)
        #expect(try reopened.mainContext.fetchCount(FetchDescriptor<EntryInsights>()) == 0)
        // The link went with the entry; the entity is its own record and stays.
        #expect(try reopened.mainContext.fetchCount(FetchDescriptor<EntityLink>()) == 0)
        #expect(try reopened.mainContext.fetchCount(FetchDescriptor<Entity>()) == 1)
    }
}
