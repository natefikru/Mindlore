import Testing
import UIKit
@testable import Mindlore

struct ReadTapCaretTests {
    private let font = UIFont.systemFont(ofSize: 17)
    private let text = "First line here\nSecond line there"

    private func offset(_ point: CGPoint, in text: String? = nil, width: CGFloat = 300) -> Int {
        ReadTapCaret.offset(at: point, in: text ?? self.text, width: width, font: font, lineSpacing: 6)
    }

    @Test func aTapAtTheTopLeftGoesBeforeTheFirstCharacter() {
        #expect(offset(CGPoint(x: 0, y: 2)) == 0)
    }

    @Test func aTapBelowTheTextGoesToTheEnd() {
        #expect(offset(CGPoint(x: 10, y: 500)) == text.utf16.count)
    }

    @Test func aTapPastTheEndOfALineStaysOnThatLine() {
        // "First line here" is 15 characters; the newline is the 16th.
        #expect(offset(CGPoint(x: 290, y: 5)) == 15)
    }

    @Test func aTapOnTheSecondLineLandsInIt() {
        let lineHeight = font.lineHeight + 6
        let start = offset(CGPoint(x: 0, y: lineHeight + 4))
        #expect(start == 16)
        let later = offset(CGPoint(x: 60, y: lineHeight + 4))
        #expect(later > 16 && later < text.utf16.count)
    }

    @Test func aTapBetweenWordsGoesToTheNearerSide() {
        let prefix = ("First " as NSString).size(withAttributes: [.font: font]).width
        #expect(offset(CGPoint(x: prefix + 1, y: 5)) == 6)
    }

    @Test func emptyTextAndNoWidthGoToTheEnd() {
        #expect(offset(CGPoint(x: 5, y: 5), in: "") == 0)
        #expect(offset(CGPoint(x: 5, y: 5), width: 0) == text.utf16.count)
    }
}
