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
    }

    // One fenced block per entry, sanitized the same way Ask fences a block. The caller
    // (ReflectSource.weekEntries) has already applied the eligibility check.
    static func weekPrompt(_ entries: [WeekEntry]) -> String {
        entries.map { entry in
            "\(AskContextBuilder.openDelimiter)\n\(AskContextBuilder.dateFormatter.string(from: entry.date)) \(entry.title)\n\(AskContextBuilder.sanitized(entry.text))\n\(AskContextBuilder.closeDelimiter)"
        }.joined(separator: "\n\n")
    }

    // Every covered week's own generated items, one fenced block per week (free: already paid
    // for), then one fenced block of digest lines for everything else in the month.
    static func monthPrompt(cachedWeekItems: [[ReflectQueueItem]], digestLines: [String]) -> String {
        var blocks: [String] = []
        for items in cachedWeekItems where !items.isEmpty {
            let body = items.map { "- \($0.body)" }.joined(separator: "\n")
            blocks.append("\(AskContextBuilder.openDelimiter)\n\(body)\n\(AskContextBuilder.closeDelimiter)")
        }
        if !digestLines.isEmpty {
            blocks.append("\(AskContextBuilder.openDelimiter)\n\(digestLines.joined(separator: "\n"))\n\(AskContextBuilder.closeDelimiter)")
        }
        return blocks.joined(separator: "\n\n")
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
