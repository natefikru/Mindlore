import Foundation

// Where an entry's text names its entities, for read mode's links. Longer names win overlaps, so
// "Sarah Kim" is one link rather than "Sarah" plus leftover text, and nothing is linked twice.
nonisolated enum EntityNameRanges {
    struct Candidate: Equatable, Sendable {
        // Already resolved through merges, so it's the entity the link should open.
        let entityID: UUID
        let kind: EntityKind
        let names: [String]
    }

    struct Match: Equatable {
        let range: Range<String.Index>
        let entityID: UUID
    }

    static func matches(in text: String, candidates: [Candidate]) -> [Match] {
        var found: [Match] = []
        for candidate in candidates {
            for name in Set(candidate.names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where name.count > 1 {
                for range in NameMatching.ranges(of: name, in: text) where isWholeCharacters(range, in: text) {
                    found.append(Match(range: range, entityID: candidate.entityID))
                }
            }
        }
        // Longest first, then earliest, then a fixed order between two entities on the same words.
        found.sort { a, b in
            let lengthA = text.distance(from: a.range.lowerBound, to: a.range.upperBound)
            let lengthB = text.distance(from: b.range.lowerBound, to: b.range.upperBound)
            if lengthA != lengthB { return lengthA > lengthB }
            if a.range.lowerBound != b.range.lowerBound { return a.range.lowerBound < b.range.lowerBound }
            return a.entityID.uuidString < b.entityID.uuidString
        }
        var kept: [Match] = []
        for match in found where !kept.contains(where: { $0.range.overlaps(match.range) }) {
            kept.append(match)
        }
        return kept.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    // A match that ends inside a character (a decomposed accent right after it) isn't a name.
    private static func isWholeCharacters(_ range: Range<String.Index>, in text: String) -> Bool {
        text.rangeOfComposedCharacterSequences(for: range) == range
    }
}
