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
        // "since April", "since 2025": everything from then until now, not the month or year itself.
        if let since = sinceRange(in: text, now: now, calendar: calendar) { return since }
        if let month = monthRange(in: text, now: now, calendar: calendar) { return month }
        if let season = seasonRange(in: text, now: now, calendar: calendar) { return season }
        // Last, so "April 2025" is April and not the whole year.
        return yearRange(in: text, now: now, calendar: calendar)
    }

    // MARK: - Years

    // A bare year, which every other branch misses: "how was 2025" reached the right entries only
    // because each one indexes its own month and year as a term, so it ranked instead of filtering
    // and the year was never the denominator the rollup and the sample note are measured against.
    private static func yearRange(in text: String, now: Date, calendar: Calendar) -> DateInterval? {
        guard let year = explicitYear(in: text) else { return nil }
        // Not a year the journal could hold. Better no range than every entry filtered away.
        let currentYear = calendar.component(.year, from: now)
        guard year <= currentYear else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = 1
        components.day = 1
        guard let start = calendar.date(from: components),
              let end = calendar.date(byAdding: .year, value: 1, to: start) else { return nil }
        return DateInterval(start: start, end: end)
    }

    // MARK: - Seasons

    // Meteorological, which is what people mean: summer is June to August, and winter straddles the
    // new year. Framed like a month, because "fall" and "spring" are ordinary verbs.
    private struct Season {
        let names: [String]
        let startMonth: Int
        // Winter's start belongs to the year before the one it is named for, so "winter 2025" is
        // December 2024 to February 2025.
        var startsYearEarlier = false

        func interval(year: Int, calendar: Calendar) -> DateInterval? {
            var components = DateComponents()
            components.year = startsYearEarlier ? year - 1 : year
            components.month = startMonth
            components.day = 1
            guard let start = calendar.date(from: components),
                  let end = calendar.date(byAdding: .month, value: 3, to: start) else { return nil }
            return DateInterval(start: start, end: end)
        }
    }

    private static let seasons = [
        Season(names: ["spring"], startMonth: 3),
        Season(names: ["summer"], startMonth: 6),
        Season(names: ["autumn", "fall"], startMonth: 9),
        Season(names: ["winter"], startMonth: 12, startsYearEarlier: true),
    ]

    private static func seasonRange(in text: String, now: Date, calendar: Calendar) -> DateInterval? {
        let currentYear = calendar.component(.year, from: now)
        for season in seasons {
            guard season.names.contains(where: { namesATime($0, in: text) }) else { continue }
            if let year = explicitYear(in: text) {
                return season.interval(year: year, calendar: calendar)
            }
            // The most recent one that has started. In December that is the winter just begun.
            for year in [currentYear + 1, currentYear, currentYear - 1] {
                guard let interval = season.interval(year: year, calendar: calendar) else { continue }
                guard interval.start <= now else { continue }
                // "last summer" said during the summer means the one before this one. Said in
                // November it means the one that just ended, which is this same interval.
                guard interval.contains(now), saysLast(season.names, in: text) else { return interval }
                return season.interval(year: year - 1, calendar: calendar)
            }
        }
        return nil
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

    // "since April", "since 2025". A month or year named after "since" is where a stretch starts,
    // not the stretch itself: answering "how has it been since April" from April alone leaves out
    // everything it was asking about.
    private static func sinceRange(in text: String, now: Date, calendar: Calendar) -> DateInterval? {
        guard let regex = try? NSRegularExpression(pattern: "\\bsince\\s+(?:the\\s+)?([a-z]+|(?:19|20)\\d{2})\\b", options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let captured = Range(match.range(at: 1), in: text) else { return nil }
        let word = String(text[captured]).lowercased()
        let today = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return nil }

        var start: Date?
        if let year = Int(word), (1900...2100).contains(year) {
            var components = DateComponents()
            components.year = year
            components.month = 1
            components.day = 1
            start = calendar.date(from: components)
        } else if let month = monthSymbols.firstIndex(where: { $0 == word || $0.hasPrefix(word) && word.count >= 3 }).map({ $0 % 12 + 1 }) {
            var components = DateComponents()
            components.year = mostRecentYear(ofMonth: month, now: now, calendar: calendar)
            components.month = month
            components.day = 1
            start = calendar.date(from: components)
        } else if let season = seasons.first(where: { $0.names.contains(word) }) {
            let currentYear = calendar.component(.year, from: now)
            start = [currentYear + 1, currentYear, currentYear - 1]
                .compactMap { season.interval(year: $0, calendar: calendar) }
                .first { $0.start <= now }?
                .start
        }
        guard let start, start < tomorrow else { return nil }
        return DateInterval(start: start, end: tomorrow)
    }

    // "in March", "March 2025". A bare month means its most recent occurrence that isn't ahead.
    //
    // A month name has to be framed as one: "may", "march" and "august" are ordinary English
    // words, and "what may I have forgotten?" must not quietly pull in a month of entries.
    private static func monthRange(in text: String, now: Date, calendar: Calendar) -> DateInterval? {
        for (index, name) in monthSymbols.enumerated() {
            let month = index % 12 + 1
            guard namesATime(name, in: text) else { continue }
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

    // Either a word that can only introduce a time ("in March", "back in March", "my summer",
    // "last winter"), or a year right after it ("March 2025"). The framing matters more for seasons
    // than for months: "fall" and "spring" are ordinary verbs, and "did I fall?" must not pull in
    // three months of entries.
    private static func saysLast(_ names: [String], in text: String) -> Bool {
        names.contains { name in
            let escaped = NSRegularExpression.escapedPattern(for: name)
            guard let regex = try? NSRegularExpression(pattern: "\\blast\\s+(?:the\\s+)?\(escaped)\\b", options: [.caseInsensitive]) else { return false }
            return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }
    }

    private static func namesATime(_ name: String, in text: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let openers = "\\bin|\\bduring|\\bsince|\\bthroughout|\\bback in|\\bover|\\bmy|\\blast|\\bthis|\\bearly|\\blate"
        let framed = "(?:(?:\(openers))\\s+(?:the\\s+)?\(escaped)\\b)|(?:\\b\(escaped)\\s+(?:19|20)\\d{2}\\b)"
        guard let regex = try? NSRegularExpression(pattern: framed, options: [.caseInsensitive]) else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func namesADay(_ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: "(?<!\\d)\\d{1,2}(?!\\d)") else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    // MARK: - Pieces

    private static let numberWords: [String: Int] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
    ]

    // Fixed English, like the stop list, the season names, and AskIndex's own month term. Taken
    // from the calendar the caller passed, they came from the device's locale: a phone set to French
    // stopped understanding "in April" while every other date phrase in here stayed English.
    static let monthSymbols: [String] = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.monthSymbols.map { $0.lowercased() } + formatter.shortMonthSymbols.map { $0.lowercased() }
    }()

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
