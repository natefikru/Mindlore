import Foundation

// Builds the clients each AI job uses from the current settings, so a settings change applies
// to the next request without restarting anything.
enum AIServices {
    static func titleGenerator(settings: SettingsStore, accounts: ProviderAccountStore, http: any HTTPClient) -> Result<TitleCoordinator.Generator, AIJobFailure> {
        switch settings.titleGenerator {
        case .off:
            return .failure(AIJobFailure(raw: "settings.off"))
        case .onDevice:
            guard FoundationModelsAvailability.isAvailable else {
                return .failure(AIJobFailure(FoundationModelsAvailability.unavailableReason))
            }
            return .success(.init(generator: FoundationModelsTextGenerator(), model: "", label: FoundationModelsTextGenerator.label))
        case .openAI:
            guard settings.aiEnabled else { return .failure(AIJobFailure(raw: "settings.aiOff")) }
            guard let provider = accounts.resolve(.text) else { return .failure(AIJobFailure(.missingKey)) }
            let generator = OpenAICompatibleTextGenerator(baseURL: provider.account.baseURL, apiKey: provider.apiKey, http: http)
            return .success(.init(generator: generator, model: provider.model, label: "openai:\(provider.model)"))
        }
    }
}

extension Result {
    var isSuccess: Bool {
        if case .success = self { true } else { false }
    }
}
