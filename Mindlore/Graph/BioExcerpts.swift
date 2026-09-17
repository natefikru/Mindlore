import Foundation

// The sentences a bio is drafted from: where the journal names an entity, and nothing else.
// Newest entries first, whole sentences only, a fixed budget in total.
nonisolated enum BioExcerpts {
    static let maxEntries = 8
    static let maxCharacters = 1_500

    // One linked entry: its text as the provider already saw it, and the names it used.
    struct Source: Equatable, Sendable {
        let text: String
        let date: Date
        let surfaces: [String]
    }

    struct Selection: Equatable, Sendable {
        var sentences: [String] = []
        // Entries that gave at least one sentence.
        var entries = 0
        var characters: Int { sentences.reduce(0) { $0 + $1.count } }
        var isEmpty: Bool { sentences.isEmpty }
    }

    static func select(from sources: [Source]) -> Selection {
        var selection = Selection()
        var seen: Set<String> = []
        var budget = maxCharacters
        let newest = sources.sorted { $0.date > $1.date }.prefix(maxEntries)
        for source in newest {
            var contributed = false
            // A sentence that doesn't fit is skipped, not cut, so a shorter one later can still go.
            for sentence in sentences(in: source.text, naming: source.surfaces)
            where sentence.count <= budget && seen.insert(sentence).inserted {
                selection.sentences.append(sentence)
                budget -= sentence.count
                contributed = true
            }
            if contributed { selection.entries += 1 }
        }
        return selection
    }

    static func sentences(in text: String, naming surfaces: [String]) -> [String] {
        let names = surfaces.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !names.isEmpty else { return [] }
        var found: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { substring, _, _, _ in
            guard let sentence = substring?.split(whereSeparator: \.isNewline).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines), !sentence.isEmpty else { return }
            if names.contains(where: { NameMatching.range(of: $0, in: sentence) != nil }) {
                found.append(sentence)
            }
        }
        return found
    }
}
