import Foundation

// The closed set of life areas an entry is filed under, one or two per entry. Raw values are
// stored on insights and sent to the model, so the user's renames never reach either.
// LifeAreaTests pins the list.
nonisolated enum LifeArea: String, CaseIterable, Codable, Sendable {
    case work, money, health, mind, family, love, friends, play, home

    static let maxPerEntry = 2

    var defaultName: String { rawValue.capitalized }

    var meaning: String {
        switch self {
        case .work: "job, school, career, side projects"
        case .money: "spending, saving, debt, bills"
        case .health: "body, sleep, exercise, food, medical"
        case .mind: "the author's inner life itself: mental state, self-reflection, growth, faith"
        case .family: "parents, siblings, kids, relatives"
        case .love: "partner, dating, breakups"
        case .friends: "friendships, social life, community"
        case .play: "hobbies, creative work, travel, rest"
        case .home: "where the author lives, moving, chores, the household"
        }
    }

    var symbol: String {
        switch self {
        case .work: "briefcase"
        case .money: "dollarsign.circle"
        case .health: "heart"
        case .mind: "brain.head.profile"
        case .family: "figure.2.and.child.holdinghands"
        case .love: "heart.circle"
        case .friends: "person.3"
        case .play: "paintpalette"
        case .home: "house"
        }
    }
}
