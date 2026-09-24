import Foundation

// Turns what a provider said into an answer and its citations. Only handles handed out in this
// conversation count: an entry that wrote "[E7]" into its own text, or a model that invented a
// number, can't point the user at something the question never reached.
nonisolated enum AskAnswerParser {
    nonisolated struct Answer: Equatable, Sendable {
        let text: String
        let handles: [String]
        // A note the author asked for, or a new version of one, in this turn, still Markdown. Only
        // the OpenAI shape can carry one; a stopped or a marker-parsed answer never does.
        var note: NoteRequest? = nil
    }

    // What the model wrote for "make me a note" or "add butter to that list". The text is the
    // whole note as Markdown, read into words and formatting by AskNoteWriter the same way a
    // cleanup is. `target` is nil for a new note and a handle for a change, never an id: the handle
    // is looked up in the request's own map, like a citation.
    nonisolated struct NoteRequest: Equatable, Sendable {
        let title: String
        let text: String
        var target: String? = nil
    }

    // The OpenAI shape: {"answer": "...", "citations": ["E1"], "noteTitle": null, "noteText": null,
    // "editNoteHandle": null}. Flat nullable strings rather than a nullable object, because a
    // nullable string is the shape every schema the app sends already uses. Optional to the
    // decoder too, so an answer without them (a server that ignored the strict schema, a fixture
    // from before) still reads.
    nonisolated struct Payload: Decodable {
        let answer: String
        let citations: [String]
        let noteTitle: String?
        let noteText: String?
        let editNoteHandle: String?
    }

    // `editable` is the handles of the notes this request carried whole. An edit aimed anywhere
    // else is dropped whole rather than turned into a new note: the author asked to change
    // something, and a second copy of it is not what they asked for.
    static func parseJSON(_ text: String, known: Set<String>, editable: Set<String> = []) throws -> Answer {
        let payload = try StructuredOutputParser.decode(Payload.self, from: text)
        return Answer(
            text: payload.answer.trimmingCharacters(in: .whitespacesAndNewlines),
            handles: filtered(payload.citations, known: known),
            note: noteRequest(title: payload.noteTitle, text: payload.noteText, target: payload.editNoteHandle, editable: editable)
        )
    }

    // A note with no words is no note: a title alone would make an entry that reads as empty, and
    // an edit to nothing would empty the note.
    static func noteRequest(title: String?, text: String?, target: String? = nil, editable: Set<String> = []) -> NoteRequest? {
        let body = (text ?? "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        let heading = (title ?? "")
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        var handle: String?
        if let target, !target.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let resolved = Self.normalized(target), editable.contains(resolved) else { return nil }
            handle = resolved
        }
        return NoteRequest(title: heading, text: body, target: handle)
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
