import Foundation

// Turns a name as written into the key everything is matched on. "Sarah's", "SARAH" and
// "  sarah  " all have to reach the same person, and "Dr. Kim" has to reach "Kim".
// Display names keep their original spelling; only keys are compared.
nonisolated enum EntityNormalizer {
    // Stripped from the front of a person's name. A kinship word is a role, not a name:
    // "Aunt May" is May. Nothing is stripped if it would leave the key empty.
    static let honorifics: Set<String> = [
        "mr", "mrs", "ms", "miss", "mx", "dr", "prof", "professor", "sir", "dame", "lord", "lady",
        "aunt", "auntie", "uncle", "grandma", "grandpa", "granny", "nana",
    ]

    static func key(for name: String, kind: EntityKind = .other) -> String {
        // Case, diacritics, and full-width forms all fold away: "NĚMEČEK" and "Němeček" are one person.
        let folded = name
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: "\u{2019}", with: "'")

        var tokens = folded
            .split(whereSeparator: \.isWhitespace)
            .map(trimmedOfEdgePunctuation)
            .filter { !$0.isEmpty }

        if kind == .person {
            while let first = tokens.first, tokens.count > 1, honorifics.contains(first) {
                tokens.removeFirst()
            }
        }

        if let last = tokens.last, let stripped = withoutPossessive(last) {
            if stripped.isEmpty { tokens.removeLast() } else { tokens[tokens.count - 1] = stripped }
        }

        return tokens.joined(separator: " ")
    }

    static func tokens(of key: String) -> [String] {
        key.split(separator: " ").map(String.init)
    }

    // "sarah's" and "james'" both belong to the same name as "sarah" and "james".
    private static func withoutPossessive(_ token: String) -> String? {
        if token.hasSuffix("'s") { return String(token.dropLast(2)) }
        if token.hasSuffix("'") { return String(token.dropLast()) }
        return nil
    }

    // Drops commas, periods, quotes, and brackets from the ends while keeping the marks that
    // live inside a name: o'brien, jean-luc, r2-d2.
    private static func trimmedOfEdgePunctuation(_ token: some StringProtocol) -> String {
        var slice = Substring(token)
        while let first = slice.first, isEdgePunctuation(first) { slice = slice.dropFirst() }
        while let last = slice.last, isEdgePunctuation(last), !slice.hasSuffix("'") { slice = slice.dropLast() }
        return String(slice)
    }

    private static func isEdgePunctuation(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy {
            CharacterSet.punctuationCharacters.contains($0) || CharacterSet.symbols.contains($0)
        }
    }
}
