import Foundation
import FoundationModels

nonisolated enum OnDeviceModelError: Error, Equatable {
    case unavailable(Reason)
    case generationFailed

    enum Reason: String, Sendable {
        case deviceNotEligible
        case appleIntelligenceNotEnabled
        case modelNotReady
        case unknown
    }
}

// Apple's on-device model. Free, offline, and small: about 4,096 tokens per session, so callers
// keep prompts short. A request with a schema is answered through guided generation, which holds
// the model to that shape and returns it as JSON, so the same parser reads the answer whichever
// model wrote it. Without a schema it returns plain text.
nonisolated struct FoundationModelsTextGenerator: TextGenerator {
    static let label = "apple:foundation"

    func generate(_ request: TextRequest) async throws -> TextResult {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            break
        case .unavailable(let reason):
            throw OnDeviceModelError.unavailable(Self.reason(reason))
        }
        let session = LanguageModelSession(model: model, instructions: request.system)
        do {
            if let schema = request.schema {
                let generation = try Self.generationSchema(schema, name: request.schemaName)
                let options = GenerationOptions(maximumResponseTokens: request.maxOutputTokens)
                let response = try await session.respond(to: request.user, schema: generation, options: options)
                return TextResult(text: response.content.jsonString, model: Self.label, inputTokens: nil, outputTokens: nil)
            }
            let response = try await session.respond(to: request.user)
            return TextResult(text: response.content, model: Self.label, inputTokens: nil, outputTokens: nil)
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            throw AIError.contextTooLong
        } catch {
            throw OnDeviceModelError.generationFailed
        }
    }

    // The request's JSON Schema as a guided-generation schema. Every named schema needs a unique
    // name, so each takes its path from the root. A nullable property becomes an optional one: the
    // model may leave it out, and every parser here already reads a missing field as null.
    static func generationSchema(_ schema: JSONSchema, name: String) throws -> GenerationSchema {
        try GenerationSchema(root: dynamic(schema, path: name), dependencies: [])
    }

    static func dynamic(_ schema: JSONSchema, path: String) -> DynamicGenerationSchema {
        switch schema {
        case .string:
            return DynamicGenerationSchema(type: String.self)
        case .enumeration(let values, let description, _):
            return DynamicGenerationSchema(name: path, description: description, anyOf: values)
        case .integer:
            return DynamicGenerationSchema(type: Int.self)
        case .number:
            return DynamicGenerationSchema(type: Double.self)
        case .boolean:
            return DynamicGenerationSchema(type: Bool.self)
        case .array(let items, _, _):
            return DynamicGenerationSchema(arrayOf: dynamic(items, path: path + "_item"))
        case .object(let properties, let description, _):
            return DynamicGenerationSchema(
                name: path,
                description: description,
                properties: properties.map { property in
                    DynamicGenerationSchema.Property(
                        name: property.name,
                        description: property.schema.summary,
                        schema: dynamic(property.schema, path: path + "_" + property.name),
                        isOptional: property.schema.isNullable
                    )
                }
            )
        }
    }

    static func reason(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> OnDeviceModelError.Reason {
        switch reason {
        case .deviceNotEligible: .deviceNotEligible
        case .appleIntelligenceNotEnabled: .appleIntelligenceNotEnabled
        case .modelNotReady: .modelNotReady
        @unknown default: .unknown
        }
    }
}

extension JSONSchema {
    nonisolated var summary: String? {
        switch self {
        case .string(let description, _), .enumeration(_, let description, _), .integer(let description, _),
             .number(let description, _), .boolean(let description, _), .array(_, let description, _),
             .object(_, let description, _):
            description
        }
    }

    nonisolated var isNullable: Bool {
        switch self {
        case .string(_, let nullable), .enumeration(_, _, let nullable), .integer(_, let nullable),
             .number(_, let nullable), .boolean(_, let nullable), .array(_, _, let nullable),
             .object(_, _, let nullable):
            nullable
        }
    }
}
