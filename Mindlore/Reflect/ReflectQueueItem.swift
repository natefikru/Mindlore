import Foundation

// One thing Reflect surfaces for a period: its generated summary. `Codable` because that is what
// `ReflectSummary` persists. Loose ends used to ride along here too, and repeated on every week
// they stayed open; they live in Today's row now, where they can be acted on.
nonisolated struct ReflectQueueItem: Identifiable, Equatable, Codable, Sendable {
    enum Source: Equatable, Codable, Sendable {
        case generated
    }

    // Stable across a re-fetch of the same week, since it is what dismissal keys against. Assigned
    // once, at generation, and persisted with it.
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
