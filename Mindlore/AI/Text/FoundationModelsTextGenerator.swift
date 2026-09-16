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
// keep prompts short. It ignores request schemas and returns plain text.
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
            let response = try await session.respond(to: request.user)
            return TextResult(text: response.content, model: Self.label, inputTokens: nil, outputTokens: nil)
        } catch {
            throw OnDeviceModelError.generationFailed
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
