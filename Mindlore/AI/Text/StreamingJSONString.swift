import Foundation

// Reading one string field out of a JSON object that is still arriving.
//
// Stateless on purpose. It re-scans whatever has accumulated, every time, and carries nothing
// between calls: a `\uXXXX` cut in half by a network read is simply not there yet, and arrives
// whole on the next pass. A decoder that kept its position across chunk boundaries would instead
// have to hold half an escape, which is the bug that passes every test and fails on the phone.
// Re-reading a few kilobytes per frame costs nothing next to the round trip that delivered it.
nonisolated enum StreamingJSONString {
    // The value of `field`, decoded as far as it has arrived, or nil if the value has not started.
    // The field is matched where a key can be, never inside a string, so an answer that quotes
    // `"answer":"` at itself does not end up reading its own text as the field.
    static func value(of field: String, in json: String) -> String? {
        let characters = Array(json)
        var index = 0
        var stringStart: Int?
        var escaped = false
        while index < characters.count {
            let character = characters[index]
            if let start = stringStart {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    stringStart = nil
                    if String(characters[(start + 1)..<index]) == field,
                       let valueStart = valueStart(in: characters, afterKeyEndingAt: index) {
                        return decoded(characters, from: valueStart)
                    }
                }
            } else if character == "\"" {
                stringStart = index
            }
            index += 1
        }
        return nil
    }

    // Where the value's own characters begin: a colon, then an opening quote. Anything else means
    // this was not a key, or the value has not arrived.
    private static func valueStart(in characters: [Character], afterKeyEndingAt keyEnd: Int) -> Int? {
        var index = keyEnd + 1
        while index < characters.count, characters[index].isWhitespace { index += 1 }
        guard index < characters.count, characters[index] == ":" else { return nil }
        index += 1
        while index < characters.count, characters[index].isWhitespace { index += 1 }
        guard index < characters.count, characters[index] == "\"" else { return nil }
        return index + 1
    }

    // Forward to the closing quote, or to the end of what has arrived. Anything incomplete, a
    // trailing backslash or three of the four hex digits, ends the answer here and is picked up
    // whole next time.
    private static func decoded(_ characters: [Character], from start: Int) -> String {
        var text = ""
        var index = start
        while index < characters.count {
            let character = characters[index]
            guard character == "\\" else {
                if character == "\"" { return text }
                text.append(character)
                index += 1
                continue
            }
            guard index + 1 < characters.count else { return text }
            switch characters[index + 1] {
            case "n": text.append("\n")
            case "t": text.append("\t")
            case "r": text.append("\r")
            case "b": text.append("\u{08}")
            case "f": text.append("\u{0C}")
            case "\"": text.append("\"")
            case "\\": text.append("\\")
            case "/": text.append("/")
            case "u":
                guard let (scalar, width) = unescapedScalar(characters, at: index) else { return text }
                text.unicodeScalars.append(scalar)
                index += width
                continue
            default:
                // Not an escape JSON defines, so not something to guess at.
                return text
            }
            index += 2
        }
        return text
    }

    // A `\uXXXX`, and the pair of them an emoji is written as, with how many characters it took.
    private static func unescapedScalar(_ characters: [Character], at index: Int) -> (Unicode.Scalar, Int)? {
        guard index + 5 < characters.count,
              let value = UInt32(String(characters[(index + 2)...(index + 5)]), radix: 16) else { return nil }
        guard (0xD800...0xDBFF).contains(value) else {
            return Unicode.Scalar(value).map { ($0, 6) }
        }
        guard index + 11 < characters.count, characters[index + 6] == "\\", characters[index + 7] == "u",
              let low = UInt32(String(characters[(index + 8)...(index + 11)]), radix: 16),
              (0xDC00...0xDFFF).contains(low),
              let scalar = Unicode.Scalar(0x10000 + (value - 0xD800) * 0x400 + (low - 0xDC00)) else { return nil }
        return (scalar, 12)
    }
}
