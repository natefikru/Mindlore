import Foundation

// Word-level difference between the entry's text and a cleaned-up version, so the user can see what
// would change before replacing their own words.
nonisolated enum TextDiff {
    struct Run: Equatable {
        let text: String
        let changed: Bool
    }

    static func runs(original: String, cleaned: String) -> (original: [Run], cleaned: [Run]) {
        let originalWords = words(in: original)
        let cleanedWords = words(in: cleaned)
        // Compared without their spacing, so re-wrapping a paragraph isn't reported as changed words.
        let difference = cleanedWords.map(Self.bare).difference(from: originalWords.map(Self.bare))
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        return (runs(originalWords, changed: removed), runs(cleanedWords, changed: inserted))
    }

    static func summary(original: String, cleaned: String) -> String {
        let (before, after) = runs(original: original, cleaned: cleaned)
        let removed = before.filter(\.changed).count
        let added = after.filter(\.changed).count
        if removed == 0 && added == 0 { return "No changes." }
        return "\(added) \(added == 1 ? "word" : "words") added, \(removed) \(removed == 1 ? "word" : "words") removed."
    }

    private static func bare(_ word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Keeps whitespace with its word so rebuilt text reads the same.
    private static func words(in text: String) -> [String] {
        var words: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if character.isWhitespace {
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    private static func runs(_ words: [String], changed: Set<Int>) -> [Run] {
        var runs: [Run] = []
        for (index, word) in words.enumerated() {
            let isChanged = changed.contains(index)
            if var last = runs.last, last.changed == isChanged {
                runs.removeLast()
                last = Run(text: last.text + word, changed: isChanged)
                runs.append(last)
            } else {
                runs.append(Run(text: word, changed: isChanged))
            }
        }
        return runs
    }
}
