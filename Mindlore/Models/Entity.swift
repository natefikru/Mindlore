import Foundation
import SwiftData

// What an entity is. A superset of MentionKind: tags and themes are nodes too, so a person
// and a theme can share an edge. Raw values are stored, so never rename one.
nonisolated enum EntityKind: String, CaseIterable, Codable, Sendable {
    case person, place, organization, project, event, other, tag, theme

    init(_ mention: MentionKind) {
        self = EntityKind(rawValue: mention.rawValue) ?? .other
    }

    // The kinds a mention can produce, in the order they are shown.
    static let mentionKinds: [EntityKind] = MentionKind.allCases.map(EntityKind.init)
}

// Where a link came from. A user link survives reindexing; an AI link is rebuilt from insights.
nonisolated enum EntityLinkSource: String, CaseIterable, Codable, Sendable {
    case ai, user
}

// One person, place, organization, project, event, tag, or theme, gathered from the mentions,
// tags, and themes that EntryInsights already stores. Follows the same CloudKit schema rules
// as Entry: every property optional or defaulted, nothing unique.
@Model
final class Entity {
    var id: UUID = UUID()
    // The display form. The user's casing wins once they rename it.
    var name: String = ""
    // The normalized form everything is matched on. EntityNormalizer owns its shape.
    var key: String = ""
    var kindRaw: String = EntityKind.other.rawValue
    // Other surface forms that resolve here: "Sarah K", "my sister", a merged entity's name.
    var aliases: [String] = []
    // Drafted by AI on first open, then the user's the moment they edit it.
    var bio: String?
    var bioWasGenerated: Bool = false
    // Any manual edit, merge, hide, or alias. Keeps the entity alive with no links.
    var confirmedByUser: Bool = false
    // Still resolves, so it never comes back under a new id, but no list or graph shows it.
    var hidden: Bool = false
    // Set on the loser of a merge. Always one hop from a live root: merging the winner again
    // rewrites every pointer aimed at it, so no chain is ever longer than one.
    var mergedIntoID: UUID?
    var mergedAt: Date?
    // Exactly the aliases this loser added to its winner, so unmerge removes no more than that.
    var contributedAliases: [String] = []
    // Suggestion partners the user said were not the same thing.
    var notSameAs: [UUID] = []

    // Denormalized so the Connections list can sort by count or recency with a SortDescriptor.
    // GraphIndexer.recount is the only writer.
    var linkCount: Int = 0
    var firstLinkedAt: Date?
    var lastLinkedAt: Date?
    var createdAt: Date = Date.now

    // Nullify, not cascade: deleting an entity must never delete links out of entries.
    // Recount deletes the nullified leftovers.
    @Relationship(deleteRule: .nullify, inverse: \EntityLink.entity)
    var links: [EntityLink]? = []

    var kind: EntityKind {
        get { EntityKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    // A merge loser is kept as the undo, and hidden from everything.
    var isMerged: Bool { mergedIntoID != nil }

    init(name: String, key: String, kind: EntityKind, createdAt: Date = .now) {
        self.name = name
        self.key = key
        self.kindRaw = kind.rawValue
        self.createdAt = createdAt
    }
}
