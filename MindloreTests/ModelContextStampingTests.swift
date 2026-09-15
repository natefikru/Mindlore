import Foundation
import SwiftData
import Testing
@testable import Mindlore

@MainActor
struct ModelContextStampingTests {
    @Test func savingStampsEditedEntriesAndLeavesNewOnesAlone() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let edited = Entry(createdAt: Date(timeIntervalSince1970: 100), text: "before")
        context.insert(edited)
        try context.save()

        edited.text = "after"
        let inserted = Entry(createdAt: Date(timeIntervalSince1970: 200), text: "new")
        context.insert(inserted)
        try context.saveStampingEntries(at: Date(timeIntervalSince1970: 5_000))

        #expect(edited.updatedAt == Date(timeIntervalSince1970: 5_000))
        #expect(inserted.updatedAt == Date(timeIntervalSince1970: 200))
    }

    @Test func unchangedEntriesKeepTheirTimestamp() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let untouched = Entry(createdAt: Date(timeIntervalSince1970: 100), text: "same")
        let edited = Entry(createdAt: Date(timeIntervalSince1970: 100), text: "before")
        context.insert(untouched)
        context.insert(edited)
        try context.save()

        edited.text = "after"
        try context.saveStampingEntries(at: Date(timeIntervalSince1970: 5_000))

        #expect(untouched.updatedAt == Date(timeIntervalSince1970: 100))
    }
}
