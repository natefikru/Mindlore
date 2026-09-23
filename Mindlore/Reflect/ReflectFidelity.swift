import Foundation

// What a period's prompt is built from. A week reads its own entries in full; a month reads
// cached week summaries plus digest lines for whatever wasn't individually visited, never a whole
// month of entries at once (tasks/reflect-queue-spec.md).
nonisolated enum ReflectFidelity {
    nonisolated struct WeekEntry: Equatable, Sendable {
        let id: UUID
        let date: Date
        let title: String
        let text: String
        var isCreative = false
        var isNote = false
    }

    // One fenced block per entry, sanitized the same way Ask fences a block. The caller
    // (ReflectSource.weekEntries) has already applied the eligibility check. Under a character
    // limit (the on-device model) every entry keeps an equal share of its opening, so a long
    // Monday can't crowd Friday out of the week.
    static func weekPrompt(_ entries: [WeekEntry], characterLimit: Int? = nil) -> String {
        let share = characterLimit.map { limit in
            let overhead = entries.reduce(0) { $0 + $1.title.count + 40 }
            return max(160, (limit - overhead) / max(1, entries.count))
        }
        return entries.map { entry in
            let text = AskContextBuilder.sanitized(entry.text)
            let body = share.map { opening(of: text, characters: $0) } ?? text
            let marker = entry.isCreative ? AskContextBuilder.creativeMarker : (entry.isNote ? AskContextBuilder.noteMarker : "")
            return "\(AskContextBuilder.openDelimiter)\n\(AskContextBuilder.dateFormatter.string(from: entry.date)) \(entry.title)\(marker)\n\(body)\n\(AskContextBuilder.closeDelimiter)"
        }.joined(separator: "\n\n")
    }

    // Every covered week's own generated items, one fenced block per week (free: already paid
    // for), then one fenced block of digest lines for everything else in the month. Under a
    // character limit the week summaries go in first, since each already stands for a whole
    // week, and digest lines fill what's left, spread across the month rather than its first days.
    static func monthPrompt(cachedWeekItems: [[ReflectQueueItem]], digestLines: [String], characterLimit: Int? = nil) -> String {
        var blocks: [String] = []
        for items in cachedWeekItems where !items.isEmpty {
            let body = items.map { "- \($0.body)" }.joined(separator: "\n")
            blocks.append("\(AskContextBuilder.openDelimiter)\n\(body)\n\(AskContextBuilder.closeDelimiter)")
        }
        var lines = digestLines
        if let characterLimit {
            let room = characterLimit - blocks.reduce(0) { $0 + $1.count + 2 }
            lines = spread(lines, within: room)
        }
        if !lines.isEmpty {
            blocks.append("\(AskContextBuilder.openDelimiter)\n\(lines.joined(separator: "\n"))\n\(AskContextBuilder.closeDelimiter)")
        }
        return blocks.joined(separator: "\n\n")
    }

    // The first `characters` of the text, cut back to a word, with an ellipsis when it was cut.
    static func opening(of text: String, characters: Int) -> String {
        guard text.count > characters else { return text }
        let cut = text.prefix(characters)
        let word = cut.lastIndex(where: \.isWhitespace).map { cut[..<$0] } ?? cut
        return word.trimmingCharacters(in: .whitespacesAndNewlines) + "\u{2026}"
    }

    // As many lines as fit, taken evenly across the list, ends included.
    static func spread(_ lines: [String], within room: Int) -> [String] {
        guard room > 0, !lines.isEmpty else { return [] }
        let average = max(1, lines.reduce(0) { $0 + $1.count + 1 } / lines.count)
        let count = min(lines.count, room / average)
        guard count < lines.count else { return lines }
        guard count > 1 else { return count == 1 ? [lines[lines.count - 1]] : [] }
        return (0..<count).map { lines[$0 * (lines.count - 1) / (count - 1)] }
    }

    // "Week of 14 September 2026" or "September 2026", the same shape ReflectPeriodSelection.title
    // uses, built from an arbitrary interval rather than an offset from now.
    static func title(kind: ReflectSummaryKind, interval: DateInterval, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        switch kind {
        case .week:
            formatter.dateFormat = "d MMMM yyyy"
            return "Week of \(formatter.string(from: interval.start))"
        case .month:
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: interval.start)
        }
    }
}
