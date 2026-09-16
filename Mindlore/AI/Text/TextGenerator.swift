import Foundation

nonisolated struct TextImage: Sendable, Equatable {
    enum Detail: String, Sendable {
        case low
        case high
        case auto
    }

    let jpegData: Data
    var detail: Detail = .high
}

nonisolated struct TextRequest: Sendable {
    var model: String
    var system: String
    var user: String
    var images: [TextImage] = []
    // With a schema the response text is JSON matching it; without one it is free text.
    var schema: JSONSchema?
    var schemaName: String = "result"
    var maxOutputTokens: Int?
}

nonisolated struct TextResult: Sendable, Equatable {
    let text: String
    let model: String
    let inputTokens: Int?
    let outputTokens: Int?
}

// One capability, many possible vendors. Implementations throw AIError.
nonisolated protocol TextGenerator: Sendable {
    func generate(_ request: TextRequest) async throws -> TextResult
}
