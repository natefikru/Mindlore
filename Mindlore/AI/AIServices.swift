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

// The text model for the account's text capability, with what to record about it.
struct ResolvedTextGenerator {
    let generator: any TextGenerator
    let model: String
    let label: String
}

extension AIServices {
    // Reads the key from the Keychain. Call when a request is about to go out.
    static func textGenerator(settings: SettingsStore, accounts: ProviderAccountStore) -> Result<ResolvedTextGenerator, AIJobFailure> {
        guard settings.aiEnabled else { return .failure(AIJobFailure(raw: "settings.aiOff")) }
        guard let provider = accounts.resolve(.text) else { return .failure(AIJobFailure(.missingKey)) }
        let generator = OpenAICompatibleTextGenerator(baseURL: provider.account.baseURL, apiKey: provider.apiKey, http: accounts.http)
        return .success(.init(generator: generator, model: provider.model, label: "openai:\(provider.model)"))
    }

    // Whether textGenerator would succeed, without touching the Keychain, for views to ask.
    static func textUsable(settings: SettingsStore, accounts: ProviderAccountStore) -> Bool {
        settings.aiEnabled && accounts.hasUsableKey && accounts.settingsAccount(for: .text) != nil
    }

    // Ask's provider, from the setting the user picked, the same shape as titleGenerator.
    static func askGenerator(settings: SettingsStore, accounts: ProviderAccountStore) -> Result<AskProvider, AIJobFailure> {
        switch settings.askGenerator {
        case .off:
            return .failure(AIJobFailure(raw: "settings.off"))
        case .onDevice:
            guard FoundationModelsAvailability.isAvailable else {
                return .failure(AIJobFailure(FoundationModelsAvailability.unavailableReason))
            }
            return .success(.init(generator: FoundationModelsTextGenerator(), model: "", label: FoundationModelsTextGenerator.label, kind: .onDevice))
        case .openAI:
            return textGenerator(settings: settings, accounts: accounts)
                .map { .init(generator: $0.generator, model: $0.model, label: $0.label, kind: .openAI) }
        }
    }

    static func askUsable(settings: SettingsStore, accounts: ProviderAccountStore) -> Bool {
        switch settings.askGenerator {
        case .off: false
        case .onDevice: FoundationModelsAvailability.isAvailable
        case .openAI: textUsable(settings: settings, accounts: accounts)
        }
    }

    static func insightsGenerator(settings: SettingsStore, accounts: ProviderAccountStore) -> Result<InsightsCoordinator.Generator, AIJobFailure> {
        textGenerator(settings: settings, accounts: accounts)
    }

    static func insightSections(_ settings: SettingsStore) -> InsightSections {
        InsightSections(
            summary: settings.insightSummary,
            moods: settings.insightMoods,
            lifeAreas: settings.insightLifeAreas,
            tags: settings.insightTags,
            mentions: settings.insightMentions,
            looseEnds: settings.insightLooseEnds,
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
