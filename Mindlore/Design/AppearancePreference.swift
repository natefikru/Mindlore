import SwiftUI
import UIKit

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

// Applied to the app's windows rather than through `.preferredColorScheme` alone. That modifier
// left an open sheet (Settings is one) in the old scheme until it was reopened, and going back to
// System after Light or Dark often didn't take until a relaunch (owner, 2026-09-24). A window's
// style reaches every sheet it presents at once, and `.unspecified` hands back to the system.
extension AppearancePreference {
    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    // What the app was last told, for a window made later (the lock cover).
    @MainActor static var appliedStyle: UIUserInterfaceStyle = .unspecified

    @MainActor static func apply(_ preference: AppearancePreference) {
        appliedStyle = preference.interfaceStyle
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = preference.interfaceStyle
            }
        }
    }
}
