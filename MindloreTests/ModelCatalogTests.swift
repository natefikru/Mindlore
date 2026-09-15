import Foundation
import Testing
@testable import Mindlore

struct ModelCatalogTests {
    // A real /models answer, trimmed: chat models, transcription models, and things that fit neither.
    private let models = [
        "dall-e-3", "gpt-3.5-turbo", "gpt-4.1", "gpt-4o", "gpt-4o-mini-transcribe", "gpt-4o-mini-tts",
        "gpt-4o-realtime", "gpt-4o-search-preview", "gpt-4o-transcribe", "gpt-5.1-codex", "gpt-5.6-luna",
        "gpt-5.6-terra", "gpt-6-astra", "gpt-audio", "gpt-image-1", "gpt-transcribe", "o3", "sora-2",
        "text-embedding-3-small", "whisper-1",
    ]

    @Test func speechModelsAreTranscriptionOnes() {
        #expect(ModelCatalog.speechModels(in: models) == ["gpt-4o-mini-transcribe", "gpt-4o-transcribe", "gpt-transcribe", "whisper-1"])
    }

    @Test func textModelsAreChatOnesWithoutSpecialPurposeVariants() {
        #expect(ModelCatalog.textModels(in: models) == ["gpt-3.5-turbo", "gpt-4.1", "gpt-4o", "gpt-5.6-luna", "gpt-5.6-terra", "gpt-6-astra", "o3"])
    }

    @Test func pagesUseTheSameListAsText() {
        #expect(ModelCatalog.models(for: .pages, in: models) == ModelCatalog.models(for: .text, in: models))
        #expect(ModelCatalog.models(for: .speech, in: models) == ModelCatalog.speechModels(in: models))
    }

    @Test func anEmptyListStaysEmpty() {
        #expect(ModelCatalog.textModels(in: []).isEmpty)
        #expect(ModelCatalog.speechModels(in: []).isEmpty)
    }

    @MainActor
    @Test func testingTheConnectionFillsTheSharedModelListAndRemovingTheKeyClearsIt() async throws {
        let settings = SettingsStore(store: FakeKeyValueStore(), diagnostics: .disabled)
        let http = FakeHTTPClient(FakeHTTPClient.json(200, ["data": [["id": "gpt-5.6-luna"], ["id": "gpt-transcribe"]]]))
        let accounts = ProviderAccountStore(settings: settings, secrets: FakeSecretStore(), http: http, diagnostics: .disabled)
        let account = try accounts.saveOpenAIKey("sk-1")

        _ = await accounts.testConnection()
        #expect(accounts.availableModels == ["gpt-5.6-luna", "gpt-transcribe"])

        try accounts.remove(account)
        #expect(accounts.availableModels.isEmpty)
    }
}
