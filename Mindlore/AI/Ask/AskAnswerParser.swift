import Foundation

// Turns what a provider said into an answer and its citations. Only handles handed out in this
// conversation count: an entry that wrote "[E7]" into its own text, or a model that invented a
// number, can't point the user at something the question never reached.
nonisolated enum AskAnswerParser {
    nonisolated struct Answer: Equatable, Sendable {
        let text: String
        let handles: [String]
    }

    // The OpenAI shape: {"answer": "...", "citations": ["E1"]}.
    nonisolated struct Payload: Decodable {
        let answer: String
        let citations: [String]
    }

    static func parseJSON(_ text: String, known: Set<String>) throws -> Answer {
        let payload = try StructuredOutputParser.decode(Payload.self, from: text)
        return Answer(text: payload.answer.trimmingCharacters(in: .whitespacesAndNewlines), handles: filtered(payload.citations, known: known))
    }

    // Foundation Models answers in plain text with [E3] markers. Known markers become citations
    // and leave the text; an unknown one stays where it was written, since removing it would
    // change a sentence the user is reading.
    static func parseMarkers(_ text: String, known: Set<String>) -> Answer {
        let found = markers(in: text).filter { known.contains($0) }
        // Removed by the same pattern that found them, so a marker written "[ E3 ]" goes too.
        var stripped = text
        if let regex = try? NSRegularExpression(pattern: markerPattern) {
            var result = ""
            var cursor = text.startIndex
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let whole = Range(match.range, in: text), let inner = Range(match.range(at: 1), in: text),
                      let handle = normalized(String(text[inner])), known.contains(handle) else { continue }
                result += text[cursor..<whole.lowerBound]
                cursor = whole.upperBound
            }
            result += text[cursor...]
            stripped = result
        }
        let tidied = stripped
            .replacingOccurrences(of: " ,", with: ",")
            .replacingOccurrences(of: " .", with: ".")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Answer(text: tidied, handles: filtered(found, known: known))
    }

    static let markerPattern = "\\[\\s*([Ee]\\d+)\\s*\\]"

    static func markers(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: markerPattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range(at: 1), in: text).flatMap { normalized(String(text[$0])) }
        }
    }

    // "e3", " E3 " and "E3" are the same handle; anything else is not one at all.
    static func normalized(_ handle: String) -> String? {
        let trimmed = handle.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, first == "E" || first == "e" else { return nil }
        let digits = trimmed.dropFirst()
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return nil }
        return "E" + digits
    }

    // In the order the answer used them, each one once.
    private static func filtered(_ handles: [String], known: Set<String>) -> [String] {
        var seen: Set<String> = []
        return handles
            .compactMap(normalized)
            .filter { known.contains($0) && seen.insert($0).inserted }
    }
}
