import Foundation

enum AppConfig {
    // The app's own journal mirrors to this container's private database. Only the default store
    // does (ModelContainerFactory); tests and demo journals never touch it. Permanent once created.
    static let cloudKitContainerID: String? = "iCloud.com.natefikru.mindlore"
}
