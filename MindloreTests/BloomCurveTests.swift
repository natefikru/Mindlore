import Foundation
import Testing
@testable import Mindlore

// The curve a graph node blooms along. `Motion.bloom` is an Animation and cannot be sampled, so
// this exists to be sampled instead; these assert it behaves like the spring it stands in for.
struct BloomCurveTests {
    @Test func itStartsSmallAndEndsExactlySettled() {
        #expect(BloomCurve.scale(at: 0) == BloomCurve.from)
        #expect(BloomCurve.scale(at: BloomCurve.duration) == 1)
        #expect(BloomCurve.scale(at: 10) == 1, "a node that stopped blooming is the size of one that never did")
    }

    @Test func itOvershootsOnceBeforeItSettles() {
        let samples = stride(from: 0.0, to: BloomCurve.duration, by: 0.01).map { BloomCurve.progress(at: $0) }
        guard let peak = samples.max() else { return #expect(Bool(false)) }
        #expect(peak > 1, "a bounce of 0.3 overshoots")
        #expect(peak < 1.15, "and only just: this is a notice, not a pop")

        // One overshoot, not a wobble: the curve rises, crosses 1 once, and comes back.
        let crossings = zip(samples, samples.dropFirst()).filter { ($0 < 1) != ($1 < 1) }.count
        #expect(crossings == 1)
    }

    @Test func opacityLeadsTheScaleSoTheNodeIsLegibleWhileItArrives() {
        #expect(BloomCurve.opacity(at: 0) == 0)
        #expect(BloomCurve.opacity(at: BloomCurve.duration * 0.4) == 1)
        #expect(BloomCurve.opacity(at: BloomCurve.duration) == 1)
    }

    // Matches BloomTransition, which scales only when Reduce Motion is off and always fades.
    @Test func reduceMotionIsOpacityAlone() {
        for time in [0, 0.1, 0.3, 0.6] {
            #expect(BloomCurve.scale(at: time, reduceMotion: true) == 1)
        }
        #expect(BloomCurve.opacity(at: 0.1) > 0)
    }

    // A staggered node has not started yet. It has to count as running and draw at nothing, or it
    // shows full size and then pops back to the start of its own animation.
    @Test func aNodeWaitingItsTurnIsRunningAndInvisible() {
        #expect(BloomCurve.isRunning(at: -0.12))
        #expect(BloomCurve.opacity(at: -0.12) == 0)
        #expect(BloomCurve.scale(at: -0.12) == BloomCurve.from)
        #expect(!BloomCurve.isRunning(at: BloomCurve.duration))
    }

    @Test func itMatchesTheAnimationItStandsIn() {
        #expect(BloomCurve.duration == 0.6, "Motion.bloom's duration")
        #expect(BloomCurve.from == 0.6, "BloomTransition's scale")
    }
}
