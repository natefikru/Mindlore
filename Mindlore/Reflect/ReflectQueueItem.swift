import Foundation

// One thing Reflect surfaces for a week: a loose end still open at its end, a name gone quiet
// as of it, or a question the AI generated from what the week actually held. `Codable` because
// generated items are what `ReflectSummary` persists; reused-signal items are never stored, only
// built fresh at read time, so they never go stale between a loose end resolving and the cache
// catching up.
nonisolated struct ReflectQueueItem: Identifiable, Equatable, Codable, Sendable {
    enum Source: Equatable, Codable, Sendable {
        case looseEnd(UUID)
        case quietName(UUID)
        case generated
    }

    // Stable across a re-fetch of the same week, since it is what dismissal keys against. A loose
    // end or an entity's own id for those sources; a generated item's id is assigned once, at
    // generation, and persisted with it.
    let id: String
    let source: Source
    let title: String
    let body: String
    // What seeds a new entry when the card is tapped. Never empty in practice; a caller that has
    // nothing worth writing about doesn't make the item.
    let prompt: String

    init(id: String, source: Source, title: String, body: String, prompt: String) {
        self.id = id
        self.source = source
        self.title = title
        self.body = body
        self.prompt = prompt
    }
}
