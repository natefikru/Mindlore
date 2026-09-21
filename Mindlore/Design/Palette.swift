import SwiftUI

// Every colour the app owns. The values live in Assets.xcassets with a light and a dark variant each,
// so nothing here names a number. Areas are warm and saturated, kinds are cooler and quieter, so a
// kind on the graph is never mistaken for an area.
enum Palette {
    // The warm page behind everything, and the opaque surface a card sits on.
    static let paper = Color(.paper)
    static let card = Color(.card)
    // The user's own words.
    static let ink = Color(.ink)
    static let ember = Color.accentColor
    static let hairline = Color.primary.opacity(0.08)
}

extension LifeArea {
    var color: Color {
        switch self {
        case .work: Color(.areaWork)
        case .money: Color(.areaMoney)
        case .health: Color(.areaHealth)
        case .mind: Color(.areaMind)
        case .family: Color(.areaFamily)
        case .love: Color(.areaLove)
        case .friends: Color(.areaFriends)
        case .play: Color(.areaPlay)
        case .home: Color(.areaHome)
        }
    }
}

extension EntityKind {
    // The graph canvas's node fill, and any kind legend beside it. Seven fixed colours, never derived
    // from anything else, so a kind's colour stays stable across a session. The canvas reads these
    // once per fill bucket, not once per node.
    var color: Color {
        switch self {
        case .person: Color(.kindPerson)
        case .place: Color(.kindPlace)
        case .organization: Color(.kindOrganization)
        case .project: Color(.kindProject)
        case .event: Color(.kindEvent)
        case .tag: Color(.kindTag)
        case .other: Color(.kindOther)
        }
    }
}

extension MoodCategory {
    // A dot beside the mood's word, never the only signal: the word and its meaning carry the
    // information. The hues tell categories apart and grade nothing; there is no good or bad colour.
    var color: Color {
        switch self {
        case .joyful: .orange
        case .calm: .teal
        case .connected: .pink
        case .reflective: .indigo
        case .anxious: .yellow
        case .angry: .red
        case .low: .blue
        case .drained: .gray
        }
    }
}
