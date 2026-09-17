import Foundation
import SwiftData
import Testing
@testable import Mindlore

struct EntityAreasTests {
    private typealias Areas = EntityAreas.EntryAreas
    private let sarah = UUID()

    private func links(_ entryIDs: [UUID], entity: UUID) -> [EntityGraph.LinkInput] {
        entryIDs.map { .init(entryID: $0, entityID: entity, entryDate: .distantPast) }
    }

    private func at(_ day: Double) -> Date { Date(timeIntervalSince1970: day * 86_400) }

    @Test func theMostCommonAreaWins() {
        let e1 = UUID(), e2 = UUID(), e3 = UUID()
        let result = EntityAreas.primaryAreas(links: links([e1, e2, e3], entity: sarah), areasByEntry: [
            e1: Areas(areas: [.work, .friends], date: at(1)),
            e2: Areas(areas: [.friends], date: at(2)),
            e3: Areas(areas: [.work, .friends], date: at(9)),
        ])
        #expect(result[sarah] == .friends)
    }

    @Test func aTieGoesToTheMostRecentEntrysArea() {
        let e1 = UUID(), e2 = UUID()
        let result = EntityAreas.primaryAreas(links: links([e1, e2], entity: sarah), areasByEntry: [
            e1: Areas(areas: [.work], date: at(1)),
            e2: Areas(areas: [.family], date: at(5)),
        ])
        #expect(result[sarah] == .family)

        let same = UUID()
        let both = EntityAreas.primaryAreas(links: links([same], entity: sarah), areasByEntry: [
            same: Areas(areas: [.home, .work], date: at(1)),
        ])
        #expect(both[sarah] == .work, "equal counts and dates fall back to LifeArea's order")
    }

    @Test func entriesWithoutAreasGiveNoneAndDuplicateLinksCountOnce() {
        let e1 = UUID(), e2 = UUID(), e3 = UUID()
        let tom = UUID()
        let result = EntityAreas.primaryAreas(
            links: links([e1], entity: sarah) + links([e2, e2, e2, e3], entity: sarah) + links([e1], entity: tom),
            areasByEntry: [
                e2: Areas(areas: [.play], date: at(1)),
                e3: Areas(areas: [.home], date: at(2)),
            ]
        )
        #expect(result[sarah] == .home, "e2 counted once, so the tie goes to the more recent home")
        #expect(result[tom] == nil)
    }

    // Through GraphServices: a merged entity counts the entries its loser brought.
    @MainActor
    @Test func aMergedEntityCountsItsLosersEntries() throws {
        let harness = try GraphHarness()
        let graph = GraphServices(diagnostics: .disabled)
        let context = harness.context
        for (index, text) in ["Sarah at work.", "Sarah at work again."].enumerated() {
            let entry = try harness.entry(text, entryDate: at(Double(index)), mentions: [("Sarah", .person)])
            entry.insights?.areas = [.work]
        }
        for index in 0..<3 {
            let entry = try harness.entry("Tom over dinner.", entryDate: at(Double(10 + index)), mentions: [("Tom", .person)])
            entry.insights?.areas = [.friends]
        }
        try context.save()
        graph.indexer.sweep(in: context)
        let sarah = try harness.entity("Sarah"), sara = try harness.entity("Tom")
        #expect(graph.primaryAreas(in: context)[sarah.id] == .work)

        _ = graph.merge(sara.id, into: sarah.id, in: context)
        let areas = graph.primaryAreas(in: context)
        #expect(areas[sarah.id] == .friends)
        #expect(areas[sara.id] == nil)
    }
}
