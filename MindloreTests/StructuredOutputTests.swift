import Foundation
import Testing
@testable import Mindlore

struct StructuredOutputTests {
    private func object(_ schema: JSONSchema) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: try schema.jsonData()) as? [String: Any])
    }

    @Test func objectsAreClosedAndRequireEveryProperty() throws {
        let schema = JSONSchema.object([
            .init("summary", .string(nullable: true)),
            .init("tags", .array(.string())),
        ])
        let json = try object(schema)

        #expect(json["type"] as? String == "object")
        #expect(json["additionalProperties"] as? Bool == false)
        #expect(json["required"] as? [String] == ["summary", "tags"])
        let properties = try #require(json["properties"] as? [String: [String: Any]])
        #expect(properties["summary"]?["type"] as? [String] == ["string", "null"])
        #expect((properties["tags"]?["items"] as? [String: Any])?["type"] as? String == "string")
    }

    @Test func nullableEnumsListNullAmongTheirValues() throws {
        let json = try object(.enumeration(["calm", "sad"], description: "mood", nullable: true))

        #expect(json["type"] as? [String] == ["string", "null"])
        let values = try #require(json["enum"] as? [Any])
        #expect(values.count == 3)
        #expect(values.last is NSNull)
        #expect(json["description"] as? String == "mood")
    }

    private struct Sample: Decodable, Equatable {
        let text: String
    }

    @Test func parsesCleanFencedAndWrappedJSON() throws {
        #expect(try StructuredOutputParser.decode(Sample.self, from: #"{"text":"hi"}"#) == Sample(text: "hi"))
        #expect(try StructuredOutputParser.decode(Sample.self, from: "```json\n{\"text\": \"hi\"}\n```") == Sample(text: "hi"))
        #expect(try StructuredOutputParser.decode(Sample.self, from: "Here you go: {\"text\": \"a } b\"} hope that helps") == Sample(text: "a } b"))
        #expect(try StructuredOutputParser.decode(Sample.self, from: #"{"text":"quote \" and { brace"}"#) == Sample(text: "quote \" and { brace"))
    }

    @Test func truncatedOrWrongShapedJSONIsAnInvalidResponse() {
        #expect(throws: AIError.invalidResponse) { try StructuredOutputParser.decode(Sample.self, from: #"{"text": "cut off"#) }
        #expect(throws: AIError.invalidResponse) { try StructuredOutputParser.decode(Sample.self, from: #"{"other": 1}"#) }
        #expect(throws: AIError.invalidResponse) { try StructuredOutputParser.decode(Sample.self, from: "no json at all") }
    }
}
