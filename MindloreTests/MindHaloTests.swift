import Foundation
import Testing
@testable import Mindlore

// Who breathes on the map. The rule is one entry dated inside the window, so these run against
// link dates alone: no entity, no fetch, no canvas.
struct MindHaloTests {
    private func at(_ day: Double) -> Date { Date(timeIntervalSince1970: day * 86_400) }

    private func snapshot(_ entries: [(day: Double, mentions: [UUID])]) -> MindMapSnapshot {
        var links: [EntityGraph.LinkInput] = []
        var infos: [UUID: MindMapSnapshot.EntryInfo] = [:]
        var entities: [UUID: MindMapSnapshot.EntityInfo] = [:]
        for entry in entries {
            let id = UUID()
            infos[id] = .init(id: id, date: at(entry.day), areas: [], mood: nil)
            for mention in entry.mentions {
                links.append(.init(entryID: id, entityID: mention, entryDate: at(entry.day)))
                entities[mention] = .init(id: mention, name: mention.uuidString, kind: .person)
            }
        }
        return MindMapSnapshot(entities: entities, links: links, entries: infos)
    }

    @Test func ringsWhatTheLastSevenDaysNamed() {
        let recent = UUID(), old = UUID()
        let map = snapshot([(100, [recent]), (80, [old])])
        #expect(MindMap.haloed(map, asOf: at(103)) == [recent])
    }

    // The window is inclusive at both ends, the way `recentMentions` counts.
    @Test func sevenDaysBreathesAndEightDoesNot() {
        let entity = UUID()
        let map = snapshot([(100, [entity])])
        #expect(MindMap.haloed(map, asOf: at(107)) == [entity])
        #expect(MindMap.haloed(map, asOf: at(108)).isEmpty)
    }

    // An entry dated after the map's moment has not happened yet, which is what makes a replay's
    // halo follow the replay instead of sitting on whoever is recent today.
    @Test func anEntryAheadOfTheMapsMomentNeverRings() {
        let future = UUID(), present = UUID()
        let map = snapshot([(110, [future]), (100, [present])])
        #expect(MindMap.haloed(map, asOf: at(101)) == [present])
    }

    @Test func aReplaysHaloIsTheHaloOfItsOwnWeek() {
        let january = UUID(), june = UUID()
        let map = snapshot([(10, [january]), (160, [june])])
        #expect(MindMap.haloed(map, asOf: at(12)) == [january])
        #expect(MindMap.haloed(map, asOf: at(162)) == [june])
    }

    // A busy week on a large journal would ring everything, which reads as a target range rather
    // than as news.
    @Test func theCapKeepsTheMostMentioned() {
        let loud = UUID(), quiet = (0..<5).map { _ in UUID() }
        var entries: [(day: Double, mentions: [UUID])] = quiet.map { (100, [$0]) }
        entries += (0..<3).map { _ in (100, [loud]) }
        let map = snapshot(entries)

        let capped = MindMap.haloed(map, asOf: at(101), cap: 2)
        #expect(capped.count == 2)
        #expect(capped.contains(loud), "three mentions beats one")
    }

    // Ties break on the id, so the same week rings the same nodes on every rebuild rather than
    // whichever way the dictionary happened to enumerate.
    @Test func theCapIsDeterministicOnATie() {
        let ids = (0..<6).map { _ in UUID() }
        let map = snapshot(ids.map { (100, [$0]) })
        let runs = (0..<5).map { _ in MindMap.haloed(map, asOf: at(101), cap: 3) }
        #expect(Set(runs).count == 1)
        #expect(runs[0] == Set(ids.sorted { $0.uuidString < $1.uuidString }.prefix(3)))
    }

    @Test func anEmptyJournalRingsNothing() {
        #expect(MindMap.haloed(.empty, asOf: at(100)).isEmpty)
    }

    // The window and the cap are the two numbers the map's look depends on; a change to either is
    // a design decision, not a tidy-up.
    @Test func theWindowIsSevenDaysAndTheCapIsForty() {
        #expect(MindMap.haloDays == 7)
        #expect(MindMap.haloCap == 40)
    }
}
