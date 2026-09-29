import UIKit

// Home Screen quick actions, from a long press on the icon: Record, New Entry, and Ask. Declared in
// Info.plist so they are there before the first launch, and handed to IntentRequests like Siri's
// intents and the Record control's link, so a cold launch and a warm one take the same path.
nonisolated enum QuickAction {
    static func action(forType type: String) -> IntentAction? {
        switch type {
        case "com.natefikru.mindlore.record": .record
        case "com.natefikru.mindlore.new": .newEntry
        case "com.natefikru.mindlore.ask": .ask(nil)
        default: nil
        }
    }
}

@MainActor
private func request(_ item: UIApplicationShortcutItem) -> Bool {
    guard let action = QuickAction.action(forType: item.type) else { return false }
    IntentRequests.shared.request(action)
    return true
}

// A cold launch from a quick action carries it in the connection options; a warm one arrives at
// the scene delegate, which SwiftUI only offers through a delegate adaptor.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem { _ = request(item) }
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = QuickActionSceneDelegate.self
        return configuration
    }
}

final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
        request(shortcutItem)
    }
}
