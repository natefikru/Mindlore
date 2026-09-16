import Foundation
import Synchronization
import Testing
@testable import Mindlore

nonisolated final class FakeSecretStore: SecretStore {
    private let secrets = Mutex<[String: String]>([:])

    func read(account: String) throws -> String? { secrets.withLock { $0[account] } }
    func write(_ secret: String, account: String) throws { secrets.withLock { $0[account] = secret } }
    func delete(account: String) throws { _ = secrets.withLock { $0.removeValue(forKey: account) } }
}

struct KeychainSecretStoreTests {
    // A unique service keeps test items away from the app's real key.
    private let store = KeychainSecretStore(service: "com.natefikru.mindlore.tests.\(UUID().uuidString)")

    @Test func roundTripOverwriteAndDelete() throws {
        let account = UUID().uuidString
        #expect(try store.read(account: account) == nil)

        try store.write("sk-first", account: account)
        #expect(try store.read(account: account) == "sk-first")

        try store.write("sk-second", account: account)
        #expect(try store.read(account: account) == "sk-second")

        try store.delete(account: account)
        #expect(try store.read(account: account) == nil)
        try store.delete(account: account)
    }

    @Test func servicesAreIsolated() throws {
        let account = UUID().uuidString
        let other = KeychainSecretStore(service: "com.natefikru.mindlore.tests.\(UUID().uuidString)")
        try store.write("sk-mine", account: account)
        defer { try? store.delete(account: account) }

        #expect(try other.read(account: account) == nil)
    }
}

@MainActor
struct ProviderAccountStoreTests {
    private func makeStores() -> (SettingsStore, ProviderAccountStore, FakeSecretStore) {
        let settings = SettingsStore(store: FakeKeyValueStore(), diagnostics: .disabled)
        let secrets = FakeSecretStore()
        return (settings, ProviderAccountStore(settings: settings, secrets: secrets, diagnostics: .disabled), secrets)
    }

    @Test func savingAKeyCreatesTheOpenAIAccountForEveryCapability() throws {
        let (settings, accounts, secrets) = makeStores()

        let account = try accounts.saveOpenAIKey("  sk-live  ")

        #expect(settings.providerAccounts == [account])
        #expect(account.baseURL == ProviderDefaults.openAIBaseURL)
        #expect(try secrets.read(account: account.id.uuidString) == "sk-live")
        #expect(settings.speechAccountID == account.id)
        #expect(settings.pageAccountID == account.id)
        #expect(settings.textAccountID == account.id)
        #expect(accounts.hasKey(for: account))
        #expect(accounts.resolve(.text) == ResolvedProvider(account: account, apiKey: "sk-live", model: ProviderDefaults.textModel))
        #expect(accounts.resolve(.speech)?.model == ProviderDefaults.speechModel)
        #expect(accounts.resolve(.pages)?.model == ProviderDefaults.pageModel)
    }

    @Test func replacingAKeyKeepsTheSameAccount() throws {
        let (settings, accounts, _) = makeStores()
        let first = try accounts.saveOpenAIKey("sk-1")
        let second = try accounts.saveOpenAIKey("sk-2")

        #expect(first.id == second.id)
        #expect(settings.providerAccounts.count == 1)
        #expect(accounts.resolve(.text)?.apiKey == "sk-2")
    }

    @Test func removingAnAccountDeletesItsKeyAndClearsSelections() throws {
        let (settings, accounts, secrets) = makeStores()
        let account = try accounts.saveOpenAIKey("sk-1")

        try accounts.remove(account)

        #expect(try secrets.read(account: account.id.uuidString) == nil)
        #expect(settings.providerAccounts.isEmpty)
        #expect(settings.speechAccountID == nil && settings.pageAccountID == nil && settings.textAccountID == nil)
        #expect(accounts.resolve(.text) == nil)
    }

    @Test func theCachedKeyStateFollowsSavingAndRemoving() throws {
        let (_, accounts, _) = makeStores()
        #expect(!accounts.hasUsableKey)

        let account = try accounts.saveOpenAIKey("sk-1")
        #expect(accounts.hasUsableKey)

        try accounts.remove(account)
        #expect(!accounts.hasUsableKey)
    }

    @Test func noKeyResolvesToNothing() {
        let (settings, accounts, _) = makeStores()
        let account = ProviderAccount.openAI()
        settings.providerAccounts = [account]
        settings.textAccountID = account.id

        #expect(accounts.resolve(.text) == nil)
        #expect(!accounts.hasKey(for: account))
    }

    @Test func testConnectionReportsModelsOrTheMappedError() async throws {
        let settings = SettingsStore(store: FakeKeyValueStore(), diagnostics: .disabled)
        let http = FakeHTTPClient(FakeHTTPClient.json(200, ["data": [["id": "gpt-5.6-luna"]]]), FakeHTTPClient.error(401))
        let accounts = ProviderAccountStore(settings: settings, secrets: FakeSecretStore(), http: http, diagnostics: .disabled)
        #expect(await accounts.testConnection() == .failure(.missingKey))
        #expect(http.sent.isEmpty)

        try accounts.saveOpenAIKey("sk-1")
        #expect(await accounts.testConnection() == .success(["gpt-5.6-luna"]))
        #expect(http.sent.first?.request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-1")
        #expect(http.sent.first?.request.url?.absoluteString == "https://api.openai.com/v1/models")
        #expect(await accounts.testConnection() == .failure(.invalidKey))
    }
}
