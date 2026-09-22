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

// Who reads an entry for its insights (summary, mood, areas, tags, names, loose ends). Built like
// TitleGenerator. On device is what lets the map, Today, and Reflect fill in with no key at all.
nonisolated enum InsightsGenerator: String, Codable, Sendable, CaseIterable {
    case off
    case onDevice
    case openAI
}

// Who answers a question in Ask. Built like TitleGenerator: the user's choice, not a rule with
// an exception, and picked once the first time Ask opens.
nonisolated enum AskGenerator: String, Codable, Sendable, CaseIterable {
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
