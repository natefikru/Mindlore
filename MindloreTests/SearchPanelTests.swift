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
}
