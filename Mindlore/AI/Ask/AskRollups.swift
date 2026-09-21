import Foundation

// Counts, so an aggregate question is answered about the whole stretch rather than from whatever
// twelve entries fit.
//
// "How have I been feeling this year?" matches three hundred entries and sends twelve. Without a
// rollup the model has no way to know it is looking at a sample, so it answers the year from the
// last two weeks, in a confident voice, citing real entries. That is the only failure mode in Ask
// that produces a wrong answer rather than a thin one.
//
// Counts and coverage, plus mood and area distribution (owner, 2026-09-18, revised for Reflect
// 2026-09-21): a block here carries numbers, a month name, two dates, and a mood/area shape built
// from `ReflectAggregator` — the same aggregator Reflect's charts read, so there is one source for
// these counts, not two. Top tags stay out: a tag is closer to the entry's own words than a mood
// category or a life area name, so it stays off every block a model sees, same as a title or a
// name.
nonisolated enum AskRollups {
    static let maxMonthsBeforeRollingUpByYear = 24
    // How many distinct moods/areas a line names, highest count first, so a month with all nine
    // areas touched doesn't turn one line into a wall of text.
    static let maxDistributionEntriesInLine = 3

    nonisolated struct Month: Sendable, Equatable {
        let interval: DateInterval
        let count: Int
        let first: Date?
        let last: Date?
        let period: ReflectAggregator.Period
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
        let documents = index.documents.filter { matched.contains($0.id) && $0.isSendable }
        return intervals.compactMap { interval in
            let inside = documents.filter { $0.date >= interval.start && $0.date < interval.end }
            guard !inside.isEmpty else { return nil }
            let dates = inside.map(\.date).sorted()
            let facts = inside.map { document in
                ReflectAggregator.EntryFact(
                    date: document.date,
                    mood: moodCategory(from: document.mood),
                    areas: lifeAreas(from: document.areas)
                )
            }
            let period = ReflectAggregator.aggregate(facts: facts, in: interval)
            return Month(interval: interval, count: inside.count, first: dates.first, last: dates.last, period: period)
        }
    }

    // `AskIndex` stores the specific mood written (`Mood.rawValue`, e.g. "tired") and each area's
    // fixed default name (`LifeArea.defaultName`, e.g. "Work") — see `AskSources.documents(in:)`.
    // Rolling the mood up to its category, same as Reflect's own charts do, keeps the line a shape
    // rather than the specific word the entry used.
    private static func moodCategory(from raw: String?) -> MoodCategory? {
        raw.flatMap(Mood.init(rawValue:))?.category
    }

    private static func lifeAreas(from raw: [String]) -> [LifeArea] {
        raw.compactMap { LifeArea(rawValue: $0.lowercased()) }
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

    // A month line at its longest: "September 2026: 31 entries, 1 September to 30 September
    // (mood: calm 4, reflective 3, anxious 2; areas: work 3, health 2, home 1)".
    static let charactersPerLine = 150
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
        struct YearTotals {
            var count = 0
            var months = 0
            var moodCounts: [MoodCategory: Int] = [:]
            var areaCounts: [LifeArea: Int] = [:]
        }
        var byYear: [Int: YearTotals] = [:]
        for month in months {
            let year = calendar.component(.year, from: month.interval.start)
            var totals = byYear[year] ?? YearTotals()
            totals.count += month.count
            totals.months += 1
            for (mood, count) in month.period.moodCounts { totals.moodCounts[mood, default: 0] += count }
            for (area, count) in month.period.areaCounts { totals.areaCounts[area, default: 0] += count }
            byYear[year] = totals
        }
        return byYear.sorted { $0.key > $1.key }.map { year, totals in
            var line = "\(year): \(entries(totals.count)) across \(totals.months) months"
            if let suffix = distributionSuffix(moodCounts: totals.moodCounts, areaCounts: totals.areaCounts) {
                line += " (\(suffix))"
            }
            return line
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
        if let suffix = distributionSuffix(moodCounts: month.period.moodCounts, areaCounts: month.period.areaCounts) {
            line += " (\(suffix))"
        }
        return line
    }

    private static func entries(_ count: Int) -> String {
        count == 1 ? "1 entry" : "\(count) entries"
    }

    // "mood: calm 4, reflective 3; areas: work 3, health 2" — numbers and category names only,
    // highest count first, capped so a busy period reads as a shape rather than a full table.
    private static func distributionSuffix(
        moodCounts: [MoodCategory: Int],
        areaCounts: [LifeArea: Int]
    ) -> String? {
        func rendered<Key: RawRepresentable>(_ counts: [Key: Int]) -> String where Key.RawValue == String {
            counts
                .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.rawValue < $1.key.rawValue }
                .prefix(maxDistributionEntriesInLine)
                .map { "\($0.key.rawValue) \($0.value)" }
                .joined(separator: ", ")
        }
        var parts: [String] = []
        if !moodCounts.isEmpty { parts.append("mood: \(rendered(moodCounts))") }
        if !areaCounts.isEmpty { parts.append("areas: \(rendered(areaCounts))") }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
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
