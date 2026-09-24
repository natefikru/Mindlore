import Foundation
import Testing
@testable import Mindlore

struct SearchPanelTests {
    private let available: CGFloat = 700

    @Test func stopHeights() {
        #expect(SearchPanel.height(for: .peek, available: available) == SearchPanel.peekHeight)
        #expect(abs(SearchPanel.height(for: .half, available: available) - 245) < 0.001)
        #expect(SearchPanel.height(for: .full, available: available) == 640)
        #expect(SearchPanel.height(for: .full, available: 50) == SearchPanel.peekHeight, "never shorter than peek")
    }

    @Test func aDragSnapsToTheNearestStop() {
        #expect(SearchPanel.snap(from: .half, predictedTranslation: 0, available: available) == .half)
        #expect(SearchPanel.snap(from: .half, predictedTranslation: 60, available: available) == .half)
        #expect(SearchPanel.snap(from: .half, predictedTranslation: 200, available: available) == .peek)
        #expect(SearchPanel.snap(from: .half, predictedTranslation: -250, available: available) == .full)
        #expect(SearchPanel.snap(from: .peek, predictedTranslation: -150, available: available) == .half)
    }

    // A flick carries further than the finger went: the predicted end decides.
    @Test func aFlickFromFullCanReachPeek() {
        #expect(SearchPanel.snap(from: .full, predictedTranslation: 700, available: available) == .peek)
        #expect(SearchPanel.snap(from: .full, predictedTranslation: 300, available: available) == .half)
    }

    // Between the stops the panel follows the finger point for point; past either end it gives
    // less and less, and never more than `overscroll`.
    @Test func aDragTracksTheFingerAndRubberBandsPastTheEnds() {
        let half = SearchPanel.height(for: .half, available: available)
        let full = SearchPanel.height(for: .full, available: available)
        let peek = SearchPanel.height(for: .peek, available: available)
        #expect(SearchPanel.visibleHeight(from: .half, translation: 0, available: available) == half)
        #expect(SearchPanel.visibleHeight(from: .half, translation: -100, available: available) == half + 100)
        #expect(SearchPanel.visibleHeight(from: .half, translation: 50, available: available) == half - 50)

        let past = SearchPanel.visibleHeight(from: .full, translation: -40, available: available)
        #expect(past > full && past < full + 40, "gives, but less than the finger")
        let far = SearchPanel.visibleHeight(from: .full, translation: -5_000, available: available)
        #expect(far < full + SearchPanel.overscroll)
        let below = SearchPanel.visibleHeight(from: .peek, translation: 40, available: available)
        #expect(below < peek && below > peek - 40)
        #expect(SearchPanel.rubberBand(0) == 0)
    }

    @Test func glassTurnsToPaperOverTheFirstStretchOffPeek() {
        let peek = SearchPanel.peekHeight
        #expect(SearchPanel.reveal(visible: peek, peek: peek) == 0)
        #expect(SearchPanel.reveal(visible: peek - 10, peek: peek) == 0)
        #expect(abs(SearchPanel.reveal(visible: peek + SearchPanel.revealDistance / 2, peek: peek) - 0.5) < 0.001)
        #expect(SearchPanel.reveal(visible: peek + 500, peek: peek) == 1)
    }

    // The settle starts at the finger's speed, as a fraction of the distance left per second.
    @Test func theSettleSpringStartsAtTheFingersSpeed() {
        // 100pt to go upward, finger moving up at 400pt/s: four distances a second.
        #expect(SearchPanel.settleVelocity(from: 300, to: 400, dragVelocity: -400) == 4)
        #expect(SearchPanel.settleVelocity(from: 300, to: 300.5, dragVelocity: -400) == 0, "already there")
        #expect(SearchPanel.settleVelocity(from: 300, to: 310, dragVelocity: -9_000) == 12, "capped")
        #expect(SearchPanel.settleVelocity(from: 300, to: 400, dragVelocity: 900) == -3, "against the settle, capped")
    }
}
