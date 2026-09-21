import Foundation

// Renaming an entity fixes the name wherever the app wrote it itself: bios, summaries, generated
// titles, custom card text, and loose ends. The user's own words are never touched, so a misheard
// name still reads in the entry as it was said and the alias is what makes it still resolve.
//
// NameMatching alone would be wrong here. It is a whole-word matcher, so "Sarah" matches inside
// "Sarah Jane", and it ignores case, so entities named Mark, Will, Ray, or Hope match ordinary
// words. It finds a name so a chip can point at it, which tolerates a loose match; a replacement
// does not. So its ranges are only candidates, and the rules below decide which ones are the name.
nonisolated enum EntityProseRewriter {
    struct Counts: Equatable {
        var bios = 0
        var summaries = 0
        var looseEnds = 0
        var titles = 0
        var cards = 0

        var total: Int { bios + summaries + looseEnds + titles + cards }
        var isEmpty: Bool { total == 0 }
    }

    // nil when nothing changed, so a caller can skip the write entirely.
    static func rewrite(_ text: String, from old: String, to new: String) -> String? {
        let old = old.trimmingCharacters(in: .whitespacesAndNewlines)
        let new = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !old.isEmpty, !new.isEmpty, old != new else { return nil }

        let ranges = candidates(of: old, in: text)
        guard !ranges.isEmpty else { return nil }

        // Back to front: replacing forwards invalidates the ranges that follow.
        var result = text
        for range in ranges.sorted(by: { $0.lowerBound > $1.lowerBound }) {
            result.replaceSubrange(range, with: new)
        }
        return result == text ? nil : result
    }

    // Whether a rename would change this text, for the warning shown before it happens. Same
    // rules, so the count and the rewrite can never disagree.
    static func contains(_ name: String, in text: String) -> Bool {
        !candidates(of: name.trimmingCharacters(in: .whitespacesAndNewlines), in: text).isEmpty
    }

    private static func candidates(of name: String, in text: String) -> [Range<String.Index>] {
        guard !name.isEmpty, !text.isEmpty else { return [] }
        return NameMatching.ranges(of: name, in: text).filter { range in
            // Exact case. The app writes a name as the entity carries it, so this costs almost
            // nothing and is what keeps "make your mark" out of a Mark's rename.
            guard text[range] == name else { return false }
            return !isPartOfALongerName(range, in: text)
        }
    }

    // "Sarah" inside "Sarah Jane" is one name, not this entity's. Skipping a capitalized
    // neighbour also skips "Sarah Monday", which is the safe way to be wrong: leaving prose alone
    // beats editing the wrong words in a rewrite nobody can undo.
    private static func isPartOfALongerName(_ range: Range<String.Index>, in text: String) -> Bool {
        capitalizedWordFollows(range.upperBound, in: text) || capitalizedWordPrecedes(range.lowerBound, in: text)
    }

    private static func capitalizedWordFollows(_ index: String.Index, in text: String) -> Bool {
        guard index < text.endIndex, text[index] == " " else { return false }
        let next = text.index(after: index)
        guard next < text.endIndex else { return false }
        return text[next].isUppercase
    }

    // "Jane" in "dinner with Jane Sarah" makes the Sarah part of a longer name. "Told" in "Told
    // Sarah about it" does not: it is capitalized only because it starts the sentence. Skipping
    // on a capital alone would leave almost every real occurrence untouched, since a name so
    // often follows the first word of a sentence.
    private static func capitalizedWordPrecedes(_ index: String.Index, in text: String) -> Bool {
        guard index > text.startIndex else { return false }
        let space = text.index(before: index)
        guard text[space] == " ", space > text.startIndex else { return false }

        // Walk back over the previous word to its first letter.
        var start = space
        while start > text.startIndex {
            let previous = text.index(before: start)
            guard text[previous].isLetter else { break }
            start = previous
        }
        guard start < space, text[start].isUppercase else { return false }
        return !startsASentence(start, in: text)
    }

    private static func startsASentence(_ index: String.Index, in text: String) -> Bool {
        var cursor = index
        while cursor > text.startIndex {
            let previous = text.index(before: cursor)
            let character = text[previous]
            if character == " " || character.isNewline { cursor = previous; continue }
            return character == "." || character == "!" || character == "?" || character == ":"
        }
        return true
    }
}
