import Foundation

// The feed's shape: the last `recentWeekCount` weeks in full, newest first, then every month
// before that back to the journal's first entry, collapsed. Pure: no SwiftData, no entry counts
// (a month with zero entries is skipped, but that's the caller's job once it has fetched them).
nonisolated enum ReflectFeed {
    static let defaultRecentWeekCount = 8

    nonisolated struct WeekRow: Identifiable, Equatable, Sendable {
        let interval: DateInterval
        let isCurrent: Bool
        var id: Date { interval.start }
    }

    nonisolated struct MonthRow: Identifiable, Equatable, Sendable {
        let interval: DateInterval
        var id: Date { interval.start }
    }

    // The current week first, then each week before it, for `recentWeekCount` weeks total.
    static func recentWeeks(recentWeekCount: Int = defaultRecentWeekCount, now: Date, calendar: Calendar = .current) -> [WeekRow] {
        guard var cursor = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
        var weeks: [WeekRow] = []
        for index in 0..<recentWeekCount {
            weeks.append(WeekRow(interval: cursor, isCurrent: index == 0))
            guard let previousAnchor = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor.start),
                  let previous = calendar.dateInterval(of: .weekOfYear, for: previousAnchor) else { break }
            cursor = previous
        }
        return weeks
    }

    // Every calendar month whose own interval falls entirely before `weekStart` (the oldest recent
    // week's start), back to the month `earliestEntryDate` falls in, newest first. A month's own
    // interval never overlaps the recent-weeks stretch, since every day in that stretch already
    // belongs to a week row.
    static func months(beforeWeekStart weekStart: Date, earliestEntryDate: Date, calendar: Calendar = .current) -> [MonthRow] {
        guard let earliestMonth = calendar.dateInterval(of: .month, for: earliestEntryDate),
              let dayBefore = calendar.date(byAdding: .day, value: -1, to: weekStart),
              var cursor = calendar.dateInterval(of: .month, for: dayBefore) else { return [] }
        if cursor.end > weekStart {
            guard let previousAnchor = calendar.date(byAdding: .month, value: -1, to: cursor.start),
                  let previous = calendar.dateInterval(of: .month, for: previousAnchor) else { return [] }
            cursor = previous
        }
        var months: [MonthRow] = []
        while cursor.start >= earliestMonth.start {
            months.append(MonthRow(interval: cursor))
            guard let previousAnchor = calendar.date(byAdding: .month, value: -1, to: cursor.start),
                  let previous = calendar.dateInterval(of: .month, for: previousAnchor) else { break }
            cursor = previous
        }
        return months
    }

    // The weeks inside a month row, for its fold-out: every week whose start falls inside the
    // month, oldest first.
    static func weeks(in monthInterval: DateInterval, calendar: Calendar = .current) -> [WeekRow] {
        var weeks: [WeekRow] = []
        var seen: Set<Date> = []
        var cursor = monthInterval.start
        while cursor < monthInterval.end {
            if let week = calendar.dateInterval(of: .weekOfYear, for: cursor),
               week.start >= monthInterval.start, week.start < monthInterval.end,
               seen.insert(week.start).inserted {
                weeks.append(WeekRow(interval: week, isCurrent: false))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return weeks.sorted { $0.interval.start < $1.interval.start }
    }
}
