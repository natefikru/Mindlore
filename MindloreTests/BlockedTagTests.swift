import Foundation
import SwiftData
import Testing
@testable import Mindlore

@MainActor
struct BlockedTagTests {
    @Test func everySpellingOfLooseEndsIsBlockedAndNothingElse() {
        for tag in ["loose ends", "Loose-ends", "loose_end", "LOOSE ENDS", "looseends", "loose-end"] {
            #expect(InsightsPromptBuilder.isBlockedTag(tag), "\(tag)")
        }
        for tag in ["loose", "ends", "running", "loose threads", "dead ends"] {
            #expect(!InsightsPromptBuilder.isBlockedTag(tag), "\(tag)")
        }
    }

    @Test func theSweepTakesItOutOfEntriesPartsAndTheMap() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        defer { withExtendedLifetime(container) {} }
        let entry = Entry(text: "Groceries and a call to make")
        context.insert(entry)
        let insights = EntryInsights()
        insights.tags = ["groceries", "loose-ends"]
        insights.sections = [EntrySection(topic: "Errands", tags: ["loose ends", "errands"])]
        entry.insights = insights
        let blocked = Entity(name: "loose ends", key: "loose ends", kind: .tag)
        let kept = Entity(name: "groceries", key: "groceries", kind: .tag)
        context.insert(blocked)
        context.insert(kept)
        let blockedLink = EntityLink(surface: "loose ends", kind: .tag)
        blockedLink.entityID = blocked.id
        blockedLink.entryID = entry.id
        let keptLink = EntityLink(surface: "groceries", kind: .tag)
        keptLink.entityID = kept.id
        keptLink.entryID = entry.id
        context.insert(blockedLink)
        context.insert(keptLink)
        try context.save()

        #expect(BlockedTagSweep.run(in: context) > 0)
        try context.save()

        #expect(insights.tags == ["groceries"])
        #expect(insights.sections.first?.tags == ["errands"])
        let entities = try context.fetch(FetchDescriptor<Entity>())
        #expect(entities.map(\.name) == ["groceries"])
        let links = try context.fetch(FetchDescriptor<EntityLink>())
        #expect(links.map(\.entityID) == [kept.id])
        #expect(BlockedTagSweep.run(in: context) == 0, "nothing left to do the second time")
    }
}
