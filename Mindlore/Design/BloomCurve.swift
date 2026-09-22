import Foundation

// `Motion.bloom` is an `Animation`, and an `Animation` cannot be sampled. Inside a `Canvas` there
// is no view identity and no transition system, so `BloomTransition` cannot reach a graph node:
// the scale has to be read off a curve at a moment in time instead.
//
// This is that curve, and it is the step response of the spring `Motion.bloom` describes rather
// than a guess that looks close: damping ratio 0.7 (bounce 0.3), natural frequency chosen so the
// 2% settling time is the animation's own duration. It overshoots once, by about 5%, at 0.46 s,
// and is pinned to exactly 1 from 0.6 s on so a node that stopped blooming is the same size as a
// node that never did.
enum BloomCurve {
    static let duration: Double = 0.6
    static let from: Double = 0.6

    private static let damping = 0.7
    private static let frequency = 4 / (damping * duration)
    private static let damped = frequency * (1 - damping * damping).squareRoot()

    // 0 at rest, 1 settled, briefly over 1 in between.
    static func progress(at time: Double) -> Double {
        guard time > 0 else { return 0 }
        guard time < duration else { return 1 }
        let decay = exp(-damping * frequency * time)
        return 1 - decay * (cos(damped * time) + (damping * frequency / damped) * sin(damped * time))
    }

    static func scale(at time: Double, reduceMotion: Bool = false) -> Double {
        guard !reduceMotion else { return 1 }
        return from + (1 - from) * progress(at: time)
    }

    // Faster than the scale, so a node is legible before it has finished arriving. Opacity is the
    // whole of the effect under Reduce Motion, matching what `BloomTransition` does.
    static func opacity(at time: Double) -> Double {
        guard time > 0 else { return 0 }
        return min(1, time / (duration * 0.4))
    }

    // Negative time is a staggered node whose turn has not come: it counts as running, and the
    // curve holds it at nothing, or it would draw full size and then pop back to start.
    static func isRunning(at time: Double) -> Bool { time < duration }
}
