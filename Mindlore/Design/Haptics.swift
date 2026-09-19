import SwiftUI

// Every moment the phone taps back, in one place, so the same event always feels the same.
// Nothing fires on scroll. Use with `.sensoryFeedback(Haptics.kept, trigger: ...)`.
enum Haptics {
    static let recordStart = SensoryFeedback.impact(weight: .medium)
    static let recordStop = SensoryFeedback.impact(weight: .heavy, intensity: 0.8)
    static let kept = SensoryFeedback.success
    static let insightsLanded = SensoryFeedback.impact(flexibility: .soft)
    static let looseEndClosed = SensoryFeedback.success
    static let selected = SensoryFeedback.selection
    static let detent = SensoryFeedback.impact(weight: .light)
    static let replayTick = SensoryFeedback.impact(flexibility: .soft, intensity: 0.4)
    static let failed = SensoryFeedback.warning
}
