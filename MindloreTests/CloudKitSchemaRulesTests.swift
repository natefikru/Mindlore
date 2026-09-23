import Foundation
import SwiftData
import Testing
@testable import Mindlore

// Mirrors the constraints CloudKit sync puts on a SwiftData schema, so models stay
// syncable while the app has no iCloud entitlement to load a CloudKit store with.
enum CloudKitSchemaRules {
    static func violations(in schema: Schema) -> [String] {
        var problems: [String] = []
        for entity in schema.entities {
            if !entity.uniquenessConstraints.isEmpty {
                problems.append("\(entity.name) has uniqueness constraints")
            }
            for attribute in entity.attributes {
                if attribute.isUnique {
                    problems.append("\(entity.name).\(attribute.name) is unique")
                }
                if !attribute.isOptional && attribute.defaultValue == nil {
                    problems.append("\(entity.name).\(attribute.name) is non-optional with no default value")
                }
            }
            for relationship in entity.relationships {
                if !relationship.isOptional {
                    problems.append("\(entity.name).\(relationship.name) is a non-optional relationship")
                }
                if relationship.inverseName == nil {
                    problems.append("\(entity.name).\(relationship.name) has no inverse")
                }
                if relationship.deleteRule == .deny {
                    problems.append("\(entity.name).\(relationship.name) uses the deny delete rule")
                }
            }
        }
        return problems
    }
}

@Model
final class NonSyncableFixture {
    @Attribute(.unique) var code: String
    var name: String

    init(code: String, name: String) {
        self.code = code
        self.name = name
    }
}

@Model
final class OneWayOwnerFixture {
    @Relationship(deleteRule: .deny) var child: OneWayChildFixture?

    init() {}
}

@Model
final class OneWayChildFixture {
    var label: String = ""

    init() {}
}

struct CloudKitSchemaRulesTests {
    @Test func appSchemaFollowsCloudKitRules() {
        #expect(CloudKitSchemaRules.violations(in: ModelContainerFactory.schema) == [])
    }

    @Test func rulesCatchUniqueAndMissingDefaults() {
        let problems = CloudKitSchemaRules.violations(in: Schema([NonSyncableFixture.self]))

        #expect(problems.contains("NonSyncableFixture.code is unique"))
        #expect(problems.contains("NonSyncableFixture.name is non-optional with no default value"))
    }

    @Test func rulesCatchMissingInversesAndDeny() {
        let problems = CloudKitSchemaRules.violations(in: Schema([OneWayOwnerFixture.self, OneWayChildFixture.self]))

        #expect(problems.contains("OneWayOwnerFixture.child has no inverse"))
        #expect(problems.contains("OneWayOwnerFixture.child uses the deny delete rule"))
    }

    // The app is entitled for iCloud, so only the one configuration that asks for CloudKit may
    // get it. A test run or a demo journal mirroring into the owner's iCloud would be a real leak.
    @Test func onlyTheDefaultStoreMirrorsToCloudKit() throws {
        let container = "iCloud.com.natefikru.mindlore.test"
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("fixture.store")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let inMemory = try ModelContainerFactory.make(.inMemory, cloudKitContainerID: container)
        let onDisk = try ModelContainerFactory.make(.file(file), cloudKitContainerID: container)

        #expect(inMemory.configurations.allSatisfy { $0.cloudKitContainerIdentifier == nil })
        #expect(onDisk.configurations.allSatisfy { $0.cloudKitContainerIdentifier == nil })
    }
}
