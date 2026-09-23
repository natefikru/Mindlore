import Foundation

// Where an "@" name or a "#tag" is being typed. Pure, over the text and a UTF-16 caret, so the
// text view only has to ask and act. An "@" counts at the start of a word (after whitespace or at
// the start of the text) and the mention runs to the caret with no whitespace in it, so "@Sar"
// with the caret after it is a mention for "Sar" and "me@work" is an address. A tag is complete
// once a non-word character follows it: "#river " links river, "#" alone links nothing.
nonisolated enum MentionDetection {
    struct Mention: Equatable, Sendable {
        // The "@" and the query after it.
        let range: NSRange
        let query: String
    }

    struct Tag: Equatable, Sendable {
        // The "#" and the word.
        let range: NSRange
        let word: String
    }

    static func mention(in text: String, caret: Int) -> Mention? {
        let utf16 = Array(text.utf16)
        guard caret > 0, caret <= utf16.count else { return nil }
        var index = caret
        while index > 0 {
            let scalar = utf16[index - 1]
            if scalar == 64 { // "@"
                let start = index - 1
                guard start == 0 || isWhitespace(utf16[start - 1]) else { return nil }
                let query = String(decoding: utf16[index..<caret], as: UTF16.self)
                return Mention(range: NSRange(location: start, length: caret - start), query: query)
            }
            if isWhitespace(scalar) { return nil }
            index -= 1
        }
        return nil
    }

    // The tag whose word ends exactly at `location`, if the character there (or the end of the
    // text) is not part of a word.
    static func completedTag(in text: String, endingAt location: Int) -> Tag? {
        let utf16 = Array(text.utf16)
        guard location > 0, location <= utf16.count else { return nil }
        if location < utf16.count, isWord(utf16[location]) { return nil }
        var index = location
        while index > 0, isWord(utf16[index - 1]) { index -= 1 }
        guard index < location, index > 0, utf16[index - 1] == 35 else { return nil } // "#"
        let start = index - 1
        guard start == 0 || !isWord(utf16[start - 1]) else { return nil }
        let word = String(decoding: utf16[index..<location], as: UTF16.self)
        guard word.first?.isNumber != true else { return nil }
        return Tag(range: NSRange(location: start, length: location - start), word: word)
    }

    private static func isWhitespace(_ unit: UInt16) -> Bool {
        unit == 32 || unit == 10 || unit == 9 || unit == 0x00A0
    }

    private static func isWord(_ unit: UInt16) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return true }
        return CharacterSet.alphanumerics.contains(scalar) || unit == 95
    }
}
