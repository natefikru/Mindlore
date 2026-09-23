import Foundation
import SwiftData
import Testing
@testable import Mindlore

// A name the insights missed, added to one entry by hand from its menu.
@MainActor
struct AddNameTests {
    let harness: GraphHarness
    let services = GraphServices(diagnostics: .disabled)

    init() throws {
        harness = try GraphHarness()
    }

    private func plainEntry(_ text: String = "Coffee with Maya by the river.") throws -> Entry {
        let entry = Entry(text: text)
        harness.context.insert(entry)
        try harness.context.save()
        return entry
    }

    @Test func aNewNameBecomesAnEntityTheEntryMentions() throws {
        let entry = try plainEntry()

        let id = try #require(services.addName(.new(name: "  Maya ", kind: .person), to: entry, in: harness.context))

        let maya = try harness.entity("Maya")
        #expect(maya.id == id)
        #expect(maya.kind == .person)
        #expect(maya.linkCount == 1)
        let links = harness.links(of: entry)
        #expect(links.count == 1)
        #expect(links[0].source == .user)
        #expect(links[0].entityID == id)
        #expect(services.revision == 1)
    }

    @Test func aBlankNameAddsNothing() throws {
        let entry = try plainEntry()

        #expect(services.addName(.new(name: "   ", kind: .person), to: entry, in: harness.context) == nil)
        #expect(try harness.entities().isEmpty)
        #expect(services.revision == 0)
    }

    @Test func aNameSomethingAlreadyAnswersToLandsThere() throws {
        let other = try harness.entry(mentions: [("Sarah", .person)])
        services.insightsWritten(for: other, in: harness.context)
        try harness.context.save()
        let entry = try plainEntry()

        services.addName(.new(name: "sarah", kind: .person), to: entry, in: harness.context)

        #expect(try harness.entities().map(\.name) == ["Sarah"])
        #expect(try harness.entity("Sarah").linkCount == 2)
    }

    @Test func anEntityPickedFromTheListIsLinkedByID() throws {
        let other = try harness.entry(mentions: [("Harbor Cafe", .place)])
        services.insightsWritten(for: other, in: harness.context)
        try harness.context.save()
        let cafe = try harness.entity("Harbor Cafe")
        let entry = try plainEntry()

        #expect(services.addName(.existing(cafe.id), to: entry, in: harness.context) == cafe.id)
        #expect(harness.links(of: entry).map(\.surface) == ["Harbor Cafe"])
        #expect(cafe.linkCount == 2)
    }

    // "#river" typed into the entry: a user link on a tag entity, remembering the "#" it was
    // written with, so read mode can find and tint it.
    @Test func aTypedTagBecomesAUserLinkOnATagEntity() throws {
        let entry = try plainEntry("Walked by the #river again.")

        let id = try #require(services.addName(.tag("river"), to: entry, in: harness.context))

        let river = try harness.entity("river")
        #expect(river.id == id)
        #expect(river.kind == .tag)
        let links = harness.links(of: entry)
        #expect(links.count == 1)
        #expect(links[0].source == .user)
        #expect(links[0].kind == .tag)
        #expect(links[0].writtenSurface == "#river")
        // Read mode links it as written, "#river", and never the bare word.
        let candidates = EntryNameLinks.candidates(forEntry: entry.id, links: links, entities: [river])
        #expect(candidates.map(\.names) == [["#river"]])
        #expect(EntryNameLinks.links(in: entry.text, candidates: candidates).map(\.range) == [NSRange(location: 14, length: 6)])

        // The same tag again, from another entry, lands on the same entity.
        let other = try plainEntry("The #River in spring.")
        #expect(services.addName(.tag("River"), to: other, in: harness.context) == id)
        #expect(try harness.entity("river").linkCount == 2)
    }

    @Test func addingTheSameNameTwiceKeepsOneLink() throws {
        let entry = try plainEntry()

        services.addName(.new(name: "Maya", kind: .person), to: entry, in: harness.context)
        services.addName(.new(name: "Maya", kind: .person), to: entry, in: harness.context)

        #expect(harness.links(of: entry).count == 1)
        #expect(try harness.entity("Maya").linkCount == 1)
    }

    @Test func aHiddenEntityAddedByNameComesBackIntoView() throws {
        let hidden = Entity(name: "Maya", key: EntityNormalizer.key(for: "Maya", kind: .person), kind: .person)
        hidden.hidden = true
        harness.context.insert(hidden)
        try harness.context.save()
        let entry = try plainEntry()

        #expect(services.addName(.new(name: "Maya", kind: .person), to: entry, in: harness.context) == hidden.id)
        #expect(!hidden.hidden)
    }

