import Foundation

// Finds pairs of entities that look like the same thing. Nothing here merges anything: the
// Review list shows what it returns and the user decides, because one wrong automatic merge
// folds two real people together and that is worse than a duplicate.
//
// Pure and cheap. A few hundred entities is tens of thousands of comparisons, so the list is
// recomputed whenever it is shown rather than stored and kept in sync.
nonisolated enum EntityMatcher {
    struct Candidate: Equatable, Sendable {
        let id: UUID
        let key: String
        let kind: EntityKind
        let linkCount: Int
        let notSameAs: [UUID]
    }

    struct Suggestion: Equatable, Sendable {
        let a: UUID
        let b: UUID
        let score: Double
    }

    // Below this, near-matches are noise: "mom" and "tom" score 0.87.
    static let threshold = 0.88
    // One name being all of another ("Sarah" inside "Sarah Kim") is strong, but never certain.
    static let subsetScore = 0.9

    static func suggestions(among candidates: [Candidate], threshold: Double = threshold) -> [Suggestion] {
        var found: [Suggestion] = []
        for (index, a) in candidates.enumerated() {
            for b in candidates[(index + 1)...] {
                guard !a.notSameAs.contains(b.id), !b.notSameAs.contains(a.id) else { continue }
                guard let score = score(a, b), score >= threshold else { continue }
                found.append(Suggestion(a: a.id, b: b.id, score: score))
            }
        }
        // The pair the user is most likely to care about first: a strong match on two entities
        // the journal actually uses beats a strong match on two it mentioned once.
        let counts = Dictionary(candidates.map { ($0.id, $0.linkCount) }, uniquingKeysWith: { first, _ in first })
        func weight(_ suggestion: Suggestion) -> Double {
            let pair = max(1, min(counts[suggestion.a] ?? 1, counts[suggestion.b] ?? 1))
            return suggestion.score * Double(pair)
        }
        return found.sorted { (weight($0), $0.score) > (weight($1), $1.score) }
    }

    // The same test for one entity against the rest: linear, for a screen about that entity.
    static func likelySame(as entity: Candidate, among candidates: [Candidate], threshold: Double = threshold) -> Set<UUID> {
        Set(candidates.filter { other in
            other.id != entity.id && !entity.notSameAs.contains(other.id) && !other.notSameAs.contains(entity.id)
                && (score(entity, other) ?? 0) >= threshold
        }.map(\.id))
    }

    static func score(_ a: Candidate, _ b: Candidate) -> Double? {
        guard !a.key.isEmpty, !b.key.isEmpty else { return nil }

        // A tag and a theme are different kinds of thing, so they only meet when they are
        // written identically. Anything fuzzier between them is a coincidence of wording.
        if isTagAndTheme(a.kind, b.kind) {
            return a.key == b.key ? 1 : nil
        }
        guard a.kind == b.kind || a.kind == .other || b.kind == .other else { return nil }
        if a.key == b.key { return 1 }

        return max(jaroWinkler(a.key, b.key), isSubset(a.key, b.key) ? subsetScore : 0)
    }

    // MARK: - Pieces

    private static func isTagAndTheme(_ a: EntityKind, _ b: EntityKind) -> Bool {
        (a == .tag && b == .theme) || (a == .theme && b == .tag)
    }

    // "sarah" against "sarah kim": every word of one appears in the other.
    static func isSubset(_ a: String, _ b: String) -> Bool {
        let first = Set(EntityNormalizer.tokens(of: a))
        let second = Set(EntityNormalizer.tokens(of: b))
        guard !first.isEmpty, !second.isEmpty, first != second else { return false }
        return first.isSubset(of: second) || second.isSubset(of: first)
    }

    // Jaro-Winkler, which rewards a shared prefix. Short names drift at the end far more than
    // at the start, and names from speech drift in spelling rather than in shape.
    static func jaroWinkler(_ a: String, _ b: String, prefixScale: Double = 0.1) -> Double {
        let jaro = jaro(a, b)
        guard jaro > 0 else { return 0 }
        let first = Array(a), second = Array(b)
        var prefix = 0
        for index in 0..<min(4, min(first.count, second.count)) {
            if first[index] == second[index] { prefix += 1 } else { break }
        }
        return jaro + Double(prefix) * prefixScale * (1 - jaro)
    }

    static func jaro(_ a: String, _ b: String) -> Double {
        let first = Array(a), second = Array(b)
        if first.isEmpty && second.isEmpty { return 1 }
        guard !first.isEmpty, !second.isEmpty else { return 0 }
        if first == second { return 1 }

        let window = max(max(first.count, second.count) / 2 - 1, 0)
        var firstMatched = [Bool](repeating: false, count: first.count)
        var secondMatched = [Bool](repeating: false, count: second.count)
        var matches = 0

        for (index, character) in first.enumerated() {
            let start = max(0, index - window)
            let end = min(index + window + 1, second.count)
            guard start < end else { continue }
            for other in start..<end where !secondMatched[other] && second[other] == character {
                firstMatched[index] = true
                secondMatched[other] = true
                matches += 1
                break
            }
        }
        guard matches > 0 else { return 0 }

        var transpositions = 0
        var position = 0
        for index in 0..<first.count where firstMatched[index] {
            while !secondMatched[position] { position += 1 }
            if first[index] != second[position] { transpositions += 1 }
            position += 1
        }

        let matched = Double(matches)
        return (matched / Double(first.count)
            + matched / Double(second.count)
            + (matched - Double(transpositions) / 2) / matched) / 3
    }
}
