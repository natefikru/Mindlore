import SwiftUI
import UIKit

// One rule the reader can feel without being told: the user's words are set in the journal face and
// the app in SF. The user's own words (entry text, titles, quoted snippets) take the `JournalFont`
// the user picked in Settings, New York by default; chrome and anything the AI wrote is SF.
// Text styles only, never point sizes, so Dynamic Type keeps working.
extension View {
    // The user's own words, at a text style.
    func journalText(_ style: Font.TextStyle = .body, weight: Font.Weight? = nil) -> some View {
        modifier(JournalTextStyle(style: style, weight: weight))
    }

    // Numerals that tick: the recording timer, totals.
    func roundedNumerals(_ style: Font.TextStyle) -> some View {
        font(.system(style, design: .rounded)).monospacedDigit()
    }
}

private struct JournalTextStyle: ViewModifier {
    @Environment(\.journalFont) private var journalFont
    let style: Font.TextStyle
    let weight: Font.Weight?

    func body(content: Content) -> some View {
        // The weight stays optional so a style keeps its own: a headline is semibold unless asked.
        content.font(.system(style, design: journalFont.design, weight: weight))
    }
}

extension UIFont {
    // The journal twin of a preferred font, for the UIKit text view `.fontDesign` cannot reach. Built on
    // the preferred descriptor, which carries its text style, so a view with
    // `adjustsFontForContentSizeCategory` still follows Dynamic Type.
    static func journal(_ style: UIFont.TextStyle, design: UIFontDescriptor.SystemDesign = .serif) -> UIFont {
        let base = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style)
        guard let designed = base.withDesign(design) else { return .preferredFont(forTextStyle: style) }
        return UIFont(descriptor: designed, size: 0)
    }
}
