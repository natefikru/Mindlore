import Foundation
import SwiftData

// One entry mentions one entity. The only stored edge in the graph: entity-to-entity
// connections are computed from entries two entities share, so they can never go stale.
@Model
final class EntityLink {
    // Queries reach through these and compare the model's own UUID:
    //   #Predicate { if let entity = $0.entity { entity.id == wanted } else { false } }
    // Never compare persistentModelID that way. It generates no error and no correct answer:
    // the same query returned every row in one test and no rows in another.
    var entity: Entity?
    var entry: Entry?
    // The value exactly as the AI wrote it, so the entity page can show what was actually said.
    var surface: String = ""
    var kindRaw: String = EntityKind.other.rawValue
    var sourceRaw: String = EntityLinkSource.ai.rawValue
    // Linked by the first-name rule rather than an exact match, so the UI can mark it as a guess.
    var inferred: Bool = false
    // Set by the first merge that moved this link and never overwritten, so unmerge knows
    // where the link was born rather than where it last stopped.
    var originalEntityID: UUID?
    var createdAt: Date = Date.now

    var kind: EntityKind {
        get { EntityKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var source: EntityLinkSource {
        get { EntityLinkSource(rawValue: sourceRaw) ?? .ai }
        set { sourceRaw = newValue.rawValue }
    }

    init(
        surface: String,
        kind: EntityKind,
        source: EntityLinkSource = .ai,
        inferred: Bool = false,
        createdAt: Date = .now
    ) {
        self.surface = surface
        self.kindRaw = kind.rawValue
        self.sourceRaw = source.rawValue
        self.inferred = inferred
        self.createdAt = createdAt
    }

    func attach(to entry: Entry, entity: Entity) {
        self.entry = entry
        self.entity = entity
    }

    // Move the link to another entity, remembering where it was born so unmerge can put it back.
    // Only the first move records an origin: a link that has been merged twice belongs to
    // whichever entity first owned it, not to its last stop.
    func moveTo(_ entity: Entity) {
        if originalEntityID == nil { originalEntityID = self.entity?.id }
        self.entity = entity
    }
}
