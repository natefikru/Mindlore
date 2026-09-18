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

    // One line per month, newest first, from the documents the question could be answered from.
    // Only sendable ones are counted: the number the model reasons about has to match the corpus it
    // was given, and an entry Ask may not send is not part of that corpus.
    static func months(
        for intervals: [DateInterval],
        in index: AskIndex,
        calendar: Calendar = .current
    ) -> [Month] {
        intervals.compactMap { interval in
            let dates = index.documents
                .filter { $0.isSendable && $0.date >= interval.start && $0.date < interval.end }
                .map(\.date)
                .sorted()
            guard !dates.isEmpty else { return nil }
            return Month(interval: interval, count: dates.count, first: dates.first, last: dates.last)
        }
    }

    // Past two years a month a line is too many lines for what it says, so they become years.
    static func blocks(for months: [Month], calendar: Calendar = .current) -> [String] {
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
