import Foundation
import Testing
@testable import Mindlore

final class FakeCloudKeyValues: CloudKeyValues {
    var values: [String: Any] = [:]
    var writes: [String] = []
    var synchronized = 0

    func object(forKey key: String) -> Any? { values[key] }
    func write(_ value: Any?, forKey key: String) {
        values[key] = value
        writes.append(key)
    }
    func synchronize() -> Bool {
        synchronized += 1
        return true
    }
}

@MainActor
struct MirroredKeyValueStoreTests {
    private let local = FakeKeyValueStore()
    private let cloud = FakeCloudKeyValues()

    private func store(enabled: Bool = true) -> MirroredKeyValueStore {
        MirroredKeyValueStore(local: local, cloud: cloud, keys: ["shared"], isEnabled: enabled)
    }

    @Test func onlyMirroredKeysGoUp() {
        let mirrored = store()

        mirrored.set("a", forKey: "shared")
        mirrored.set("b", forKey: "mine")

        #expect(local.values["shared"] as? String == "a")
        #expect(local.values["mine"] as? String == "b")
        #expect(cloud.values["shared"] as? String == "a")
        #expect(cloud.values["mine"] == nil)
    }

    @Test func switchedOffNothingGoesUpOrComesDown() {
        let mirrored = store(enabled: false)
        cloud.values["shared"] = "theirs"
        var changed: [String] = []
        mirrored.onChange = { changed += $0 }

        mirrored.start(observing: nil)
        mirrored.set("mine", forKey: "shared")
        mirrored.cloudChanged(reason: .server, keys: ["shared"])

        #expect(cloud.values["shared"] as? String == "theirs")
        #expect(local.values["shared"] as? String == "mine")
        #expect(changed.isEmpty)
        #expect(cloud.synchronized == 0)
    }

    @Test func readsNeverAskTheCloud() {
        let mirrored = store()
        cloud.values["shared"] = "theirs"

        #expect(mirrored.object(forKey: "shared") == nil)
    }

    @Test func atStartTheCloudWinsAndWhatOnlyThisPhoneHasGoesUp() {
        let mirrored = MirroredKeyValueStore(local: local, cloud: cloud, keys: ["a", "b", "c"], isEnabled: true)
        cloud.values["a"] = "theirs"
        local.values["a"] = "mine"
        local.values["b"] = "only mine"
        var changed: [String] = []
        mirrored.onChange = { changed += $0 }

        mirrored.start(observing: nil)

        #expect(local.values["a"] as? String == "theirs")
        #expect(cloud.values["b"] as? String == "only mine")
        // Nobody set c: it stays missing on both sides, so neither side's default is pushed.
        #expect(local.values["c"] == nil)
        #expect(cloud.values["c"] == nil)
        #expect(changed == ["a"])
        #expect(cloud.synchronized == 1)
    }

    @Test func aServerChangeComesDownRemovalsIncluded() {
        let mirrored = store()
        local.values["shared"] = "old"
        cloud.values["shared"] = nil
        var changed: [String] = []
        mirrored.onChange = { changed += $0 }

        mirrored.cloudChanged(reason: .server, keys: ["shared", "other"])

        #expect(local.values["shared"] == nil)
        #expect(changed == ["shared"])
    }

    @Test func anEqualValueIsNotAChange() {
        let mirrored = store()
        local.values["shared"] = Data([1, 2])
        cloud.values["shared"] = Data([1, 2])
        var changed: [String] = []
        mirrored.onChange = { changed += $0 }

        mirrored.cloudChanged(reason: .server, keys: ["shared"])

        #expect(changed.isEmpty)
    }

    @Test func aNewAccountNeverResetsThisPhoneToDefaults() {
        let mirrored = store()
        local.values["shared"] = "mine"

        mirrored.cloudChanged(reason: .accountChange, keys: ["shared"])

        #expect(local.values["shared"] as? String == "mine")
        #expect(cloud.values["shared"] as? String == "mine")
    }

    @Test func theNotificationReachesTheStore() {
        let center = NotificationCenter()
        let mirrored = store()
        mirrored.start(observing: center)
        cloud.values["shared"] = "theirs"

        center.post(name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: nil, userInfo: [
            NSUbiquitousKeyValueStoreChangeReasonKey: NSUbiquitousKeyValueStoreServerChange,
            NSUbiquitousKeyValueStoreChangedKeysKey: ["shared"],
        ])

        #expect(local.values["shared"] as? String == "theirs")
    }
}
