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
        var stripped = text
        for handle in Set(found) {
            stripped = stripped.replacingOccurrences(of: "[\(handle)]", with: "", options: [.caseInsensitive])
        }
        let tidied = stripped
            .replacingOccurrences(of: " ,", with: ",")
            .replacingOccurrences(of: " .", with: ".")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Answer(text: tidied, handles: filtered(found, known: known))
    }

    static func markers(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "\\[\\s*([Ee]\\d+)\\s*\\]") else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range(at: 1), in: text).map { "E" + text[$0].dropFirst() }
        }
    }

    // In the order the answer used them, each one once.
    private static func filtered(_ handles: [String], known: Set<String>) -> [String] {
        var seen: Set<String> = []
        return handles
            .map { "E" + $0.trimmingCharacters(in: .whitespaces).dropFirst(($0.first == "e" || $0.first == "E") ? 1 : 0) }
            .filter { known.contains($0) && seen.insert($0).inserted }
    }
}
