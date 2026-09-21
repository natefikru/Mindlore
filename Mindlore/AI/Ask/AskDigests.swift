import Foundation

// One line per entry, for the entries that matched and didn't fit whole.
//
// Twenty entries is plenty for "what did Maya say about the move" and nowhere near enough for "what
// happened this year", which matched two hundred. Rollups tell the model how many there were;
// digests tell it what they were about. A hundred and fifty lines cost about what seven whole
// entries do, so the year arrives for the price of a tail nobody wanted to read anyway.
//
// A line carries a handle, so an answer can cite a day it only saw one line of, and the chip
// resolves like any other. The prompt says a single line is a shortened entry, so a quote from one
// is never offered as everything that was written that day.
nonisolated enum AskDigests {
    // Both ends of a line are capped so the estimate below is a true upper bound: the plan reserves
    // room for digests before any entry text has been read, the way every other slice does.
    static let maxTitleCharacters = 40
    static let maxTextCharacters = 90

    // "[E123] 2026-03-14 " plus the two caps, plus the newline, rounded up.
    static let charactersPerLine = 150
    static let fenceCharacters = 20

    static func estimatedCharacters(lineCount: Int) -> Int {
        guard lineCount > 0 else { return 0 }
        return fenceCharacters + lineCount * charactersPerLine
    }

    // How many lines a number of characters buys. The inverse of the above, so the plan and the
    // renderer can never disagree about what fits.
    static func lineCapacity(characters: Int) -> Int {
        max(0, (characters - fenceCharacters) / charactersPerLine)
    }

    // Sanitized like any other block body: an entry can contain a delimiter or something shaped
    // like a handle, and a digest line is the one place entry text sits next to a handle the model
    // is meant to trust.
    static func line(handle: String, date: Date, title: String, text: String) -> String {
        var line = "[\(handle)] \(AskContextBuilder.dateFormatter.string(from: date))"
        if let title = InsightsPromptBuilder.promptSafe(AskContextBuilder.sanitized(title)) {
            line += " \(clipped(title, to: maxTitleCharacters))"
        }
        let body = clipped(flattened(AskContextBuilder.sanitized(text)), to: maxTextCharacters)
        if !body.isEmpty {
            line += ": \(body)"
        }
        return line
    }

    // One line means one line. A recording's text arrives as paragraphs, and a line break inside a
    // fenced block would read as the end of the entry.
    private static func flattened(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // Cut on a word, so a line ends on something readable rather than mid-name.
    private static func clipped(_ text: String, to limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let head = trimmed.prefix(limit)
        guard let space = head.lastIndex(of: " "), head.distance(from: head.startIndex, to: space) > limit / 2 else {
            return String(head)
        }
        return String(head[head.startIndex..<space])
    }
}
