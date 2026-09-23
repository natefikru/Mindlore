import Foundation
import SwiftData
import Testing
@testable import Mindlore

// The repair must write only links that are actually empty. A version that matched every link
// rewrote all 56 of the owner's on each launch and sent them all to iCloud again.
@MainActor
struct EntityLinkRepairTests {
    @Test func fillsAnEmptyLinkFromItsIDAndThenHasNothingToDo() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let entry = Entry(text: "Lunch with Maya")
        let maya = Entity(name: "Maya", key: "maya", kind: .person)
        let filled = EntityLink(surface: "Maya", kind: .person)
        filled.attach(to: entry, entity: maya)
        let empty = EntityLink(surface: "Maya", kind: .person)
        empty.entry = entry
        empty.entryID = entry.id
        empty.entityID = maya.id
        context.insert(entry)
        context.insert(maya)
        context.insert(filled)
        context.insert(empty)
        try context.save()

        #expect(try EntityLinkRepair.run(in: context) == 1)
        #expect(empty.linkedEntity === maya)
        #expect(!context.hasChanges)
        #expect(try EntityLinkRepair.run(in: context) == 0)
    }

    @Test func aLinkWhoseEntityIsGoneStaysEmpty() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let orphan = EntityLink(surface: "Someone", kind: .person)
        orphan.entityID = UUID()
        context.insert(orphan)
        try context.save()

        #expect(try EntityLinkRepair.run(in: context) == 0)
        #expect(orphan.linkedEntity == nil)
    }
}
