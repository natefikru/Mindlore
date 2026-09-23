import SwiftUI
import UIKit

// The typeface the user's own words are set in. One rule the reader can feel without being told
// is that serif is the user and sans is the app; this setting moves the user's side of it, and
// the app's chrome stays SF whatever is picked. System designs only, never bundled fonts, so
// Dynamic Type and every weight keep working.
nonisolated enum JournalFont: String, CaseIterable, Codable, Sendable {
    case serif
    case sans
    case rounded
    case monospaced

    var settingsName: String {
        switch self {
        case .serif: "Classic"
        case .sans: "Modern"
        case .rounded: "Soft"
        case .monospaced: "Typewriter"
        }
    }

    var detail: String {
        switch self {
        case .serif: "A book face, the way the journal has always read."
        case .sans: "The plain face the rest of the phone uses."
        case .rounded: "Softer edges, a little friendlier."
        case .monospaced: "Every letter the same width, like a typewriter."
        }
    }

    var design: Font.Design {
        switch self {
        case .serif: .serif
        case .sans: .default
        case .rounded: .rounded
        case .monospaced: .monospaced
        }
    }

    var uiDesign: UIFontDescriptor.SystemDesign {
        switch self {
        case .serif: .serif
        case .sans: .default
        case .rounded: .rounded
        case .monospaced: .monospaced
        }
    }
}

// Carried through the environment from RootView, so every view that sets the user's words and
// the UIKit text view underneath the editor read one value.
private struct JournalFontKey: EnvironmentKey {
    static let defaultValue = JournalFont.serif
}

extension EnvironmentValues {
    var journalFont: JournalFont {
        get { self[JournalFontKey.self] }
        set { self[JournalFontKey.self] = newValue }
    }
}
