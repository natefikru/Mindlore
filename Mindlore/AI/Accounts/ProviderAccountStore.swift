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
    // Shared by the settings screen and every AI client, so tests and UI tests can swap it.
    @ObservationIgnored let http: any HTTPClient
    // Bumped whenever a key is saved or removed, so views that show key state refresh.
    private(set) var keyRevision = 0
    // The provider's model list, once loaded, shared by every model picker.
    private(set) var availableModels: [String] = []
    // Whether a usable key exists, so views can ask without a Keychain read on every render.
    private(set) var hasUsableKey = false

    init(settings: SettingsStore, secrets: any SecretStore = KeychainSecretStore(), http: any HTTPClient = URLSessionHTTPClient(), diagnostics: DiagnosticsLog = .shared) {
        self.settings = settings
        self.secrets = secrets
        self.http = http
        self.diagnostics = diagnostics
        refreshKeyState()
    }

    private func refreshKeyState() {
        hasUsableKey = settings.providerAccounts.contains(where: keyIsPresent)
    }

    // An account is only added once its key has been written, so a Keychain error means the key is
    // there and locked, not missing. Reading it as missing told the user their key had vanished.
    private func keyIsPresent(_ account: ProviderAccount) -> Bool {
        switch readKey(account) {
        case .success(let key): key?.isEmpty == false
        case .failure: true
        }
    }

    private func readKey(_ account: ProviderAccount) -> Result<String?, AIError> {
        do {
            return .success(try secrets.read(account: account.id.uuidString))
        } catch {
            let status = (error as? SecretStoreError).map { Int($0.status) } ?? 0
            diagnostics.record("ai.keyUnreadable", ["status": .int(status)])
            return .failure(.keyUnavailable)
        }
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
        // Saving a key is the consent: titles, insights, and Ask all gate on `aiEnabled` before
        // they'll touch OpenAI, so leaving it off left a saved key inert until the user found the
        // separate "Use AI" toggle (owner, 2026-09-22).
        if !settings.aiEnabled { settings.aiEnabled = true }
        keyRevision += 1
        refreshKeyState()
        diagnostics.record("ai.keySaved", ["provider": .string(ProviderPreset.openAI.id)])
        return account
    }

    func remove(_ account: ProviderAccount) throws {
        try secrets.delete(account: account.id.uuidString)
        settings.providerAccounts.removeAll { $0.id == account.id }
        availableModels = []
        if settings.speechAccountID == account.id { settings.speechAccountID = nil }
        if settings.pageAccountID == account.id { settings.pageAccountID = nil }
        if settings.textAccountID == account.id { settings.textAccountID = nil }
        keyRevision += 1
        refreshKeyState()
        diagnostics.record("ai.keyRemoved", ["provider": .string(account.presetID ?? "custom")])
    }

    func hasKey(for account: ProviderAccount) -> Bool {
        _ = keyRevision
        return keyIsPresent(account)
    }

    // The account chosen for a capability, without touching the Keychain.
    func settingsAccount(for capability: AICapability) -> ProviderAccount? {
        settings.account(for: capability)
    }

    // Fails with `missingKey` when the capability has no account or its account has no key, and
    // `keyUnavailable` when the Keychain refused the read. AI being on is checked by callers.
    func resolve(_ capability: AICapability) -> Result<ResolvedProvider, AIError> {
        guard let account = settings.account(for: capability) else { return .failure(.missingKey) }
        return readKey(account).flatMap { key in
            guard let key, !key.isEmpty else { return .failure(.missingKey) }
            return .success(ResolvedProvider(account: account, apiKey: key, model: settings.model(for: capability)))
        }
    }

    func testConnection() async -> Result<[String], AIError> {
        guard let account = openAIAccount else { return .failure(.missingKey) }
        let key: String
        switch readKey(account) {
        case .success(let read?) where !read.isEmpty: key = read
        case .success: return .failure(.missingKey)
        case .failure(let error): return .failure(error)
        }
        do {
            let models = try await OpenAICompatibleModelList(baseURL: account.baseURL, apiKey: key, http: http).fetch()
            availableModels = models
            diagnostics.record("ai.connectionTested", ["ok": true, "models": .int(models.count)])
            return .success(models)
        } catch {
            let mapped = error as? AIError ?? .invalidResponse
            diagnostics.record("ai.connectionTested", ["ok": false, "error": .string(mapped.caseName)])
            return .failure(mapped)
        }
    }
}
