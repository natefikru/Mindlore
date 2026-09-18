import Foundation
import SwiftData

// What an entity is. A superset of MentionKind so tags are nodes too, which is what lets a
// person and a tag share an edge. Raw values are stored, so never rename one.
nonisolated enum EntityKind: String, CaseIterable, Sendable {
    case person, place, organization, project, event, other, tag

    init(_ mention: MentionKind) {
        self = EntityKind(rawValue: mention.rawValue) ?? .other
    }
}

nonisolated enum EntityLinkSource: String, CaseIterable, Sendable {
    case ai, user
}

// One person, place, organization, project, event, or tag, gathered from the mentions and tags
// EntryInsights already stores. Follows the same CloudKit schema rules as Entry.
@Model
final class Entity {
    var id: UUID = UUID()
    var name: String = ""
    // The normalized form everything is matched on. EntityNormalizer owns its shape.
    var key: String = ""
    var kindRaw: String = EntityKind.other.rawValue
    // Other surface forms that resolve here: "Sarah K", "my sister", a merged entity's name.
    var aliases: [String] = []
    var bio: String?
    // AI drafts a bio only while it is empty or still AI-written, the same rule as titles.
    var bioWasGenerated: Bool = false
    // Any edit the user makes to the bio, clearing it included. After that AI never writes it,
    // which an empty bio alone could not say.
    var bioEditedByUser: Bool = false
    // What the last draft was made from, for the page's disclosure line. Set only when a request
    // was answered, so a draft that never went out is tried again.
    var bioDraftedAt: Date?
    var bioModelUsed: String?
    var bioSourceEntries: Int = 0
    var bioSourceCharacters: Int = 0
    // A kind the user never touched can still be upgraded when a later mention says what this
    // is. Kept apart from confirmedByUser so writing a bio doesn't freeze the kind.
    var kindEditedByUser: Bool = false
    // Any manual edit. Keeps the entity alive once it has no links left.
    var confirmedByUser: Bool = false
    // The user's own hide. A hidden entity still resolves, so it never comes back under a new id.
    var hidden: Bool = false
    var mergedIntoID: UUID?
    var mergedAt: Date?
    // Exactly the aliases this loser added to its winner, so unmerge removes no more than that.
    var contributedAliases: [String] = []
    // Suggestion partners the user said were not the same thing.
    var notSameAs: [UUID] = []

    // The CNContact this person is, when the user has linked one. Only the identifier: the name,
    // the photo, and everything else stay in Contacts and are read live, so the app never holds a
    // copy of the address book.
    var contactIdentifier: String?

    // Denormalized so the map and Mind's panel read them without walking links. GraphIndexer.recount owns them.
    var linkCount: Int = 0
    var firstLinkedAt: Date?
    var lastLinkedAt: Date?
    // Orders entities that have never been linked, which have no other date to sort on.
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .nullify, inverse: \EntityLink.entity)
    var links: [EntityLink]? = []

    var kind: EntityKind {
        get { EntityKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var isMerged: Bool { mergedIntoID != nil }

    // A merge loser is kept as the undo record, so it stays out of every list without the
    // user ever having hidden it. Merging must not write `hidden`, or unmerge can't tell
    // the two apart.
    var isBrowsable: Bool { !hidden && !isMerged }

    init(id: UUID = UUID(), name: String, key: String, kind: EntityKind, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.key = key
        self.kindRaw = kind.rawValue
        self.createdAt = createdAt
    }
}
