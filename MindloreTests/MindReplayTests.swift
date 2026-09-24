import Foundation
import Testing
@testable import Mindlore

@MainActor
struct MindReplayTests {
    private func at(_ day: Double) -> Date { Date(timeIntervalSince1970: day * 86_400) }

    private func snapshot(days: [Double]) -> MindMapSnapshot {
        let person = UUID()
        let links = days.map { EntityGraph.LinkInput(entryID: UUID(), entityID: person, entryDate: at($0)) }
        return MindMapSnapshot(entities: [person: .init(id: person, name: "Sarah", kind: .person)], links: links, entries: [:])
    }

    @Test func theClockRunsLinearlyFromTheFirstMentionAndClamps() throws {
        let replay = try #require(MindReplay(snapshot: snapshot(days: [30, 10, 500]), end: at(110), duration: 10))
        #expect(replay.start == at(10), "the future mention on day 500 is ignored")
        #expect(replay.asOf(elapsed: -1) == at(10))
        #expect(replay.asOf(elapsed: 5) == at(60))
        #expect(replay.asOf(elapsed: 12) == at(110))
        #expect(!replay.isFinished(elapsed: 9.9))
        #expect(replay.isFinished(elapsed: 10))
    }

    @Test func nothingToPlayWithoutAPastMention() {
        #expect(MindReplay(snapshot: .empty, end: at(10)) == nil)
        #expect(MindReplay(snapshot: snapshot(days: [20]), end: at(10)) == nil)
        #expect(MindReplay(snapshot: snapshot(days: [10]), end: at(10)) == nil)
    }

    @Test func aPlayerFetchesOnceForSixtySteps() throws {
        let data = snapshot(days: [0, 50])
        var fetches = 0
        let player = MindReplayPlayer()
        #expect(player.start(now: at(100)) { fetches += 1; return data })
        #expect(player.isRunning)
        var dates: [Date] = []
        for step in 0...60 {
            let result = try #require(player.step(elapsed: Double(step) / 10))
            #expect(result.snapshot.links == data.links)
            #expect(result.finished == (step == 60))
            dates.append(result.asOf)
        }
        #expect(fetches == 1)
        #expect(dates == dates.sorted())
        #expect(player.asOf == at(100))

        player.refetch()
        #expect(fetches == 2, "a graph change mid-run reads once more")
        #expect(player.step(elapsed: 3)?.asOf == at(50), "and keeps the clock")

        player.stop()
        #expect(!player.isRunning)
        #expect(player.step(elapsed: 1) == nil)
        player.refetch()
        #expect(fetches == 2)

        #expect(player.start(now: at(100)) { fetches += 1; return data })
        #expect(fetches == 3)
    }

    @Test func aPlayerWithNothingToPlayDoesNotRun() {
        let player = MindReplayPlayer()
        #expect(!player.start(now: at(1)) { .empty })
        #expect(!player.isRunning)
    }

    @Test func noteStepCollectsTimings() {
        let player = MindReplayPlayer()
        player.start(now: at(100)) { self.snapshot(days: [1]) }
        player.noteStep(seconds: 0.002)
        #expect(player.stepSeconds == [0.002])
        #expect(player.startedAt != nil)
    }

    @Test func stepsPublishTwiceASecond() {
        let published = (0..<20).filter { MindReplay.publishes(step: $0) }
        #expect(published == [0, 5, 10, 15])
    }

    // MARK: - Playing the window on screen

    @Test func aReplayTakesSixSeconds() throws {
        let replay = try #require(MindReplay(snapshot: snapshot(days: [10]), end: at(110)))
        #expect(replay.duration == 6)
        #expect(!replay.isFinished(elapsed: 5.9))
        #expect(replay.isFinished(elapsed: 6))
    }

