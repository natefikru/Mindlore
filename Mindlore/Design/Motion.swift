import SwiftUI

// The app's four motions. Everything that moves picks one of these, so the app moves one way.
enum Motion {
    // Anything arriving: cards, chips, a sheet's content.
    static let settle = Animation.spring(duration: 0.45, bounce: 0.18)
    // Something the app noticed appearing: insights landing, a node joining the graph.
    static let bloom = Animation.spring(duration: 0.6, bounce: 0.3)
    // One object moving between two places: the accessory becoming the recorder, a row becoming an entry.
    static let carry = Animation.spring(duration: 0.5, bounce: 0.12)
    // Waiting: the idle mic, AI at work.
    static let breathe = Animation.easeInOut(duration: 2.4).repeatForever(autoreverses: true)
    // What all of them become under Reduce Motion.
    static let reduced = Animation.easeInOut(duration: 0.2)

    // The gap between items that Bloom in one after another.
    static let stagger: Double = 0.06

    static func resolve(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        guard reduceMotion else { return animation }
        // A repeating animation has no still equivalent; it simply doesn't run.
        return animation == breathe ? nil : reduced
    }
}

// Scale and fade in, for a Bloom. Opacity only under Reduce Motion.
struct BloomTransition: Transition {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .opacity(phase.isIdentity ? 1 : 0)
            .scaleEffect(phase.isIdentity || reduceMotion ? 1 : 0.6)
    }
}

extension Transition where Self == BloomTransition {
    static var bloom: BloomTransition { BloomTransition() }
}
