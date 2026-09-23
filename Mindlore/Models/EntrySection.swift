import Foundation

// One stretch of an entry that talks about one thing, as the insights run divided it. Kept in the
// background: nothing marks up the text, but the tags and names each part carries are folded into
// the entry's own, and the insights sheet lists the parts so a long entry reads as what it covered.
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
