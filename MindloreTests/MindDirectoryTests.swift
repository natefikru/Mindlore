import Foundation
import SwiftData
import Testing
@testable import Mindlore

@MainActor
struct MindDirectoryTests {
    let harness: GraphHarness
    let graph = GraphServices(diagnostics: .disabled)

    init() throws {
        harness = try GraphHarness()
    }

    private var context: ModelContext { harness.context }
    private func at(_ day: Double) -> Date { Date(timeIntervalSince1970: day * 86_400) }

    private func seed() throws {
        try harness.entry("Sarah and Tom.", entryDate: at(1), mentions: [("Sarah", .person), ("Tom", .person)])
        try harness.entry("Sarah again.", entryDate: at(5), mentions: [("Sarah", .person)])
        try harness.entry("Tom at the lake.", entryDate: at(3), mentions: [("Tom", .person), ("Lake", .place)])
        graph.indexer.sweep(in: context)
    }

    private func looseEnd(_ text: String, about ids: [UUID]) -> LooseEnd {
        let looseEnd = LooseEnd(text: text, sourceEntryID: UUID(), sourceEntryDate: at(1), entityIDs: ids)
        context.insert(looseEnd)
        return looseEnd
    }

    private func row(_ name: String, in rows: [EntitySearch.Row]) -> EntitySearch.Row? {
        rows.first { $0.name == name }
    }

    @Test func rowsCarryLastMentionedAndOpenLooseEnds() throws {
        try seed()
        let sarah = try harness.entity("Sarah"), tom = try harness.entity("Tom")
        _ = looseEnd("Hear from Sarah", about: [sarah.id])
        _ = looseEnd("Plan with both", about: [sarah.id, tom.id])
        looseEnd("Settled", about: [sarah.id]).setStatus(.resolved, at: at(9))
        looseEnd("Faded", about: [sarah.id]).setStatus(.faded, at: at(9))
        try context.save()

        let rows = MindDirectory.rows(in: context)
        #expect(row("Sarah", in: rows.visible)?.lastMentioned == at(5))
        #expect(row("Sarah", in: rows.visible)?.openLooseEnds == 2)
        #expect(row("Tom", in: rows.visible)?.openLooseEnds == 1)
        #expect(row("Lake", in: rows.visible)?.openLooseEnds == 0)
        #expect(rows.hidden.isEmpty)
    }

    @Test func mergesCountOnceAndUnmergeSplitsThemAgain() throws {
        try seed()
        let sarah = try harness.entity("Sarah"), tom = try harness.entity("Tom")
        _ = looseEnd("Tom's thing", about: [tom.id])
        _ = looseEnd("Both of them", about: [sarah.id, tom.id])
        try context.save()

        _ = graph.merge(tom.id, into: sarah.id, in: context)
        var rows = MindDirectory.rows(in: context)
        #expect(row("Tom", in: rows.visible) == nil)
        #expect(row("Tom", in: rows.hidden) == nil, "a merged loser shows nowhere")
        #expect(row("Sarah", in: rows.visible)?.openLooseEnds == 2, "the shared loose end counts once")
        #expect(row("Sarah", in: rows.visible)?.linkCount == 4, "every link Tom had moved over")

        graph.unmerge(tom.id, in: context)
        rows = MindDirectory.rows(in: context)
        #expect(row("Tom", in: rows.visible)?.openLooseEnds == 2)
        #expect(row("Tom", in: rows.visible)?.linkCount == 2, "unmerge gives Tom his mentions back")
        #expect(row("Sarah", in: rows.visible)?.openLooseEnds == 1)
        #expect(row("Sarah", in: rows.visible)?.linkCount == 2)
    }

    @Test func hiddenEntitiesGoToTheirOwnList() throws {
        try seed()
        let lake = try harness.entity("Lake")
        graph.setHidden(true, on: lake.id, in: context)

        let rows = MindDirectory.rows(in: context)
        #expect(row("Lake", in: rows.visible) == nil)
        #expect(row("Lake", in: rows.hidden) != nil)
    }

    // Done changes a loose end's status, not how many there are.
    @Test func theRefreshKeyChangesWhenALooseEndIsMarkedDone() {
        let id = UUID()
        let before = MindDirectory.looseEndKey([(id, LooseEndStatus.open.rawValue)])
        let after = MindDirectory.looseEndKey([(id, LooseEndStatus.resolved.rawValue)])
        #expect(before != after)
        #expect(before.count == after.count)
    }
}
