import Foundation

// What an entry is. A journal entry is the author's account of their own life, a note is
// something kept for use (a list, a plan, a recipe, notes from a meeting or a book), and a
// creative piece is work the author made (a poem, lyrics, a story). The kind decides which
// insights are taken as facts about the author's life: a grocery list carries no mood, and a lyric
// puts nobody on the map. Mind's map reads journal entries only, so neither a note nor a creative
// piece draws anything there (owner, 2026-09-23). Stored on the entry as two flags, `isNote` and `isCreative`, because
// everything that reads `isCreative` already keys off it.
nonisolated enum EntryKind: String, CaseIterable, Codable, Sendable {
    case journal
    case note
    case creative

    var name: String {
        switch self {
        case .journal: "Journal"
        case .note: "Note"
        case .creative: "Creative"
        }
    }

    var symbol: String {
        switch self {
        case .journal: "book"
        case .note: "note.text"
        case .creative: "paintbrush.pointed"
        }
    }

    // One line under the picker saying what the choice changes.
    var meaning: String {
        switch self {
        case .journal: "An account of your day: moods, names, and open threads all count."
        case .note: "Something kept for use, like a list or a plan. Open threads count; it carries no mood and stays off the map."
        case .creative: "A poem, lyrics, or a story. Its names, moods, and threads are never taken as your life."
        }
    }

    // The value the insights request uses. "life" rather than "journal": the model answered
    // "journal" for every kind of text when the label was the app's own word.
    var promptValue: String {
        switch self {
        case .journal: "life"
        case .note: "note"
        case .creative: "creative"
        }
    }

    static func fromPromptValue(_ value: String?) -> EntryKind {
        switch value {
        case "creative": .creative
        case "note": .note
        default: .journal
        }
    }

    // What an entry of this kind keeps from an insights run. Everything else is dropped before
    // it is written, so it never reaches the map, Reflect, or Today.
    var keepsMoods: Bool { self == .journal }
    var keepsAreas: Bool { self != .creative }
    var keepsMentions: Bool { self != .creative }
    var keepsLooseEnds: Bool { self != .creative }
    var keepsSections: Bool { self != .creative }

    // Whether moving from `other` to this kind brings back something the run had dropped, so
    // the caller knows the entry needs reading again.
    func keepsMore(than other: EntryKind) -> Bool {
        (keepsMoods && !other.keepsMoods) || (keepsAreas && !other.keepsAreas)
            || (keepsMentions && !other.keepsMentions) || (keepsLooseEnds && !other.keepsLooseEnds)
    }
}
