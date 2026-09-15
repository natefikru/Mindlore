import Foundation

nonisolated protocol KeyValueStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

nonisolated extension UserDefaults: KeyValueStore {}
