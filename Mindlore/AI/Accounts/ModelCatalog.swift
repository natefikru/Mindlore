import Foundation

// Sorts a provider's model list into the ones worth offering for each job. Anything the filters miss
// can still be typed in by hand, so a new model never has to wait for an app update.
nonisolated enum ModelCatalog {
    static func speechModels(in models: [String]) -> [String] {
        models.filter { $0.contains("transcribe") || $0.hasPrefix("whisper") }
    }

    // Text and page work both need a general chat model; pages also need image input.
    static func textModels(in models: [String]) -> [String] {
        let excluded = ["transcribe", "tts", "audio", "realtime", "embedding", "image", "moderation", "search", "whisper", "codex", "instruct", "dall-e", "sora"]
        return models.filter { model in
            (model.hasPrefix("gpt") || model.hasPrefix("o1") || model.hasPrefix("o3") || model.hasPrefix("o4")) && !excluded.contains { model.contains($0) }
        }
    }

    static func models(for capability: AICapability, in models: [String]) -> [String] {
        capability == .speech ? speechModels(in: models) : textModels(in: models)
    }
}
