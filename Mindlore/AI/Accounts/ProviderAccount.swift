import Foundation

nonisolated enum ProviderKind: String, Codable, Sendable {
    case openAICompatible
}

nonisolated enum AICapability: String, Codable, Sendable, CaseIterable {
    case speech
    case pages
    case text
}

// Non-secret account settings. The key lives in Keychain under the account's id.
nonisolated struct ProviderAccount: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var kindRaw: String
    var name: String
    var baseURL: URL
    var presetID: String?

    var kind: ProviderKind? { ProviderKind(rawValue: kindRaw) }

    static func openAI(id: UUID = UUID()) -> ProviderAccount {
        ProviderAccount(id: id, kindRaw: ProviderKind.openAICompatible.rawValue, name: ProviderPreset.openAI.name, baseURL: ProviderPreset.openAI.baseURL, presetID: ProviderPreset.openAI.id)
    }
}

nonisolated struct ProviderPreset: Sendable {
    let id: String
    let name: String
    let baseURL: URL
    let speechModel: String
    let pageModel: String
    let textModel: String

    static let openAI = ProviderPreset(
        id: "openai",
        name: "OpenAI",
        baseURL: ProviderDefaults.openAIBaseURL,
        speechModel: ProviderDefaults.speechModel,
        pageModel: ProviderDefaults.pageModel,
        textModel: ProviderDefaults.textModel
    )
}
