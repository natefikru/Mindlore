import Foundation
import SwiftData
import Testing
@testable import Mindlore

@MainActor
struct EntityPeekPresentationTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    @Test func theSummaryTakesTheBiosFirstLineAndCountsRecentEntries() {
        let summary = EntityPeekPresentation.summary(
            name: "Sarah",
            kind: .person,
            bio: "\n  A friend from the climbing gym.  \nMoved in March.",
            entryDates: [now - 2 * day, now - 29 * day, now - 31 * day, now - 400 * day],
            now: now
        )
        #expect(summary.bioFirstLine == "A friend from the climbing gym.")
        #expect(summary.lastMentioned == now - 2 * day)
        #expect(summary.recentEntryCount == 2)
    }

    @Test func noBioAndNoEntriesSayNothing() {
        let summary = EntityPeekPresentation.summary(name: "Tom", kind: .person, bio: "  ", entryDates: [], now: now)
        #expect(summary.bioFirstLine == nil)
        #expect(summary.lastMentioned == nil)
        #expect(summary.recentEntryCount == 0)
    }

    @Test func aWinnerCountsEveryEntryItAbsorbedOnce() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let graph = GraphServices()
        let winner = Entity(name: "Sarah Kim", key: "sarah kim", kind: .person)
        winner.bio = "Climbs on Tuesdays."
        let loser = Entity(name: "Sara", key: "sara", kind: .person)
        context.insert(winner)
        context.insert(loser)

        func entry(daysAgo: Double, naming entities: [Entity]) {
            let entry = Entry(createdAt: now - daysAgo * day, text: "Saw them.")
            context.insert(entry)
            for entity in entities {
                let link = EntityLink(surface: entity.name, kind: .person)
                context.insert(link)
                link.attach(to: entry, entity: entity)
            }
        }
        entry(daysAgo: 1, naming: [winner, loser])
        entry(daysAgo: 10, naming: [loser])
        entry(daysAgo: 90, naming: [winner])
        try context.save()

        #expect(graph.merge(loser.id, into: winner.id, in: context) == winner.id)

        let summary = try #require(EntityPeekPresentation.load(winner.id, graph: graph, in: context, now: now))
        #expect(summary.name == "Sarah Kim")
        #expect(summary.bioFirstLine == "Climbs on Tuesdays.")
        #expect(summary.recentEntryCount == 2)
        #expect(summary.lastMentioned == now - 1 * day)
        #expect(EntityPeekPresentation.load(UUID(), graph: graph, in: context, now: now) == nil)
        #expect(summary.openLooseEnd == nil)

        // Loose ends written against the loser count for the winner; settled ones don't show.
        let older = LooseEnd(text: "Ask Sara about the trip", sourceEntryID: UUID(), sourceEntryDate: now - 5 * day, entityIDs: [loser.id])
        let newer = LooseEnd(text: "Sarah's reply on the lease", sourceEntryID: UUID(), sourceEntryDate: now - 2 * day, entityIDs: [loser.id])
        let settled = LooseEnd(text: "Settled already", sourceEntryID: UUID(), sourceEntryDate: now - 1 * day, entityIDs: [winner.id])
        settled.setStatus(.resolved, at: now)
        [older, newer, settled].forEach(context.insert)
        let withLooseEnds = try #require(EntityPeekPresentation.load(winner.id, graph: graph, in: context, now: now))
        #expect(withLooseEnds.openLooseEnd == "Sarah's reply on the lease")
        #expect(withLooseEnds.openLooseEndCount == 2, "both open ones, through the merge; the settled one doesn't count")
    }

    // Twenty-six weeks ending now, the newest on the right; a week's first instant belongs to the
    // week before, and the future and anything older than the span stay out.
    @Test func theSeriesIsWeeklyOverHalfAYear() {
        let week = 7 * day
        let bars = EntityPeekPresentation.series([now, now - 1 * day, now - week, now - week + 1, now - 26 * week, now - 26 * week + 1, now + day], now: now)
        #expect(bars.count == 26)
        #expect(bars[25] == 3)
        #expect(bars[24] == 1)
        #expect(bars[0] == 1)
        #expect(bars.reduce(0, +) == 5)
        #expect(EntityPeekPresentation.summary(name: "Tom", kind: .person, bio: nil, entryDates: [now - day], now: now).series.last == 1)
    }

    @Test func namesAndThemesSplitFromOneRankedList() {
        let partners: [(id: UUID, name: String, kind: EntityKind, entries: Int)] = [
            (UUID(), "dating", .tag, 43), (UUID(), "processing", .tag, 42), (UUID(), "Danny", .person, 14),
            (UUID(), "texting", .tag, 12), (UUID(), "Mom", .person, 9), (UUID(), "running", .tag, 8),
            (UUID(), "Café Olmo", .place, 7), (UUID(), "Omar", .person, 6),
        ]
        let split = EntityPeekPresentation.split(partners)
        #expect(split.connections.map(\.name) == ["Danny", "Mom", "Café Olmo"])
        #expect(split.connections.map(\.entries) == [14, 9, 7])
        #expect(split.themes == ["dating", "processing", "texting"])
    }

    @Test func lastMentionedIsSaidInDays() {
        let calendar = Calendar(identifier: .gregorian)
        let noon = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 12))!
        #expect(EntityPeekPresentation.lastMentionedWords(noon.addingTimeInterval(-3600), now: noon, calendar: calendar) == "today")
        #expect(EntityPeekPresentation.lastMentionedWords(noon.addingTimeInterval(-86_400), now: noon, calendar: calendar) == "yesterday")
        #expect(EntityPeekPresentation.lastMentionedWords(noon.addingTimeInterval(-3 * 86_400), now: noon, calendar: calendar).contains("3"))
    }

    // "Often with" is mentionedWith's top three, with the entries each pair shares, most first.
    @Test func connectionsAreTheTopThreeByEntriesShared() throws {
        let harness = try GraphHarness()
        let graph = GraphServices()
        // mentionedWith weighs against the real clock, so these entries are dated from it.
        let today = Date.now
        for _ in 0..<3 { try harness.entry(entryDate: today - day, mentions: [("Maya", .person), ("Danny", .person)]) }
        for _ in 0..<2 { try harness.entry(entryDate: today - day, mentions: [("Maya", .person), ("Mom", .person)]) }
        try harness.entry(entryDate: today - day, mentions: [("Maya", .person), ("Omar", .person)])
        try harness.entry(entryDate: today - day, mentions: [("Maya", .person), ("Kev", .person)])
        harness.indexer.sweep(in: harness.context)
        let maya = try harness.entity("Maya")

        let summary = try #require(EntityPeekPresentation.load(maya.id, graph: graph, in: harness.context, now: today))

        #expect(summary.connections.count == 3)
        #expect(summary.connections.prefix(2).map(\.name) == ["Danny", "Mom"])
        #expect(summary.connections.map(\.entries).prefix(2) == [3, 2])
        #expect(summary.connections.last?.entries == 1)
        #expect(summary.series.last == 7)
    }

    // A hidden entity still has a card (it can be focused from search), and a merged loser's
    // route reads as the winner.
    @Test func hiddenEntitiesSummariseAndLosersResolveToTheWinner() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let graph = GraphServices()
        let hidden = Entity(name: "Old Job", key: "old job", kind: .organization)
        hidden.hidden = true
        let winner = Entity(name: "Sarah", key: "sarah", kind: .person)
        let loser = Entity(name: "Sara", key: "sara", kind: .person)
        [hidden, winner, loser].forEach(context.insert)
        try context.save()
        _ = graph.merge(loser.id, into: winner.id, in: context)

        #expect(EntityPeekPresentation.load(hidden.id, graph: graph, in: context, now: now)?.name == "Old Job")
        let route = EntityPagePresentation.resolve(EntityRoute(id: loser.id), exists: true, mergedIntoID: loser.mergedIntoID)
        #expect(route == .show(winner.id))
        #expect(EntityPeekPresentation.load(winner.id, graph: graph, in: context, now: now)?.name == "Sarah")
    }
}
