import Foundation

// Reflect's Loose ends tab: every loose end the journal has raised, open or closed, newest first,
// grouped by month. Plain values in, rows out, no SwiftData: `ReflectLooseEndSource` has already
// walked merges and dropped anything about a hidden name, the split `TodayComposer` keeps from
// `TodaySource`.
//
// Ordered by the journal date of the entry that raised it (`sourceEntryDate`), not by when the
// app wrote the record or when it last changed: a backdated page's thread sits with that page, and
// closing or reopening one never moves it in the list.
nonisolated enum ReflectLooseEnds {
    enum Filter: String, CaseIterable, Identifiable, Sendable {
        case all, open, closed

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: "All"
            case .open: "Open"
            case .closed: "Closed"
            }
        }

        // Closed is every ending: done, let go, and faded.
        func admits(_ status: LooseEndStatus) -> Bool {
            switch self {
            case .all: true
            case .open: status == .open
            case .closed: status != .open
            }
        }
    }

    struct Item: Equatable, Sendable, Identifiable {
        let id: UUID
        let text: String
        let status: LooseEndStatus
        // The journal date of the entry that raised it: where it sits in the list.
        let raisedOn: Date
        let dueDate: Date?
        // The last change of status, by the user, a later entry, or the fade sweep.
        let statusChangedAt: Date?
        let userTouched: Bool
        let sourceEntryID: UUID?
        // Names it is about, merges walked, hidden ones never here.
        let subjects: [String]

        init(
            id: UUID = UUID(),
            text: String,
            status: LooseEndStatus = .open,
            raisedOn: Date,
            dueDate: Date? = nil,
            statusChangedAt: Date? = nil,
            userTouched: Bool = false,
            sourceEntryID: UUID? = nil,
            subjects: [String] = []
        ) {
            self.id = id
            self.text = text
            self.status = status
            self.raisedOn = raisedOn
            self.dueDate = dueDate
            self.statusChangedAt = statusChangedAt
            self.userTouched = userTouched
            self.sourceEntryID = sourceEntryID
            self.subjects = subjects
        }

        var isOpen: Bool { status == .open }

        // When it ended, if it has. Not for an open one, even a reopened one.
        var closedAt: Date? { isOpen ? nil : statusChangedAt }

        // The same reading as `LooseEnd.reopenedAt`: open, touched, so the last change was a reopen.
        var reopenedAt: Date? { isOpen && userTouched ? statusChangedAt : nil }
    }

    struct Month: Equatable, Sendable, Identifiable {
        let start: Date
        let items: [Item]

        var id: Date { start }
    }

    // Newest raised first. Ties (two threads from one entry) by text, then id, so the order never
    // shuffles between refreshes.
    static func ordered(_ items: [Item]) -> [Item] {
        items.sorted { first, second in
            if first.raisedOn != second.raisedOn { return first.raisedOn > second.raisedOn }
            if first.text != second.text { return first.text < second.text }
            return first.id.uuidString < second.id.uuidString
        }
    }

    static func filtered(_ items: [Item], by filter: Filter) -> [Item] {
        items.filter { filter.admits($0.status) }
    }

    // The filter's items in order, cut into calendar months of the date they were raised.
    static func months(_ items: [Item], filter: Filter = .all, calendar: Calendar = .current) -> [Month] {
        var months: [Month] = []
        for item in ordered(filtered(items, by: filter)) {
            let start = calendar.dateInterval(of: .month, for: item.raisedOn)?.start ?? calendar.startOfDay(for: item.raisedOn)
            if let last = months.last, last.start == start {
                months[months.count - 1] = Month(start: start, items: last.items + [item])
            } else {
                months.append(Month(start: start, items: [item]))
            }
        }
        return months
    }

    // What the list shows: every open one pinned above the months, then the closed ones by the month
    // they were raised in. An open thread is the one thing on this page asking for something, so it
    // never sits under a year of settled ones (owner, 2026-09-24).
    struct Layout: Equatable, Sendable {
        let open: [Item]
        let months: [Month]

        var isEmpty: Bool { open.isEmpty && months.isEmpty }
    }

    static func layout(_ items: [Item], filter: Filter = .all, calendar: Calendar = .current) -> Layout {
        let open = filter.admits(.open) ? openFirst(items.filter(\.isOpen)) : []
        let closed = filter == .open ? [] : items.filter { !$0.isOpen }
        return Layout(open: open, months: months(closed, filter: filter, calendar: calendar))
    }

    // Open ones by what needs attention first: a due date, soonest first, then the newest raised.
    static func openFirst(_ items: [Item]) -> [Item] {
        let newest = ordered(items)
        let rank = Dictionary(uniqueKeysWithValues: newest.enumerated().map { ($1.id, $0) })
        return newest.sorted { first, second in
            switch (first.dueDate, second.dueDate) {
            case let (a?, b?) where a != b: return a < b
            case (.some, nil): return true
            case (nil, .some): return false
            default: return rank[first.id, default: 0] < rank[second.id, default: 0]
            }
        }
    }

    // MARK: - Copy

    static func statusTitle(_ status: LooseEndStatus) -> String {
        switch status {
        case .open: "Open"
        case .resolved: "Done"
        case .faded: "Faded"
        case .dismissed: "Let go"
        }
    }

    // A shape per status, so the status never rests on colour alone.
    static func symbol(_ status: LooseEndStatus) -> String {
        switch status {
        case .open: "circle"
        case .resolved: "checkmark.circle"
        case .faded: "moon.zzz"
        case .dismissed: "xmark.circle"
        }
    }

    static func monthTitle(_ start: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        start.formatted(style(calendar: calendar, locale: locale).month(.wide).year())
    }

    // "Raised Sep 3 · due Sep 30", "Raised Sep 3 · done Sep 20", "Raised Sep 3 · settled by a
    // later entry Sep 20", "Raised Sep 3 · reopened Sep 22" (in en_US). The month header carries
    // the raised date's year; any other date names its own year when it differs.
    static func detail(_ item: Item, calendar: Calendar = .current, locale: Locale = .current) -> String {
        func other(_ date: Date) -> String {
            day(date, relativeTo: item.raisedOn, calendar: calendar, locale: locale)
        }
        var parts = ["Raised \(other(item.raisedOn))"]
        switch item.status {
        case .open:
            if let due = item.dueDate { parts.append("due \(other(due))") }
            if let reopened = item.reopenedAt { parts.append("reopened \(other(reopened))") }
        case .resolved:
            let how = item.userTouched ? "done" : "settled by a later entry"
            parts.append(item.closedAt.map { "\(how) \(other($0))" } ?? how)
        case .faded:
            parts.append(item.closedAt.map { "faded \(other($0))" } ?? "faded")
        case .dismissed:
            parts.append(item.closedAt.map { "let go \(other($0))" } ?? "let go")
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    private static func day(_ date: Date, relativeTo anchor: Date, calendar: Calendar, locale: Locale) -> String {
        let base = style(calendar: calendar, locale: locale).day().month(.abbreviated)
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: anchor)
        return date.formatted(sameYear ? base : base.year())
    }

    private static func style(calendar: Calendar, locale: Locale) -> Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }
}
