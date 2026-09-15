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
            for relationship in entity.relationships where !relationship.isOptional {
                problems.append("\(entity.name).\(relationship.name) is a non-optional relationship")
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

struct CloudKitSchemaRulesTests {
    @Test func appSchemaFollowsCloudKitRules() {
        #expect(CloudKitSchemaRules.violations(in: ModelContainerFactory.schema) == [])
    }

    @Test func rulesCatchUniqueAndMissingDefaults() {
        let problems = CloudKitSchemaRules.violations(in: Schema([NonSyncableFixture.self]))

        #expect(problems.contains("NonSyncableFixture.code is unique"))
        #expect(problems.contains("NonSyncableFixture.name is non-optional with no default value"))
    }
}
