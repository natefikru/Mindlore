import Foundation

nonisolated enum SpeechEngine: String, Codable, Sendable, CaseIterable {
    // Text appears while the user talks. Falls back to onDevice for a recording this phone
    // can't run live, so picking it never leaves an entry without text.
    case onDeviceLive
    case onDevice
    case cloud

    // Whether a recording should run a live session. Only onDeviceLive does; someone who picked
    // onDevice on a capable phone chose not to watch text move while they speak.
    var wantsLiveSession: Bool { self == .onDeviceLive }
}

nonisolated enum SpeechEngineLabel {
    static func short(_ engine: SpeechEngine) -> String {
        switch engine {
        case .onDeviceLive: "Live on this iPhone"
        case .onDevice: "This iPhone"
        case .cloud: "OpenAI"
        }
    }
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
