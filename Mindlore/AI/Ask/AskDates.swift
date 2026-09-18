import Foundation

// The date range a question names, so "what did I do last week" reaches the right entries.
// English only, by design: a wrong range sends the wrong entries, and guessing at other
// languages would do that quietly. Every range is half-open, from the start of a day to the
// start of the day after the last one.
nonisolated enum AskDates {
    static func range(in question: String, now: Date, calendar: Calendar = .current) -> DateInterval? {
        let text = question.lowercased()
        if let relative = relativeRange(in: text, now: now, calendar: calendar) { return relative }
        if let counted = countedRange(in: text, now: now, calendar: calendar) { return counted }
        // An explicit day ("March 4, 2025") beats the month it names; a bare "March 2025" has no
        // day to detect and falls through to the whole month.
        if let detected = detectedDay(in: question, calendar: calendar) { return detected }
        return monthRange(in: text, now: now, calendar: calendar)
    }

    // MARK: - Fixed phrases

    private static func relativeRange(in text: String, now: Date, calendar: Calendar) -> DateInterval? {
        let today = calendar.startOfDay(for: now)
        if contains(text, "today") { return days(from: today, count: 1, calendar: calendar) }
        if contains(text, "yesterday") {
            guard let start = calendar.date(byAdding: .day, value: -1, to: today) else { return nil }
            return days(from: start, count: 1, calendar: calendar)
        }
        if contains(text, "this week") { return unit(.weekOfYear, offset: 0, from: now, calendar: calendar) }
        if contains(text, "last week") { return unit(.weekOfYear, offset: -1, from: now, calendar: calendar) }
        if contains(text, "this month") { return unit(.month, offset: 0, from: now, calendar: calendar) }
        if contains(text, "last month") { return unit(.month, offset: -1, from: now, calendar: calendar) }
        if contains(text, "this year") { return unit(.year, offset: 0, from: now, calendar: calendar) }
        if contains(text, "last year") { return unit(.year, offset: -1, from: now, calendar: calendar) }
        return nil
    }

    // "3 days ago", "the last 2 weeks", "in the past six months".
    private static func countedRange(in text: String, now: Date, calendar: Calendar) -> DateInterval? {
        let units: [(names: [String], component: Calendar.Component)] = [
            (["day", "days"], .day),
            (["week", "weeks"], .weekOfYear),
            (["month", "months"], .month),
            (["year", "years"], .year),
        ]
        let today = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return nil }

        for unit in units {
            let names = unit.names.joined(separator: "|")
            if let count = number(in: text, pattern: "(\\d+|\(numberWords.keys.joined(separator: "|")))\\s+(\(names))\\s+ago"), count > 0 {
                guard let start = calendar.date(byAdding: unit.component, value: -count, to: today) else { return nil }
                return days(from: start, count: 1, calendar: calendar)
            }
            if let count = number(in: text, pattern: "(?:last|past)\\s+(\\d+|\(numberWords.keys.joined(separator: "|")))\\s+(\(names))"), count > 0 {
                guard let start = calendar.date(byAdding: unit.component, value: -count, to: today) else { return nil }
                return DateInterval(start: start, end: tomorrow)
            }
        }
        return nil
    }

    // "in March", "March 2025". A bare month means its most recent occurrence that isn't ahead.
    //
    // A month name has to be framed as one: "may", "march" and "august" are ordinary English
    // words, and "what may I have forgotten?" must not quietly pull in a month of entries.
    private static func monthRange(in text: String, now: Date, calendar: Calendar) -> DateInterval? {
        var names = calendar.monthSymbols.map { $0.lowercased() }
        names += calendar.shortMonthSymbols.map { $0.lowercased() }
        for (index, name) in names.enumerated() {
            let month = index % 12 + 1
            guard namesAMonth(name, in: text) else { continue }
            let year = explicitYear(in: text) ?? mostRecentYear(ofMonth: month, now: now, calendar: calendar)
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = 1
            guard let start = calendar.date(from: components),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
            return DateInterval(start: start, end: end)
        }
        return nil
    }

    // Anything else explicit ("on 3 March 2025", "2025-03-04"), which gives that one day. Only a
    // match that actually names a day counts: the detector reads a bare month as its first, which
    // would silently narrow "what happened in March" to one day.
    private static func detectedDay(in question: String, calendar: Calendar) -> DateInterval? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let whole = NSRange(question.startIndex..., in: question)
        guard let match = detector.firstMatch(in: question, range: whole), let date = match.date,
              let matched = Range(match.range, in: question), namesADay(String(question[matched]))
        else { return nil }
        return days(from: calendar.startOfDay(for: date), count: 1, calendar: calendar)
    }

    // Either a preposition that can only introduce a time ("in March", "back in March"), or a
    // year right after it ("March 2025").
    private static func namesAMonth(_ name: String, in text: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let framed = "(?:(?:\\bin|\\bduring|\\bsince|\\bthroughout|\\bback in|\\bover)\\s+\(escaped)\\b)|(?:\\b\(escaped)\\s+(?:19|20)\\d{2}\\b)"
        guard let regex = try? NSRegularExpression(pattern: framed, options: [.caseInsensitive]) else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func namesADay(_ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: "(?<!\\d)\\d{1,2}(?!\\d)") else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    // MARK: - Pieces

    private static let numberWords: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
    ]

    private static func contains(_ text: String, _ phrase: String) -> Bool {
        NameMatching.range(of: phrase, in: text) != nil
    }

    private static func number(in text: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let captured = Range(match.range(at: 1), in: text) else { return nil }
        let value = String(text[captured])
        return Int(value) ?? numberWords[value]
    }

    private static func explicitYear(in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: "\\b(19|20)\\d{2}\\b"),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        return Int(text[range])
    }

    private static func mostRecentYear(ofMonth month: Int, now: Date, calendar: Calendar) -> Int {
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)
        return month <= currentMonth ? currentYear : currentYear - 1
    }

    private static func days(from start: Date, count: Int, calendar: Calendar) -> DateInterval? {
        guard let end = calendar.date(byAdding: .day, value: count, to: start) else { return nil }
        return DateInterval(start: start, end: end)
    }

    private static func unit(_ component: Calendar.Component, offset: Int, from now: Date, calendar: Calendar) -> DateInterval? {
        guard let shifted = calendar.date(byAdding: component, value: offset, to: now),
              let interval = calendar.dateInterval(of: component, for: shifted) else { return nil }
        return interval
    }
}
