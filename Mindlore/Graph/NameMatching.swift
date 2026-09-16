import Foundation

// Finds a name in an entry's text as a whole word, ignoring case. "Sarah" matches "sarah" and
// "Sarah's", never "Sarahs" or "Mosarah". Grounding names from the model and quoting entries
// for a bio both use it, so a name counts as present by one rule.
nonisolated enum NameMatching {
    static func range(of phrase: String, in text: String) -> Range<String.Index>? {
        ranges(of: phrase, in: text).first
    }

    static func ranges(of phrase: String, in text: String) -> [Range<String.Index>] {
        guard !phrase.isEmpty else { return [] }
        let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: phrase) + "(?![\\p{L}\\p{N}])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text) }
    }
}
