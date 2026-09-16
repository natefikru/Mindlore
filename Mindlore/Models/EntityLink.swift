import Foundation
import SwiftData

// One entry mentions one entity. The only stored edge in the graph: entity-to-entity
// connections are computed from the entries two entities share, so they can never go stale.
@Model
final class EntityLink {
    // The relationships carry SwiftData's cascade and nullify rules and give the views
    // something to read. They are not dependable for logic: part-way through an unsaved
    // batch `entity` can read nil, and a predicate that reaches through it is worse. So
    // every decision the graph makes compares these ids instead, and the two are only ever
    // written together, by the methods below.
    var entity: Entity?
    var entry: Entry?
    var entityID: UUID?
    var entryID: UUID?
    // The value exactly as the AI wrote it, so the entity page can show what was said.
    var surface: String = ""
    var kindRaw: String = EntityKind.other.rawValue
    var sourceRaw: String = EntityLinkSource.ai.rawValue
    // Linked by the first-name rule rather than an exact match, so the UI can mark it a guess.
    var inferred: Bool = false
    // Which entity a merge took this link away from, so unmerge can put it back. Only a merge
    // ever sets it, and only the first one: a link merged twice still belongs to the entity
    // it was born on.
    var originalEntityID: UUID?

    var kind: EntityKind {
        get { EntityKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var source: EntityLinkSource {
        get { EntityLinkSource(rawValue: sourceRaw) ?? .ai }
        set { sourceRaw = newValue.rawValue }
    }

    init(surface: String, kind: EntityKind, source: EntityLinkSource = .ai, inferred: Bool = false) {
        self.surface = surface
        self.kindRaw = kind.rawValue
        self.sourceRaw = source.rawValue
        self.inferred = inferred
    }

    // Merging this link's entity into `winner`. A link whose entity is already gone is left
    // for recount to delete rather than given a birthplace it never had.
    //
    // As with restore and repoint: a link that is already saved silently refuses a target the
    // store has never seen, leaving `entity` nil. Insert and save a new entity before pointing
    // existing links at it.
    func attach(to entry: Entry, entity: Entity) {
        self.entry = entry
        self.entryID = entry.id
        point(at: entity)
    }

    func moveForMerge(to winner: Entity) {
        guard let current = entityID else { return }
        if originalEntityID == nil { originalEntityID = current }
        point(at: winner)
    }

    // Unmerging: back to where it was born, with nothing left to undo.
    func restore(to origin: Entity) {
        point(at: origin)
        originalEntityID = nil
    }

    // The user saying this one mention is something else. That is a new birth, not a merge:
    // the link becomes theirs, so reindexing keeps it and no later unmerge claims it.
    func repoint(to entity: Entity) {
        point(at: entity)
        originalEntityID = nil
        source = .user
    }

    // Sets the relationship and the id together. Nothing should ever write one without the other.
    func point(at entity: Entity) {
        self.entity = entity
        self.entityID = entity.id
    }
}
