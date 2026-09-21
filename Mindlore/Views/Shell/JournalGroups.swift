import Foundation

// The journal in the shape Notes uses: the last few days by name, then months, then years.
//
// Pure over dates rather than entries, the way JournalFilter is pure over raw area strings, so
// the grouping and the delete mapping can be tested without a store.
nonisolated enum JournalGroup: Equatable, Hashable {
    // Backdating forward is allowed, so an entry can sit ahead of today.
    case later
    case recent
    case yesterday
    case thisWeek
    // An earlier month of the current year, named. Past years collapse into one group each.
    case month(year: Int, month: Int)
    case year(Int)
}

nonisolated enum JournalGroups {
    struct Dated: Equatable {
        let id: UUID
        let date: Date

        init(id: UUID, date: Date) {
            self.id = id
            self.date = date
        }
    }

    // Every comparison is by day, never by instant: an entry written at 8pm today is today, and
    // comparing it against `now` directly would flip it into Later on every re-render.
    static func group(for date: Date, now: Date, calendar: Calendar = .current) -> JournalGroup {
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)

        if day > today { return .later }
        if day == today { return .recent }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), day == yesterday { return .yesterday }

        // The current week, minus the two days already named. In the first days of January this
        // can reach back into December, which is right: it really is this week.
        if let week = calendar.dateInterval(of: .weekOfYear, for: today), week.contains(day) {
            return .thisWeek
        }

        let parts = calendar.dateComponents([.year, .month], from: day)
        let thisYear = calendar.component(.year, from: today)
        guard let year = parts.year, let month = parts.month else { return .year(thisYear) }
        return year == thisYear ? .month(year: year, month: month) : .year(year)
    }

    // Keeps the caller's order, which is already newest first, so no group needs re-sorting.
    static func build(_ dated: [Dated], now: Date, calendar: Calendar = .current) -> [(group: JournalGroup, ids: [UUID])] {
        var order: [JournalGroup] = []
        var ids: [JournalGroup: [UUID]] = [:]
        for item in dated {
            let group = group(for: item.date, now: now, calendar: calendar)
            if ids[group] == nil {
                order.append(group)
                ids[group] = []
            }
            ids[group]?.append(item.id)
        }
        return order.map { ($0, ids[$0] ?? []) }
    }

    // A section's swipe gives an offset into that section, not into the flat list. Named so a
    // test can exercise it: no test can drive SwiftUI's own onDelete.
    static func id(at offset: Int, in ids: [UUID]) -> UUID? {
        ids.indices.contains(offset) ? ids[offset] : nil
    }

    static func ids(at offsets: IndexSet, in ids: [UUID]) -> [UUID] {
        offsets.compactMap { id(at: $0, in: ids) }
    }

    static func title(_ group: JournalGroup, calendar: Calendar = .current) -> String {
        switch group {
        case .later: "Later"
        case .recent: "Recent"
        case .yesterday: "Yesterday"
        case .thisWeek: "This week"
        case .month(_, let month): monthName(month, calendar: calendar)
        case .year(let year): String(year)
        }
    }

    // Through a formatter rather than calendar.monthSymbols: a calendar built in a test has no
    // locale, and that returns "M08" instead of "August".
    private static func monthName(_ month: Int, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        let symbols = formatter.standaloneMonthSymbols ?? []
        guard (1...symbols.count).contains(month) else { return "" }
        return symbols[month - 1]
    }
}
