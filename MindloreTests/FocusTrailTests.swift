import Foundation
import Testing
@testable import Mindlore

struct FocusTrailTests {
    private let a = UUID(), b = UUID(), c = UUID()

    @Test func focusingAppendsAndRefocusingStepsBack() {
        var trail = FocusTrail()
        trail.focus(a)
        trail.focus(b)
        trail.focus(c)
        #expect(trail.ids == [a, b, c])
        #expect(trail.current == c)

        trail.focus(a)
        #expect(trail.ids == [a])
    }

    @Test func backTruncatesAndIgnoresStrangers() {
        var trail = FocusTrail()
        [a, b, c].forEach { trail.focus($0) }
        trail.back(to: UUID())
        #expect(trail.ids == [a, b, c])
        trail.back(to: b)
        #expect(trail.ids == [a, b])
        trail.clear()
        #expect(trail.current == nil)
    }

    @Test func theTrailKeepsOnlyTheLatestEight() {
        var trail = FocusTrail()
        let ids = (0..<10).map { _ in UUID() }
        ids.forEach { trail.focus($0) }
        #expect(trail.ids == Array(ids.suffix(FocusTrail.cap)))
    }

    @Test func replacingALoserCollapsesItIntoTheWinner() {
        var trail = FocusTrail()
        [a, b, c].forEach { trail.focus($0) }
        trail.replace(c, with: a)
        #expect(trail.ids == [a])

        var other = FocusTrail()
        [a, b].forEach { other.focus($0) }
        other.replace(b, with: c)
        #expect(other.ids == [a, c])
    }

    // A merge made from the review card, not a pushed page, still moves the trail to the winner,
    // and an entity that's gone drops out.
    @Test func normalizingFollowsMergesAndDropsTheMissing() {
        var trail = FocusTrail()
        [a, b, c].forEach { trail.focus($0) }
        let winner = UUID()
        trail.normalize(root: { $0 == c ? winner : $0 }, exists: { $0 != b })
        #expect(trail.ids == [a, winner])
        #expect(trail.current == winner)
    }
}