    @Test func theAddedNameSurvivesInsightsRunningAgain() throws {
        let entry = try harness.entry("Coffee with Maya and Sam.", mentions: [("Sam", .person)])
        services.insightsWritten(for: entry, in: harness.context)
        try harness.context.save()
        services.addName(.new(name: "Maya", kind: .person), to: entry, in: harness.context)

        // Generate again: the AI links are rebuilt from scratch.
        entry.insights?.generatedAt = Date(timeIntervalSince1970: 2_000)
        services.insightsWritten(for: entry, in: harness.context)
        try harness.context.save()

        #expect(Set(harness.links(of: entry).map(\.surface)) == ["Maya", "Sam"])
        #expect(try harness.entity("Maya").linkCount == 1)
    }

    @Test func anEntryWithoutInsightsKeepsItThroughTheSweep() throws {
        let entry = try plainEntry()
        services.addName(.new(name: "Maya", kind: .person), to: entry, in: harness.context)

        harness.indexer.sweep(in: harness.context)

        #expect(harness.links(of: entry).count == 1)
        #expect(try harness.entity("Maya").linkCount == 1)
    }

    @Test func aLaterAIMentionOfTheSameNameIsClaimedNotDoubled() throws {
        let entry = try harness.entry("Coffee with Maya.")
        services.insightsWritten(for: entry, in: harness.context)
        try harness.context.save()
        services.addName(.new(name: "Maya", kind: .person), to: entry, in: harness.context)

        entry.insights?.mentions = [Mention(name: "Maya", kindRaw: MentionKind.person.rawValue)]
        entry.insights?.generatedAt = Date(timeIntervalSince1970: 2_000)
        services.insightsWritten(for: entry, in: harness.context)
        try harness.context.save()

        #expect(harness.links(of: entry).count == 1)
        #expect(harness.links(of: entry)[0].source == .user)
        // The insights account for it now, so it shows among the mentions, not twice.
        #expect(services.addedNames(for: entry, in: harness.context).isEmpty)
    }

    @Test func addedNamesListsOnlyWhatTheInsightsDoNotAccountFor() throws {
        let entry = try harness.entry("Maya and Lewis.", mentions: [("Lewis", .person)])
        services.insightsWritten(for: entry, in: harness.context)
        try harness.context.save()
        // A corrected mention is the user's link too, but it is still one of the mentions.
        _ = services.repoint(MentionRef(entryID: entry.id, surface: "Lewis", kind: .person), to: .new(name: "Louis"), addingAlias: false, in: harness.context)
        services.addName(.new(name: "Maya", kind: .person), to: entry, in: harness.context)

        let added = services.addedNames(for: entry, in: harness.context)

        #expect(added.map(\.name) == ["Maya"])
        #expect(added[0].kind == .person)
    }

    @Test func removingANewNameLeavesNothingBehind() throws {
        let entry = try plainEntry()
        let id = try #require(services.addName(.new(name: "Maya", kind: .person), to: entry, in: harness.context))

        services.removeAddedName(id, from: entry, in: harness.context)

        #expect(harness.links(of: entry).isEmpty)
        #expect(try harness.entities().isEmpty)
        #expect(services.addedNames(for: entry, in: harness.context).isEmpty)
    }

    @Test func removingKeepsAnEntityOtherEntriesMention() throws {
        let other = try harness.entry(mentions: [("Sarah", .person)])
        services.insightsWritten(for: other, in: harness.context)
        try harness.context.save()
        let entry = try plainEntry()
        let id = try #require(services.addName(.new(name: "Sarah", kind: .person), to: entry, in: harness.context))

        services.removeAddedName(id, from: entry, in: harness.context)

        #expect(harness.links(of: entry).isEmpty)
        #expect(try harness.entity("Sarah").linkCount == 1)
        #expect(harness.links(of: other).count == 1)
    }

    @Test func removingNeverTakesAnAIMention() throws {
        let entry = try harness.entry(mentions: [("Sarah", .person)])
        services.insightsWritten(for: entry, in: harness.context)
        try harness.context.save()
        let sarah = try harness.entity("Sarah")

        services.removeAddedName(sarah.id, from: entry, in: harness.context)

        #expect(harness.links(of: entry).count == 1)
    }

    @Test func addingDoesNotMoveTheEntrysUpdatedAt() throws {
        let entry = try plainEntry()
        let before = entry.updatedAt

        services.addName(.new(name: "Maya", kind: .person), to: entry, in: harness.context)

        #expect(entry.updatedAt == before)
    }
}
