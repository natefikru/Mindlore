import Foundation

// Ways of thinking an entry can show in how its author talks about themselves: the patterns
// cognitive therapy names, kept to six a person recognises in plain words. The cloud insights
// request asks for them only on an account of the author's own life and only when clearly there
// (owner, 2026-09-24); Life counts them over a window as "How you talk to yourself". Never a
// diagnosis: they are habits of a sentence, not facts about a person.
nonisolated enum ThinkingPattern: String, CaseIterable, Codable, Sendable {
    case allOrNothing, catastrophizing, mindReading, shouldStatements, harshSelfTalk, overgeneralizing

    static let maxPerEntry = 3

    var title: String {
        switch self {
        case .allOrNothing: "All or nothing"
        case .catastrophizing: "Expecting the worst"
        case .mindReading: "Mind reading"
        case .shouldStatements: "Shoulds"
        case .harshSelfTalk: "Being hard on yourself"
        case .overgeneralizing: "One thing becomes everything"
        }
    }

    // What it sounds like, for the card, in the second person.
    var sounds: String {
        switch self {
        case .allOrNothing: "Something is a total success or a total failure, always or never."
        case .catastrophizing: "The worst outcome gets treated as the likely one."
        case .mindReading: "You're sure what someone thinks of you without them saying it."
        case .shouldStatements: "Rigid musts and shoulds aimed at yourself."
        case .harshSelfTalk: "Words about yourself you'd never say to a friend."
        case .overgeneralizing: "One bad moment becomes a rule about your life."
        }
    }

    // For the request's field description.
    var meaning: String {
        switch self {
        case .allOrNothing: "total success or total failure, always or never"
        case .catastrophizing: "treating the worst outcome as the likely one"
        case .mindReading: "sure what others think of them without evidence"
        case .shouldStatements: "rigid musts and shoulds aimed at themselves"
        case .harshSelfTalk: "calling themselves names or judging themselves harshly"
        case .overgeneralizing: "one event turned into a rule about their life"
        }
    }

    // Stored in the insights' custom results under this id, so adding them changed no model and
    // nothing in CloudKit's schema. `EntryInsights.customResults` never shows it as a card.
    static let storageID = UUID(uuidString: "7E1D0C0A-0000-4000-8000-7417A1C1E5F0")!
}
