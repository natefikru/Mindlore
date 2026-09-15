import Foundation

enum AppConfig {
    // Stays nil until the app signs with a paid Apple Developer team that has the iCloud capability.
    // Any CloudKit use without that entitlement fails at runtime.
    static let cloudKitContainerID: String? = nil
}
