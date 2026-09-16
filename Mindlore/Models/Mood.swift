import Foundation

// The closed mood vocabulary. Raw values are stored on insights, so renaming or removing a case
// makes old insights read that mood as nil; adding cases is safe. MoodTests pins the list.
nonisolated enum MoodCategory: String, CaseIterable, Codable, Sendable {
    case joyful, calm, connected, reflective, anxious, angry, low, drained

    enum Energy: String, Sendable {
        case low, medium, high
    }

    var name: String { rawValue.capitalized }

    // -1 unpleasant, 0 neutral, +1 pleasant.
    var valence: Int {
        switch self {
        case .joyful, .calm, .connected: 1
        case .reflective: 0
        case .anxious, .angry, .low, .drained: -1
        }
    }

    var energy: Energy {
        switch self {
        case .joyful, .anxious, .angry: .high
        case .connected, .reflective: .medium
        case .calm, .low, .drained: .low
        }
    }
}

nonisolated enum Mood: String, CaseIterable, Codable, Sendable {
    case joyful, excited, energized, proud, confident, inspired
    case content, calm, grateful, relieved, hopeful
    case loved, connected, supported, compassionate
    case reflective, curious, nostalgic, uncertain, conflicted, neutral
    case anxious, stressed, overwhelmed, restless, afraid, insecure
    case frustrated, irritated, angry, resentful, jealous
    case sad, lonely, disappointed, hurt, guilty, ashamed, hopeless
    case tired, numb, bored, unmotivated, burnedOut

    var category: MoodCategory {
        switch self {
        case .joyful, .excited, .energized, .proud, .confident, .inspired: .joyful
        case .content, .calm, .grateful, .relieved, .hopeful: .calm
        case .loved, .connected, .supported, .compassionate: .connected
        case .reflective, .curious, .nostalgic, .uncertain, .conflicted, .neutral: .reflective
        case .anxious, .stressed, .overwhelmed, .restless, .afraid, .insecure: .anxious
        case .frustrated, .irritated, .angry, .resentful, .jealous: .angry
        case .sad, .lonely, .disappointed, .hurt, .guilty, .ashamed, .hopeless: .low
        case .tired, .numb, .bored, .unmotivated, .burnedOut: .drained
        }
    }

    var name: String {
        self == .burnedOut ? "burned out" : rawValue
    }

    var meaning: String {
        switch self {
        case .joyful: "happy, light, glad"
        case .excited: "eager, looking forward to something"
        case .energized: "motivated, ready to act"
        case .proud: "satisfied with something done"
        case .confident: "sure of yourself or a decision"
        case .inspired: "struck by an idea or possibility"
        case .content: "things feel fine as they are"
        case .calm: "settled, unhurried"
        case .grateful: "thankful for someone or something"
        case .relieved: "a worry has lifted"
        case .hopeful: "expecting things to get better"
        case .loved: "cared for by someone"
        case .connected: "close to the people around you"
        case .supported: "someone has your back"
        case .compassionate: "feeling for someone else"
        case .reflective: "thinking things over"
        case .curious: "wanting to understand something"
        case .nostalgic: "drawn back to the past"
        case .uncertain: "unsure what to think or do"
        case .conflicted: "pulled in two directions"
        case .neutral: "no strong feeling either way"
        case .anxious: "worried about what might happen"
        case .stressed: "under pressure"
        case .overwhelmed: "too much at once"
        case .restless: "unable to settle"
        case .afraid: "scared or threatened"
        case .insecure: "doubting yourself or your place"
        case .frustrated: "blocked or thwarted"
        case .irritated: "annoyed by small things"
        case .angry: "strongly upset at someone or something"
        case .resentful: "holding onto a grievance"
        case .jealous: "wanting what someone else has"
        case .sad: "down, sorrowful"
        case .lonely: "missing connection"
        case .disappointed: "let down by someone or something"
        case .hurt: "emotionally wounded"
        case .guilty: "regret over something you did"
        case .ashamed: "feeling bad about who you are"
        case .hopeless: "unable to see things improving"
        case .tired: "short on energy or sleep"
        case .numb: "feeling little of anything"
        case .bored: "nothing holds your interest"
        case .unmotivated: "hard to get started"
        case .burnedOut: "worn down over a long stretch"
        }
    }
}

nonisolated enum MentionKind: String, CaseIterable, Codable, Sendable {
    case person, place, organization, project, event, other
}

// A named thing in one entry. Not resolved across entries: "Sarah" twice is two mentions.
nonisolated struct Mention: Codable, Equatable, Sendable {
    let name: String
    let kindRaw: String

    var kind: MentionKind { MentionKind(rawValue: kindRaw) ?? .other }
}

nonisolated struct CustomInsightResult: Codable, Equatable, Sendable {
    let promptID: UUID
    let name: String
    let content: String
}
