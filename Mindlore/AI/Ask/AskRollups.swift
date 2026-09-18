import Foundation

// Counts, so an aggregate question is answered about the whole stretch rather than from whatever
// twelve entries fit.
//
// "How have I been feeling this year?" matches three hundred entries and sends twelve. Without a
// rollup the model has no way to know it is looking at a sample, so it answers the year from the
// last two weeks, in a confident voice, citing real entries. That is the only failure mode in Ask
// that produces a wrong answer rather than a thin one.
//
// Counts and coverage only (owner, 2026-09-18). Mood distribution, area split, and top tags are
// Reflect's data and `tasks/todo.md` reserves them for that phase, so a block here carries nothing
// but numbers, a month name, and two dates: no title, no tag, no name, no sentence of entry text.
nonisolated enum AskRollups {
    static let maxMonthsBeforeRollingUpByYear = 24

    nonisolated struct Month: Sendable, Equatable {
        let interval: DateInterval
        let count: Int
        let first: Date?
        let last: Date?
    }

    // One line per month, newest first, counting **the entries that matched** and nothing else.
    //
    // Counting every entry in the month instead is the mistake this exists to prevent, wearing the
    // rollup's own clothes: the prompt tells the model the block summarizes what matched, so a
    // month line saying 214 turns "what happened with the deadline?" into "you wrote about the
    // deadline 214 times in March". It also contradicts the "12 of 30" line in the same prompt.
    static func months(
        for intervals: [DateInterval],
        matching matched: Set<UUID>,
        in index: AskIndex,
        calendar: Calendar = .current
    ) -> [Month] {
        let dates = index.documents
            .filter { matched.contains($0.id) && $0.isSendable }
            .map(\.date)
        return intervals.compactMap { interval in
            let inside = dates.filter { $0 >= interval.start && $0 < interval.end }.sorted()
            guard !inside.isEmpty else { return nil }
            return Month(interval: interval, count: inside.count, first: inside.first, last: inside.last)
        }
    }

    // What reserving room for these costs, before any of them is rendered. It has to know about the
    // year path, or the plan reserves for 36 month lines that are about to become three year lines.
    static func estimatedCharacters(monthCount: Int) -> Int {
        guard monthCount > 0 else { return 0 }
        let lines = monthCount > maxMonthsBeforeRollingUpByYear
            ? max(1, Int((Double(monthCount) / 12).rounded(.up)))
            : monthCount
        return fenceCharacters + lines * charactersPerLine
    }

    // A month line at its longest: "September 2026: 31 entries, 1 September to 30 September".
    static let charactersPerLine = 60
    static let fenceCharacters = 20

    // One block, not one per month: the prompt's rule calls it "a list of months and counts", and
    // twenty-four separate fences cost seventeen characters each to say the same thing.
    static func block(for months: [Month], calendar: Calendar = .current) -> String? {
        let lines = self.lines(for: months, calendar: calendar)
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    // Past two years a month a line is too many lines for what it says, so they become years.
    static func lines(for months: [Month], calendar: Calendar = .current) -> [String] {
        guard months.count > maxMonthsBeforeRollingUpByYear else {
            return months.map { line(for: $0, calendar: calendar) }
        }
        var byYear: [Int: (count: Int, months: Int)] = [:]
        for month in months {
            let year = calendar.component(.year, from: month.interval.start)
            let found = byYear[year] ?? (0, 0)
            byYear[year] = (found.count + month.count, found.months + 1)
        }
        return byYear.sorted { $0.key > $1.key }.map { year, totals in
            "\(year): \(entries(totals.count)) across \(totals.months) months"
        }
    }

    static func line(for month: Month, calendar: Calendar = .current) -> String {
        var line = "\(formatter("MMMM yyyy", calendar).string(from: month.interval.start)): \(entries(month.count))"
        if let first = month.first, let last = month.last {
            let day = formatter("d MMMM", calendar)
            let from = day.string(from: first)
            let to = day.string(from: last)
            line += from == to ? ", \(from)" : ", \(from) to \(to)"
        }
        return line
    }

    private static func entries(_ count: Int) -> String {
        count == 1 ? "1 entry" : "\(count) entries"
    }

    // The formatter has to read dates in the same zone the intervals were built in. Left on the
    // system zone, a month interval starting at midnight UTC formats as the month before for anyone
    // west of it, so a summary of September was labelled August.
    private static func formatter(_ format: String, _ calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter
    }
}
