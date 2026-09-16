import Foundation
import SwiftData

// One entry mentions one entity. The only stored edge in the graph: entity-to-entity
// connections are computed from the entries two entities share, so they can never go stale.
@Model
final class EntityLink {
    // The relationships exist for one reason: SwiftData's cascade and nullify rules, which
    // keep links from outliving the entry they belong to. Nothing reads them, not even the
    // views. `entity` comes back nil often enough after a re-point, even once everything is
    // saved, that it cannot be trusted to draw a screen with.
    //
    // The ids below are the truth. Resolve an entity by fetching it for its id. The two are
    // only ever written together, by the methods at the bottom of this file.
    var entity: Entity?
    var entry: Entry?
    var entityID: UUID?
    var entryID: UUID?
    // The value exactly as the AI wrote it, so the entity page can show what was said.
    var surface: String = ""
    // What the entry itself said, only when the AI corrected a name grounding couldn't find
    // verbatim; nil means `surface` already is the entry's own wording. Excerpts and entry rows
    // search this first, so a corrected "Luis" still finds the sentence that says "Lewis".
    var writtenSurface: String?
    var kindRaw: String = EntityKind.other.rawValue
    var sourceRaw: String = EntityLinkSource.ai.rawValue
    // Linked by the first-name rule rather than an exact match, so the UI can mark it a guess.
    var inferred: Bool = false
    // Which entity a merge took this link away from, so unmerge can put it back. Only a merge
    // ever sets it, and only the first one: a link merged twice still belongs to the entity
    // it was born on.
    var originalEntityID: UUID?
    // The resolver's candidates when a shared key tied and it picked one to link to for now,
    // rather than a real decision. Empty means resolved normally. The Review list's "Which one?"
    // asks, and repointing to one of them clears it (5c.4).
    var unsureAmong: [UUID] = []

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
        // The user said where this belongs, so it is no longer a guess.
        inferred = false
        // ...and no longer unsure, whether it was tied or just guessed wrong.
        unsureAmong = []
    }

    // Sets the relationship and the id together. Nothing should ever write one without the other.
    func point(at entity: Entity) {
        self.entity = entity
        self.entityID = entity.id
    }
}
