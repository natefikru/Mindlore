import Foundation

// What Today shows, decided in one pure pass. Nothing here reads SwiftData; TodaySource resolves
// merges, drops hidden and muted entities, and filters future-dated entries into plain values
// first, the same way GraphServices feeds EntityGraph.
//
// The row's order is the product's, not an implementation detail. It opens on the open thread that
// most needs you (due today, else fading soonest), then the day's cards: a thread your last entry
// closed, this day in an earlier year, a name gone quiet, what you last wrote. Then every other
// open thread, the one that fades soonest first. Nothing appears twice.
nonisolated enum TodayComposer {
    static let weekLength = 7
    // "More than a month" in the only sense that survives a month of 28 days and one of 31.
    static let staleAfter: TimeInterval = 30 * 86_400

    static func compose(_ input: TodayInput) -> Today {
        // Newest first, and the tie-break keeps two entries sharing a noon in a stable order.
        let entries = input.entries
            .filter { $0.entryDate <= input.now }
            .sorted { ($0.entryDate, $0.id.uuidString) > ($1.entryDate, $1.id.uuidString) }

        return Today(
            greeting: TodayCopy.greeting(at: input.now, calendar: input.calendar, name: input.name),
            week: week(entries, input),
            cards: cards(entries, input)
        )
    }

    // Seven days ending today, oldest first. Presence only: a dot is filled or it isn't, and its
    // tint is that day's newest entry's first area. No count, nothing to keep up.
    private static func week(_ entries: [EntryFacts], _ input: TodayInput) -> [WeekDay] {
        guard !entries.isEmpty else { return [] }
        let startOfToday = input.calendar.startOfDay(for: input.now)
        return (0..<weekLength).reversed().compactMap { offset in
            guard let day = input.calendar.date(byAdding: .day, value: -offset, to: startOfToday) else { return nil }
            let newest = entries.first { EntryDates.isSameDay($0.entryDate, day, calendar: input.calendar) }
            return WeekDay(date: day, hasEntry: newest != nil, tint: newest?.areas.first)
        }
    }

    private static func cards(_ entries: [EntryFacts], _ input: TodayInput) -> [TodayCard] {
        let latest = entries.first
        let open = input.looseEnds.filter { $0.status == .open }.sorted(by: fadesSooner)
        let dueToday = open.filter { end in
            end.dueDate.map { EntryDates.isSameDay($0, input.now, calendar: input.calendar) } ?? false
        }

        // A day card the user put away is gone until tomorrow; a thread card never is.
        var day: [TodayCard] = []
        if let latest, let closed = closed(by: latest, input) { day.append(.closed(closed)) }
        if let anniversary = onThisDay(entries, input) { day.append(anniversary) }
        if input.resurfacingEnabled, let lapsed = beenAWhile(input) { day.append(.beenAWhile(lapsed)) }
        if let latest, let summary = latest.summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            day.append(.latestSummary(latest))
        }
        day = day.filter { !input.dismissed.contains($0.id) }
        // In a young journal the newest entry can also be the one from a year ago, and reading it
        // twice looks like a bug.
        if case .onThisDay(let entry, _) = day.first(where: { $0.kind == .onThisDay }) {
            day.removeAll { if case .latestSummary(let latest) = $0 { latest.id == entry.id } else { false } }
        }

        // The row always opens on a thread when there is one (the one due today, else the one that
        // fades soonest), then the day's cards, then the rest of the threads.
        let threads = dueToday.map(TodayCard.dueToday)
            + open.filter { end in !dueToday.contains { $0.id == end.id } }.map(TodayCard.stillOpen)
        return Array(threads.prefix(1)) + day + Array(threads.dropFirst())
    }

    private static func closed(by latest: EntryFacts, _ input: TodayInput) -> LooseEndFacts? {
        input.looseEnds
            .filter { $0.status == .resolved && $0.resolvedByEntryID == latest.id }
            .min { older($0, $1) }
    }

    private static func onThisDay(_ entries: [EntryFacts], _ input: TodayInput) -> TodayCard? {
        let matches = entries.compactMap { entry -> (EntryFacts, TodaySpan)? in
            span(of: entry, input).map { (entry, $0) }
        }
        // Several spans can land on one day. The furthest back wins, and that is the only
        // on-this-day card there is: dismissing it does not promote the runner-up.
        let best = matches.min { first, second in
            (rank(first.1), first.0.id.uuidString) < (rank(second.1), second.0.id.uuidString)
        }
        return best.map { TodayCard.onThisDay($0.0, $0.1) }
    }

    private static func rank(_ span: TodaySpan) -> Int {
        switch span {
        case .yearsAgo(let years): -years
        case .monthAgo: Int.max - 1
        case .sixMonthsAgo: Int.max
        }
    }

    private static func span(of entry: EntryFacts, _ input: TodayInput) -> TodaySpan? {
        let calendar = input.calendar
        let then = calendar.dateComponents([.year, .month, .day], from: entry.entryDate)
        let today = calendar.dateComponents([.year, .month, .day], from: input.now)

        if let thisYear = today.year, let thatYear = then.year, thisYear > thatYear {
            if then.month == today.month, then.day == today.day {
                return .yearsAgo(thisYear - thatYear)
            }
            // A leap-day entry has no anniversary three years in four. It surfaces on the 28th
            // rather than never.
            if then.month == 2, then.day == 29, today.month == 2, today.day == 28,
               let days = calendar.range(of: .day, in: .month, for: input.now), !days.contains(29) {
                return .yearsAgo(thisYear - thatYear)
            }
        }
        // Calendar arithmetic, not 30 or 180 days, so the month is the one the user would name.
        if let monthAgo = calendar.date(byAdding: .month, value: -1, to: input.now),
           EntryDates.isSameDay(entry.entryDate, monthAgo, calendar: calendar) {
            return .monthAgo
        }
        if let halfYearAgo = calendar.date(byAdding: .month, value: -6, to: input.now),
           EntryDates.isSameDay(entry.entryDate, halfYearAgo, calendar: calendar) {
            return .sixMonthsAgo
        }
        return nil
    }

    // A different quiet name each day, the same one all day: one who is never written about
    // again shouldn't hold the card for good while the rest wait behind them. Ranked the way it
    // always was, then rotated by the day.
    private static func beenAWhile(_ input: TodayInput) -> EntityFacts? {
        let cutoff = input.now.addingTimeInterval(-staleAfter)
        let quiet = input.entities
            .filter { entity in
                guard let last = entity.lastLinkedAt else { return false }
                return entity.linkCount > 0 && entity.kind.isAName && last < cutoff
            }
            .sorted { first, second in
                if first.linkCount != second.linkCount { return first.linkCount > second.linkCount }
                let firstSeen = first.lastLinkedAt ?? .distantPast
                let secondSeen = second.lastLinkedAt ?? .distantPast
                if firstSeen != secondSeen { return firstSeen < secondSeen }
                return first.id.uuidString < second.id.uuidString
            }
        guard !quiet.isEmpty else { return nil }
        let day = input.calendar.ordinality(of: .day, in: .era, for: input.now) ?? 0
        return quiet[day % quiet.count]
    }

    private static func fadesSooner(_ first: LooseEndFacts, _ second: LooseEndFacts) -> Bool {
        (first.fadeDate, first.sourceEntryDate, first.id.uuidString) < (second.fadeDate, second.sourceEntryDate, second.id.uuidString)
    }

    private static func older(_ first: LooseEndFacts, _ second: LooseEndFacts) -> Bool {
        (first.sourceEntryDate, first.id.uuidString) < (second.sourceEntryDate, second.id.uuidString)
    }
}
