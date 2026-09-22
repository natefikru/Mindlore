import SwiftUI

// Which appearance the app draws in, independent of the system's own light/dark switch.
nonisolated enum AppearancePreference: String, CaseIterable, Codable, Sendable {
    case system, light, dark

    var settingsName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    // `nil` leaves the system in charge, the same thing `.preferredColorScheme(nil)` does.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
