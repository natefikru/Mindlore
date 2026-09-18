import Foundation

// Who the app writes about the journal's owner as. Summaries, bios, and loose ends read "I met
// Sarah", "you met Sarah", or "Nate met Sarah".
nonisolated enum JournalVoice: String, CaseIterable, Codable, Sendable {
    case first, second, name

    var settingsName: String {
        switch self {
        case .first: "I"
        case .second: "You"
        case .name: "My name"
        }
    }

    // Shown under each option so the choice is concrete before it is made.
    var sample: String {
        switch self {
        case .first: "I met Sarah at the coffee place."
        case .second: "You met Sarah at the coffee place."
        case .name: "Nate met Sarah at the coffee place."
        }
    }
}

// A prompt has to separate two things or it contradicts itself: who the instruction is about, and
// what person the output is written in. "The strongest mood I express" makes the model the
// speaker. So every prompt calls the journal's owner "the author", and this one line says how to
// write about them.
nonisolated struct PromptVoice: Equatable, Sendable {
    let subject: String
    let possessive: String
    let instruction: String

    static let `default` = PromptVoice(voice: .first, name: "")

    init(voice: JournalVoice, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // A name-voice with no name would tell the model to write "as .", so it falls back.
        let resolved: JournalVoice = (voice == .name && trimmed.isEmpty) ? .first : voice
        switch resolved {
        case .first:
            subject = "I"
            possessive = "my"
            instruction = "Write about the author in the first person, as I and my."
        case .second:
            subject = "you"
            possessive = "your"
            instruction = "Write about the author in the second person, as you and your."
        case .name:
            subject = trimmed
            possessive = "\(trimmed)'s"
            instruction = "Write about the author by name, as \(trimmed)."
        }
    }
}
