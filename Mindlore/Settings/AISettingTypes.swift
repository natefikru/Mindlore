import Foundation

nonisolated enum SpeechEngine: String, Codable, Sendable, CaseIterable {
    case onDevice
    case cloud
}

nonisolated enum TitleGenerator: String, Codable, Sendable, CaseIterable {
    case off
    case onDevice
    case openAI
}

nonisolated enum InsightsTrigger: String, Codable, Sendable, CaseIterable {
    case automatic
    case manual
}

nonisolated struct CustomInsightPrompt: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var instructions: String
    var enabled: Bool
}
