import Foundation

// How an entry's text is laid out, kept beside the text rather than inside it. `Entry.text` stays
// the plain words every reader (insights, Ask, search, previews, parts offsets) already reads, and
// this says which paragraphs are headings, list items, or quotes and which spans are bold, italic,
// or struck through. Paragraphs are numbered by their position among the text's newline-separated
// lines; spans are UTF-16 ranges, the unit a UITextView counts in. The user never sees any of it
// as syntax: the editor draws it, and the only Markdown in the app is at the edges (export, and a
// cleanup the model writes as Markdown so it can add structure to dictation).
nonisolated struct EntryFormatting: Codable, Equatable, Sendable {
    enum Block: String, Codable, CaseIterable, Sendable {
        case heading1, heading2, bullet, number, check, checked, quote

        var isList: Bool {
            switch self {
            case .bullet, .number, .check, .checked: true
            case .heading1, .heading2, .quote: false
            }
        }

        // What Return in this paragraph gives the next one.
        var continued: Block? {
            switch self {
            case .bullet, .number, .check, .checked, .quote: self == .checked ? .check : self
            case .heading1, .heading2: nil
            }
        }
    }

    struct Paragraph: Codable, Equatable, Sendable {
        var index: Int
        var block: Block?
        var indent: Int = 0
    }

    struct Span: Codable, Equatable, Sendable {
        var location: Int
        var length: Int
        var bold = false
        var italic = false
        var strike = false

        var isPlain: Bool { !bold && !italic && !strike }
    }

    static let maxIndent = 3

    var paragraphs: [Paragraph] = []
    var spans: [Span] = []

    static let empty = EntryFormatting()

    var isEmpty: Bool { paragraphs.isEmpty && spans.isEmpty }

    init(paragraphs: [Paragraph] = [], spans: [Span] = []) {
        self.paragraphs = paragraphs.filter { $0.block != nil || $0.indent > 0 }.sorted { $0.index < $1.index }
        self.spans = spans.filter { !$0.isPlain && $0.length > 0 }.sorted { $0.location < $1.location }
    }

    init?(raw: String?) {
        guard let raw, let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(EntryFormatting.self, from: data) else { return nil }
        self = EntryFormatting(paragraphs: decoded.paragraphs, spans: decoded.spans)
    }

    // nil when there is nothing to store, so an unformatted entry keeps a nil column.
    var raw: String? {
        guard !isEmpty, let data = try? JSONEncoder().encode(self) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    func paragraph(at index: Int) -> Paragraph {
        paragraphs.first { $0.index == index } ?? Paragraph(index: index)
    }

    mutating func setParagraph(_ paragraph: Paragraph) {
        paragraphs.removeAll { $0.index == paragraph.index }
        if paragraph.block != nil || paragraph.indent > 0 {
            paragraphs.append(paragraph)
            paragraphs.sort { $0.index < $1.index }
        }
    }
}

extension Entry {
    var formatting: EntryFormatting {
        get { EntryFormatting(raw: formattingRaw) ?? .empty }
        set { formattingRaw = newValue.raw }
    }
}
