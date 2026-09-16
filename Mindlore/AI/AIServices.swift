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

extension AIServices {
    static func pageTranscriber(settings: SettingsStore, accounts: ProviderAccountStore) -> Result<PageTranscriptionCoordinator.Transcription, AIJobFailure> {
        guard settings.aiEnabled else { return .failure(AIJobFailure(raw: "settings.aiOff")) }
        guard let provider = accounts.resolve(.pages) else { return .failure(AIJobFailure(.missingKey)) }
        let generator = OpenAICompatibleTextGenerator(baseURL: provider.account.baseURL, apiKey: provider.apiKey, http: accounts.http)
        return .success(.init(transcriber: OpenAICompatiblePageTranscriber(generator: generator, model: provider.model), label: "openai:\(provider.model)"))
    }

    static func pagesUsable(settings: SettingsStore, accounts: ProviderAccountStore) -> Bool {
        settings.aiEnabled && accounts.hasUsableKey && accounts.settingsAccount(for: .pages) != nil
    }
}

extension AIServices {
    static func insightsGenerator(settings: SettingsStore, accounts: ProviderAccountStore) -> Result<InsightsCoordinator.Generator, AIJobFailure> {
        guard settings.aiEnabled else { return .failure(AIJobFailure(raw: "settings.aiOff")) }
        guard let provider = accounts.resolve(.text) else { return .failure(AIJobFailure(.missingKey)) }
        let generator = OpenAICompatibleTextGenerator(baseURL: provider.account.baseURL, apiKey: provider.apiKey, http: accounts.http)
        return .success(.init(generator: generator, model: provider.model, label: "openai:\(provider.model)"))
    }

    static func insightSections(_ settings: SettingsStore) -> InsightSections {
        InsightSections(
            summary: settings.insightSummary,
            moods: settings.insightMoods,
            themes: settings.insightThemes,
            tags: settings.insightTags,
            mentions: settings.insightMentions,
            openThreads: settings.insightOpenThreads,
            cleanedText: settings.insightCleanedText,
            suggestEntryDates: settings.suggestEntryDates,
            customPrompts: settings.customInsightPrompts
        )
    }

    // Whether the automatic pass should flag insights for an entry right now.
    static func automaticInsightsUsable(settings: SettingsStore, accounts: ProviderAccountStore) -> Bool {
        settings.aiEnabled && settings.insightsTrigger == .automatic && accounts.hasUsableKey
            && accounts.settingsAccount(for: .text) != nil && !insightSections(settings).isEmpty
    }
}

extension Result {
    var isSuccess: Bool {
        if case .success = self { true } else { false }
    }
}
