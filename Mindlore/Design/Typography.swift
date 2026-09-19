import SwiftUI
import UIKit

// One rule the reader can feel without being told: serif is the user, sans is the app. The user's own
// words (entry text, titles, quoted snippets) are New York; chrome and anything the AI wrote is SF.
// Text styles only, never point sizes, so Dynamic Type keeps working.
extension View {
    // The user's own words, at a text style.
    func journalText(_ style: Font.TextStyle = .body) -> some View {
        font(.system(style, design: .serif))
    }

    // Numerals that tick: the recording timer, totals.
    func roundedNumerals(_ style: Font.TextStyle) -> some View {
        font(.system(style, design: .rounded)).monospacedDigit()
    }
}

extension UIFont {
    // The serif twin of a preferred font, for the UIKit text view `.fontDesign` cannot reach. Built on
    // the preferred descriptor, which carries its text style, so a view with
    // `adjustsFontForContentSizeCategory` still follows Dynamic Type.
    static func journal(_ style: UIFont.TextStyle) -> UIFont {
        let base = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style)
        guard let serif = base.withDesign(.serif) else { return .preferredFont(forTextStyle: style) }
        return UIFont(descriptor: serif, size: 0)
    }
}
