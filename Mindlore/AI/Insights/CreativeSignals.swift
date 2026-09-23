import Foundation

// Whether an entry is creative work, decided so that a real entry is never quietly filed as a
// poem: that mistake drops its names, area, mood, and threads without anyone noticing, where the
// other one leaves a lyric on the map for the user to flip (owner, 2026-09-22).
//
// OpenAI decides it in the insights request and is trusted. Apple's on-device model is not: asked
// inside the big request it called "worked on the Memphis song tonight" creative, then called a
// four-line lyric life. So on device the shape of the text decides first, in code: prose is never
// creative. Only text laid out like verse gets a second, single-question request.
nonisolated enum CreativeSignals {
    // Laid out like a poem or a song: at least four lines, most of them a phrase long, and not a
    // list. A grocery list has short lines too, which is why one-to-three-word lines and bullets
    // count against it, and why a verse-shaped entry still has to be confirmed by the model.
    static func looksLikeVerse(_ text: String) -> Bool {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count >= 4 else { return false }
        let words = lines.map { $0.split(whereSeparator: \.isWhitespace).count }
        // A line of real prose means an account of a day, even one with a few lines of verse in
        // it: the on-device question filed "a day at the shop, then two lines of a song" as a poem.
        guard words.allSatisfy({ $0 <= 15 }) else { return false }
        let phraseLines = words.filter { (3...14).contains($0) }.count
        let listLines = lines.filter(isListItem).count + words.filter { $0 <= 2 }.count
        let averageWords = Double(words.reduce(0, +)) / Double(lines.count)
        return Double(phraseLines) >= Double(lines.count) * 0.75
            && Double(listLines) <= Double(lines.count) * 0.25
            && (2.5...12).contains(averageWords)
    }

    private static func isListItem(_ line: String) -> Bool {
        if let first = line.first, "-*•·–".contains(first) { return true }
        // "1." or "2)" at the start.
        let prefix = line.prefix(4)
        return prefix.first?.isNumber == true && (prefix.contains(".") || prefix.contains(")"))
    }

    // The single question the on-device model is asked about verse-shaped text. Three named
    // kinds rather than yes or no, so a gratitude list or standup notes have somewhere to go.
    static let poem = "poem or song lyrics"
    static let kinds = [poem, "diary entry about the writer's own day", "list or notes"]

    static func focusedRequest(for text: String) -> TextRequest {
        TextRequest(
            model: "",
            system: "Decide what kind of text this is. A poem often runs in short lines that are not full sentences, with images rather than events. A diary entry says what happened to the writer, and can quote a few lines of a song and still be a diary entry. Notes and lists name tasks or items.",
            user: String(text.prefix(2_000)),
            schema: .object([.init("kind", .enumeration(kinds, description: "What the text is."))]),
            schemaName: "text_kind",
            maxOutputTokens: 40
        )
    }

    static func parseFocused(_ text: String) -> Bool? {
        guard let data = StructuredOutputParser.jsonObjectData(in: text),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let kind = json["kind"] as? String else { return nil }
        return kind == poem
    }

    // The whole rule. `focused` is the single-question answer, nil when it wasn't asked or failed.
    static func decide(modelSaysCreative: Bool, text: String, onDevice: Bool, focused: Bool?) -> Bool {
        guard onDevice else { return modelSaysCreative }
        guard looksLikeVerse(text) else { return false }
        return focused ?? false
    }

    // The same rule over all three kinds. The cloud model's note verdict is taken as it is; on
    // device only the creative question is asked at all, and a small model that called a song
    // diary creative is not trusted to tell a list from a day either, so it never files a note.
    static func decideKind(modelSays kind: EntryKind, text: String, onDevice: Bool, focused: Bool?) -> EntryKind {
        if decide(modelSaysCreative: kind == .creative, text: text, onDevice: onDevice, focused: focused) { return .creative }
        guard !onDevice else { return .journal }
        return kind == .note ? .note : .journal
    }
}
