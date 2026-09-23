import Foundation

// One stretch of an entry that talks about one thing, as the insights run divided it. Metadata for
// the Mind map, where two names connect only when they share a part (EntryParts); nothing marks
// up the text or shows the parts, and the tags each part carries are folded into the entry's own.
// `offset` is where the part starts in the text the insights were made from, in characters, or
// nil when the model's opening words weren't found in the entry.
nonisolated struct EntrySection: Codable, Equatable, Sendable {
    var topic: String
    var summary: String?
    var areasRaw: [String] = []
    var tags: [String] = []
    var names: [String] = []
    var offset: Int?

    var areas: [LifeArea] { areasRaw.compactMap(LifeArea.init(rawValue:)) }
}
