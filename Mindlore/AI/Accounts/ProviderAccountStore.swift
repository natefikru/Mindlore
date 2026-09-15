import Foundation
import Observation

// A provider account plus the pieces a request needs, resolved for one capability.
nonisolated struct ResolvedProvider: Sendable, Equatable {
    let account: ProviderAccount
    let apiKey: String
    let model: String
}

// Owns provider accounts and their Keychain keys. Settings hold the non-secret parts.
@Observable
final class ProviderAccountStore {
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let secrets: any SecretStore
    @ObservationIgnored private let diagnostics: DiagnosticsLog
    // Bumped whenever a key is saved or removed, so views that show key state refresh.
    private(set) var keyRevision = 0

    init(settings: SettingsStore, secrets: any SecretStore = KeychainSecretStore(), diagnostics: DiagnosticsLog = .shared) {
        self.settings = settings
        self.secrets = secrets
        self.diagnostics = diagnostics
    }

    var openAIAccount: ProviderAccount? {
        settings.providerAccounts.first { $0.presetID == ProviderPreset.openAI.id }
    }

    // Creates the OpenAI account on first use and points every capability without an account at it.
    @discardableResult
    func saveOpenAIKey(_ apiKey: String) throws -> ProviderAccount {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = openAIAccount ?? .openAI()
        try secrets.write(trimmed, account: account.id.uuidString)
        if openAIAccount == nil {
            settings.providerAccounts.append(account)
        }
        if settings.speechAccountID == nil { settings.speechAccountID = account.id }
        if settings.pageAccountID == nil { settings.pageAccountID = account.id }
        if settings.textAccountID == nil { settings.textAccountID = account.id }
        keyRevision += 1
        diagnostics.record("ai.keySaved", ["provider": .string(ProviderPreset.openAI.id)])
        return account
    }

    func remove(_ account: ProviderAccount) throws {
        try secrets.delete(account: account.id.uuidString)
        settings.providerAccounts.removeAll { $0.id == account.id }
        if settings.speechAccountID == account.id { settings.speechAccountID = nil }
        if settings.pageAccountID == account.id { settings.pageAccountID = nil }
        if settings.textAccountID == account.id { settings.textAccountID = nil }
        keyRevision += 1
        diagnostics.record("ai.keyRemoved", ["provider": .string(account.presetID ?? "custom")])
    }

    func hasKey(for account: ProviderAccount) -> Bool {
        _ = keyRevision
        return ((try? secrets.read(account: account.id.uuidString)) ?? nil)?.isEmpty == false
    }

    // Nil when the capability has no account or its account has no key. AI being on is checked by callers.
    func resolve(_ capability: AICapability) -> ResolvedProvider? {
        guard let account = settings.account(for: capability),
              let key = (try? secrets.read(account: account.id.uuidString)) ?? nil,
              !key.isEmpty else { return nil }
        return ResolvedProvider(account: account, apiKey: key, model: settings.model(for: capability))
    }

    func testConnection(http: any HTTPClient) async -> Result<[String], AIError> {
        guard let account = openAIAccount, let key = (try? secrets.read(account: account.id.uuidString)) ?? nil else {
            return .failure(.missingKey)
        }
        do {
            let models = try await OpenAICompatibleModelList(baseURL: account.baseURL, apiKey: key, http: http).fetch()
            diagnostics.record("ai.connectionTested", ["ok": true, "models": .int(models.count)])
            return .success(models)
        } catch {
            let mapped = error as? AIError ?? .invalidResponse
            diagnostics.record("ai.connectionTested", ["ok": false, "error": .string(mapped.caseName)])
            return .failure(mapped)
        }
    }
}