    @Test func eachWindowPlaysFromItsOwnStart() throws {
        let data = snapshot(days: [5, 200, 390])
        let end = at(400)
        #expect(try #require(MindReplay(snapshot: data, window: .month, end: end)).start == at(370))
        #expect(try #require(MindReplay(snapshot: data, window: .quarter, end: end)).start == at(310))
        #expect(try #require(MindReplay(snapshot: data, window: .year, end: end)).start == at(35))
        #expect(try #require(MindReplay(snapshot: data, window: .all, end: end)).start == at(5))
    }

    @Test func aJournalYoungerThanTheWindowStartsAtItsFirstMention() throws {
        let replay = try #require(MindReplay(snapshot: snapshot(days: [350, 390]), window: .year, end: at(400)))
        #expect(replay.start == at(350))
    }

    @Test func aWindowWithNothingInItHasNothingToPlay() {
        let data = snapshot(days: [5, 200])
        #expect(MindReplay(snapshot: data, window: .month, end: at(400)) == nil)
        #expect(MindReplay(snapshot: data, window: .all, end: at(400)) != nil)
    }

    // Start-exclusive, like MindStats' windows: an entry on the window's first instant belongs to
    // the window before.
    @Test func sinceDropsTheStartInstantAndKeepsWhatFollows() {
        let data = snapshot(days: [10, 20, 20.001, 30])
        let trimmed = data.since(at(20))
        #expect(trimmed.links.map(\.entryDate) == [at(20.001), at(30)])
        #expect(trimmed.entities == data.entities, "entities stay: the map's minimum is sized on them")
        #expect(data.since(nil).links == data.links)
    }

    @Test func thePlayerTrimsToTheWindowAndReTrimsOnARefetch() throws {
        var data = snapshot(days: [5, 380, 390])
        let player = MindReplayPlayer()
        #expect(player.start(now: at(400), window: .month) { data })
        #expect(player.window == .month)
        #expect(try #require(player.step(elapsed: 0)).snapshot.links.count == 2)

        data = snapshot(days: [5, 6, 380, 385, 390])
        player.refetch()
        #expect(try #require(player.step(elapsed: 1)).snapshot.links.count == 3)
    }

    // The point of the change: a replay of the window lands on exactly the map that was on screen.
    @Test func theLastStepIsTheWindowsOwnMap() throws {
        let maya = UUID(), sam = UUID(), river = UUID()
        let entities: [UUID: MindMapSnapshot.EntityInfo] = [
            maya: .init(id: maya, name: "Maya", kind: .person),
            sam: .init(id: sam, name: "Sam", kind: .person),
            river: .init(id: river, name: "River", kind: .place),
        ]
        var links: [EntityGraph.LinkInput] = []
        var entries: [UUID: MindMapSnapshot.EntryInfo] = [:]
        let written: [(day: Double, names: [UUID], area: LifeArea)] = [
            (100, [maya, sam], .friends), (200, [maya, river], .play), (320, [maya, sam], .work),
            (350, [sam, river], .play), (390, [maya, river], .friends), (395, [maya], .family),
        ]
        for entry in written {
            let id = UUID()
            entries[id] = .init(id: id, date: at(entry.day), areas: [entry.area], mood: nil)
            links += entry.names.map { EntityGraph.LinkInput(entryID: id, entityID: $0, entryDate: at(entry.day)) }
        }
        let data = MindMapSnapshot(entities: entities, links: links, entries: entries, entryDates: written.map { at($0.day) })
        let end = at(400)

        for window in MindWindow.allCases {
            let player = MindReplayPlayer()
            #expect(player.start(now: end, window: window) { data })
            let last = try #require(player.step(elapsed: MindReplay.duration))
            #expect(last.finished)
            let replayed = MindView.frame(last.snapshot, window: .all, segment: .all, visibleAreas: LifeArea.allCases, asOf: last.asOf)
            let onScreen = MindView.frame(data, window: window, segment: .all, visibleAreas: LifeArea.allCases, asOf: end)
            #expect(Set(replayed.nodes) == Set(onScreen.nodes), "\(window)")
            #expect(Set(replayed.edges) == Set(onScreen.edges), "\(window)")
            #expect(replayed.areaOf == onScreen.areaOf, "\(window)")
        }
    }
}
