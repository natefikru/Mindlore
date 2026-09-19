import Foundation

// Every word Today says, and every field it logs, outside any view so both can be tested without
// one. The rule for all of it: state what happened. Never suggest, never grade, never congratulate.
nonisolated enum TodayCopy {
    static func greeting(at date: Date, calendar: Calendar = .current, name: String = "") -> String {
        let hour = calendar.component(.hour, from: date)
        let part = switch hour {
        case 0..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? part : "\(part), \(trimmed)"
    }

    static func title(_ card: TodayCard, calendar: Calendar = .current, locale: Locale = .current) -> String {
        switch card {
        case .closed: "Closed"
        case .dueToday: "Due today"
        case .onThisDay(_, let span): heading(span)
        case .stillOpen: "Still open"
        case .beenAWhile(let entity): entity.name
        case .latestSummary: "Your last entry"
        }
    }

    // The body is the user's own words wherever there are any: a loose end verbatim, an entry's
    // title or summary. The app's own sentences are only ever about when something happened.
    static func body(_ card: TodayCard) -> String {
        switch card {
        case .closed(let end), .dueToday(let end), .stillOpen(let end):
            end.text
        case .onThisDay(let entry, _):
            entry.title.isEmpty ? (entry.summary ?? "") : entry.title
        case .beenAWhile:
            ""
        case .latestSummary(let entry):
            entry.summary ?? entry.title
        }
    }

    static func detail(_ card: TodayCard, calendar: Calendar = .current, locale: Locale = .current) -> String? {
        switch card {
        case .closed(let end):
            "Open since \(day(end.sourceEntryDate, locale: locale))"
        case .stillOpen(let end):
            "Since \(day(end.sourceEntryDate, locale: locale))"
        case .dueToday:
            nil
        case .onThisDay(let entry, _):
            day(entry.entryDate, locale: locale)
        case .beenAWhile(let entity):
            entity.lastLinkedAt.map { "Last appeared \(day($0, locale: locale))" }
        case .latestSummary(let entry):
            day(entry.entryDate, locale: locale)
        }
    }

    private static func heading(_ span: TodaySpan) -> String {
        switch span {
        case .yearsAgo(1): "A year ago today"
        case .yearsAgo(let years): "\(years) years ago today"
        case .monthAgo: "A month ago"
        case .sixMonthsAgo: "Six months ago"
        }
    }

    private static func day(_ date: Date, locale: Locale) -> String {
        date.formatted(.dateTime.day().month(.wide).locale(locale))
    }

    // Counts and fixed kind strings. Never a name, a quote, a title, or a date.
    static func shownFields(_ today: Today, milliseconds: Double) -> [String: DiagnosticValue] {
        [
            "cards": .int(today.cards.count),
            "kinds": .string(today.cards.map { $0.kind.rawValue }.joined(separator: ",")),
            "days": .int(today.week.filter(\.hasEntry).count),
            "milliseconds": .double(milliseconds)
        ]
    }

    static func dismissedFields(_ card: TodayCard, rank: Int) -> [String: DiagnosticValue] {
        ["kind": .string(card.kind.rawValue), "rank": .int(rank)]
    }
}
