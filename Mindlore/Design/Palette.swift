import SwiftUI

// Every colour the app owns. The values live in Assets.xcassets with a light and a dark variant each,
// so nothing here names a number. Each light variant is tuned for Paper (deeper and more saturated),
// each dark one for the dark page (lighter, so it still reads without glowing).
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
    // Mind's node fill, the drawer's kind glyph, the peek card's sparkline, and the avatar: on the
    // map colour means kind. Six well-separated hues for names (blue person, green place, amber
    // organization, violet project, coral event, stone other) and a dark neutral for tags, which
    // are many and small and should recede behind the names. The canvas reads these once per fill
    // bucket, not once per node.
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

extension EntryKind {
    // The badge on a row and the picker chip. The journal, which is most of the list, wears the
    // accent; notes and creative work take quiet system colours so three badges in a list read as
    // three kinds, not as three alerts (owner, 2026-09-23).
    var color: Color {
        switch self {
        case .journal: Palette.ember
        case .note: .teal
        case .creative: .indigo
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
