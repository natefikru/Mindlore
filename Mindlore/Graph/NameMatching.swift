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

    // Below EntityMatcher's 0.88: that threshold is tuned for whole entity names, most of them
    // several letters longer than one short first name, and "Lewis" for a corrected "Luis"
    // (0.805) needs a looser bar to clear at all. The first-letter check below is what keeps that
    // looseness from matching noise: two unrelated short words rarely share both a first letter
    // and a 0.8 Jaro-Winkler score.
    static let nearestWordThreshold = 0.8

    // The entry's own word or two-word phrase closest to a name grounding couldn't find
    // verbatim: the model corrected a garbled name to a known one, and this looks for what was
    // actually said. Only worth the scan on that fallback path, not on every mention.
    static func nearestWord(to name: String, in text: String, threshold: Double = nearestWordThreshold) -> String? {
        let key = EntityNormalizer.key(for: name)
        guard let firstLetter = key.first else { return nil }

        var words: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { substring, _, _, _ in
            guard let substring, !substring.isEmpty else { return }
            words.append(substring)
        }
        guard !words.isEmpty else { return nil }

        var candidates = words
        for index in 0..<(words.count - 1) {
            candidates.append("\(words[index]) \(words[index + 1])")
        }

        var best: (text: String, score: Double)?
        for candidate in candidates {
            let candidateKey = EntityNormalizer.key(for: candidate)
            guard candidateKey.first == firstLetter else { continue }
            let score = max(
                EntityMatcher.jaroWinkler(key, candidateKey),
                EntityMatcher.isSubset(key, candidateKey) ? EntityMatcher.subsetScore : 0
            )
            if score >= threshold, best == nil || score > best!.score {
                best = (candidate, score)
            }
        }
        return best?.text
    }
}
