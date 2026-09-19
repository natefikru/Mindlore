import Foundation

// "Not today" on a Today card: the day it was dismissed on, and which cards. Thrown away as soon
// as the day changes, so a dismissal is never permanent and nothing accumulates. Card keys are
// plain strings here, not the composer's own type, so settings never depends on Today's shape.
nonisolated struct TodayDismissal: Codable, Equatable, Sendable {
    var day: String = ""
    var keys: Set<String> = []

    // Year-month-day from components rather than a formatter, so no locale or calendar of the
    // user's can turn one day into two stamps.
    static func stamp(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    func keys(on day: String) -> Set<String> {
        self.day == day ? keys : []
    }

    // A dismissal on a new day starts the day over, which is also what makes a clock stepping back
    // harmless: the stamp simply stops matching and every card returns.
    mutating func dismiss(_ key: String, on day: String) {
        if self.day != day {
            self.day = day
            keys = []
        }
        keys.insert(key)
    }
}
