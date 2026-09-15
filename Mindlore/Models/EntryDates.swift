import Foundation

// A day the user picks is stored as noon of that day, so the date stays on the same calendar day
// through any time zone change under 12 hours. The calendar is injected so tests control the zone.
nonisolated enum EntryDates {
    static func noon(of date: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        return noon(year: day.year, month: day.month, day: day.day, calendar: calendar) ?? date
    }

    // Parses a model's "yyyy-MM-dd" answer. Anything partial or impossible (2025-02-30) is nil.
    static func parseDay(_ string: String, calendar: Calendar = .current) -> Date? {
        let parts = string.trimmingCharacters(in: .whitespaces).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        guard let result = noon(year: year, month: month, day: day, calendar: calendar) else { return nil }
        let check = calendar.dateComponents([.year, .month, .day], from: result)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        return result
    }

    static func isSameDay(_ first: Date, _ second: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(first, inSameDayAs: second)
    }

    private static func noon(year: Int?, month: Int?, day: Int?, calendar: Calendar) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return calendar.date(from: components)
    }
}
