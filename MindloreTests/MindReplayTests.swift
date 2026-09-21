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

    @Test func aPlayerFetchesOnceForAHundredSteps() throws {
        let data = snapshot(days: [0, 50])
        var fetches = 0
        let player = MindReplayPlayer()
        #expect(player.start(now: at(100)) { fetches += 1; return data })
        #expect(player.isRunning)
        var dates: [Date] = []
        for step in 0...100 {
            let result = try #require(player.step(elapsed: Double(step) / 10))
            #expect(result.snapshot.links == data.links)
            #expect(result.finished == (step == 100))
            dates.append(result.asOf)
        }
        #expect(fetches == 1)
        #expect(dates == dates.sorted())
        #expect(player.asOf == at(100))

        player.refetch()
        #expect(fetches == 2, "a graph change mid-run reads once more")
        #expect(player.step(elapsed: 5)?.asOf == at(50), "and keeps the clock")

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
}
