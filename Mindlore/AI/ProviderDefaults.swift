import Foundation

// Default model IDs for the OpenAI preset, confirmed against /models by OpenAILiveTests.
nonisolated enum ProviderDefaults {
    static let openAIBaseURL = URL(string: "https://api.openai.com/v1")!
    static let speechModel = "gpt-transcribe"
    static let textModel = "gpt-5.6-luna"
    static let pageModel = "gpt-5.6-terra"
}
