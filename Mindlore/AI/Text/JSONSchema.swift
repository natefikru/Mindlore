import Foundation

// The subset of JSON Schema every structured-output provider accepts: objects, strings,
// numbers, booleans, arrays, and string enums. No min/max, patterns, or recursion.
nonisolated indirect enum JSONSchema: Sendable, Equatable {
    case string(description: String? = nil, nullable: Bool = false)
    case enumeration([String], description: String? = nil, nullable: Bool = false)
    case integer(description: String? = nil, nullable: Bool = false)
    case number(description: String? = nil, nullable: Bool = false)
    case boolean(description: String? = nil, nullable: Bool = false)
    case array(JSONSchema, description: String? = nil, nullable: Bool = false)
    case object([Property], description: String? = nil, nullable: Bool = false)

    nonisolated struct Property: Sendable, Equatable {
        let name: String
        let schema: JSONSchema

        init(_ name: String, _ schema: JSONSchema) {
            self.name = name
            self.schema = schema
        }
    }

    // Strict-mode form: every object closes additionalProperties and requires every property;
    // optional values are expressed as nullable types instead.
    var jsonObject: [String: Any] {
        switch self {
        case .string(let description, let nullable):
            return Self.node("string", description, nullable)
        case .enumeration(let values, let description, let nullable):
            var node = Self.node("string", description, nullable)
            node["enum"] = nullable ? values.map { $0 as Any } + [NSNull()] : values
            return node
        case .integer(let description, let nullable):
            return Self.node("integer", description, nullable)
        case .number(let description, let nullable):
            return Self.node("number", description, nullable)
        case .boolean(let description, let nullable):
            return Self.node("boolean", description, nullable)
        case .array(let items, let description, let nullable):
            var node = Self.node("array", description, nullable)
            node["items"] = items.jsonObject
            return node
        case .object(let properties, let description, let nullable):
            var node = Self.node("object", description, nullable)
            var map: [String: Any] = [:]
            for property in properties {
                map[property.name] = property.schema.jsonObject
            }
            node["properties"] = map
            node["required"] = properties.map(\.name)
            node["additionalProperties"] = false
            return node
        }
    }

    func jsonData() throws -> Data {
        try JSONSerialization.data(withJSONObject: jsonObject, options: [.sortedKeys])
    }

    private static func node(_ type: String, _ description: String?, _ nullable: Bool) -> [String: Any] {
        var node: [String: Any] = ["type": nullable ? [type, "null"] : type]
        if let description {
            node["description"] = description
        }
        return node
    }
}
