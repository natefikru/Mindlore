import Foundation
import SwiftData
import Testing
@testable import Mindlore

struct EntityChipIndexTests {
    private let sarah = UUID()

    private func link(_ surface: String, _ kind: EntityKind, _ id: UUID, inferred: Bool = false, hidden: Bool = false) -> EntityChipIndex.LinkInput {
        .init(surface: surface, kind: kind, entityID: id, inferred: inferred, entityHidden: hidden)
    }

    @Test func looksUpByKindExactWordsFirst() {
        let place = UUID()
        let index = EntityChipIndex(links: [link("Paris", .person, sarah), link("Paris", .place, place)])

        #expect(index.chip(for: "Paris", kind: .person)?.entityID == sarah)
        #expect(index.chip(for: "Paris", kind: .place)?.entityID == place)
        #expect(index.chip(for: "Paris", kind: .tag) == nil)
    }

    @Test func fallsBackToTheNormalizedKey() {
        let index = EntityChipIndex(links: [link("Sarah's", .person, sarah)])
        #expect(index.chip(for: "sarah", kind: .person)?.entityID == sarah)
        #expect(index.chip(for: "sarah", kind: .person)?.surface == "Sarah's", "a correction looks the link up by its own words")
    }

    @Test func hiddenEntitiesOpenNothing() {
        let index = EntityChipIndex(links: [link("Sarah", .person, sarah, hidden: true)])
        #expect(index.chip(for: "Sarah", kind: .person) == nil)
    }

    @Test func aGuessSaysSo() {
        let index = EntityChipIndex(links: [link("sarah", .person, sarah, inferred: true)])
        #expect(index.chip(for: "sarah", kind: .person) == .init(entityID: sarah, guessed: true, surface: "sarah"))
    }

    @Test func aValueWithNoLinkHasNoChip() {
        #expect(EntityChipIndex.empty.chip(for: "Sarah", kind: .person) == nil)
        #expect(EntityChipIndex(links: [link("Sarah", .person, sarah)]).chip(for: "", kind: .person) == nil)
    }
}

// The index as the insights sheet builds it, from real links.
@MainActor
struct EntityChipIndexStoreTests {
    let harness: BioHarness
    var services: GraphServices { harness.services }

    init() throws {
        harness = try BioHarness()
    }

    @Test func aTagThemeAndNameEachOpenTheirEntity() throws {
        let entry = try harness.entry("A walk with Sarah.", mentions: [("Sarah", .person)], tags: ["river"])
        entry.insights?.themes = ["a walk"]
        entry.insights?.generatedAt = Date(timeIntervalSince1970: 3_000)
        try harness.context.save()
        harness.graph.indexer.sweep(in: harness.context)

        let index = services.chipIndex(for: entry.id, in: harness.context)

        #expect(index.chip(for: "Sarah", kind: .person)?.entityID == (try harness.entity("Sarah")).id)
        #expect(index.chip(for: "river", kind: .tag)?.entityID == (try harness.entity("river")).id)
        #expect(index.chip(for: "a walk", kind: .theme)?.entityID == (try harness.entity("a walk")).id)
    }

    // A dictated lowercase first name, kept as written, is linked to the full name by guessing.
    @Test func aGroundedLowercaseNameOpensTheGuessedPerson() throws {
        try harness.entry("Sarah Kim called.", mentions: [("Sarah Kim", .person)])
        let entry = try harness.entry("sarah came by.", mentions: [("sarah", .person)])

        let chip = services.chipIndex(for: entry.id, in: harness.context).chip(for: "sarah", kind: .person)

        #expect(chip == .init(entityID: try harness.entity("Sarah Kim").id, guessed: true, surface: "sarah"))
    }

    @Test func aMovedMentionOpensWhereTheUserPutIt() throws {
        let entry = try harness.entry("sarah came by.", mentions: [("sarah", .person)])
        try harness.entry("Tom called.", mentions: [("Tom", .person)])
        let tom = try harness.entity("Tom")
        let mention = MentionRef(entryID: entry.id, surface: "sarah", kind: .person)
        #expect(services.repoint(mention, to: .existing(tom.id), addingAlias: false, in: harness.context) == .applied(tom.id))

        let chip = services.chipIndex(for: entry.id, in: harness.context).chip(for: "sarah", kind: .person)

        #expect(chip == .init(entityID: tom.id, guessed: false, surface: "sarah"))
    }

    @Test func aHiddenEntityOpensNothing() throws {
        let entry = try harness.entry("Sarah called.", mentions: [("Sarah", .person)])
        services.setHidden(true, on: try harness.entity("Sarah").id, in: harness.context)

        #expect(services.chipIndex(for: entry.id, in: harness.context).chip(for: "Sarah", kind: .person) == nil)
    }

    @Test func anEntryNotIndexedYetHasNoChips() throws {
        let entry = Entry(text: "Nothing yet.")
        harness.context.insert(entry)
        #expect(services.chipIndex(for: entry.id, in: harness.context) == .empty)
    }

    // Generate again can prune what a pushed page shows; the route then resolves to gone.
    @Test func generatingAgainCanLeaveAPageWithNothingToShow() throws {
        let entry = try harness.entry("Sarah called.", mentions: [("Sarah", .person)])
        let route = EntityRoute(id: try harness.entity("Sarah").id)
        entry.insights?.mentions = []
        entry.insights?.generatedAt = Date(timeIntervalSince1970: 2_000)
        services.insightsWritten(for: entry, in: harness.context)
        try harness.context.save()

        let found = services.editor.entity(withID: route.id, in: harness.context)
        #expect(EntityPagePresentation.resolve(route, exists: found != nil, mergedIntoID: found?.mergedIntoID) == .gone)
        #expect(services.revision == 1)
    }
}
