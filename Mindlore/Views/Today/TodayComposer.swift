import Foundation

// What Today shows, decided in one pure pass. Nothing here reads SwiftData; TodaySource resolves
// merges, drops hidden and muted entities, and filters future-dated entries into plain values
// first, the same way GraphServices feeds EntityGraph.
//
// The order is the product's, not an implementation detail: a thread that just closed or is due
// today, then this day in an earlier year, then the oldest thread still open, then someone who
// has gone quiet, then what you last wrote. At most three, and nothing appears twice.
nonisolated enum TodayComposer {
    static let cardLimit = 3
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
        var chosen: [TodayCard] = []
        var usedEntries: Set<UUID> = []
        var usedLooseEnds: Set<UUID> = []

        for candidate in candidates(entries, input) {
            guard chosen.count < cardLimit else { break }
            guard !input.dismissed.contains(candidate.id) else { continue }
            // Nothing backs two cards. In a young journal the newest entry can also be the one
            // from a year ago, and reading it twice looks like a bug.
            switch candidate {
            case .closed(let end), .dueToday(let end), .stillOpen(let end):
                guard usedLooseEnds.insert(end.id).inserted else { continue }
            case .onThisDay(let entry, _), .latestSummary(let entry):
                guard usedEntries.insert(entry.id).inserted else { continue }
            case .beenAWhile:
                break
            }
            chosen.append(candidate)
        }
        return chosen
    }

    // One candidate per kind, in priority order. A kind that is dismissed or already used simply
    // lets the next kind take the slot; it never offers a second of its own.
    private static func candidates(_ entries: [EntryFacts], _ input: TodayInput) -> [TodayCard] {
        let latest = entries.first
        var candidates: [TodayCard] = []

        if let settled = closedOrDue(input, latest: latest) { candidates.append(settled) }
        if let anniversary = onThisDay(entries, input) { candidates.append(anniversary) }
        if let open = stillOpen(input) { candidates.append(.stillOpen(open)) }
        if input.resurfacingEnabled, let lapsed = beenAWhile(input) { candidates.append(.beenAWhile(lapsed)) }
        if let latest, let summary = latest.summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            candidates.append(.latestSummary(latest))
        }
        return candidates
    }

    private static func closedOrDue(_ input: TodayInput, latest: EntryFacts?) -> TodayCard? {
        if let latest {
            let closed = input.looseEnds
                .filter { $0.status == .resolved && $0.resolvedByEntryID == latest.id }
                .min { older($0, $1) }
            if let closed { return .closed(closed) }
        }
        let due = input.looseEnds
            .filter { end in
                guard end.status == .open, let dueDate = end.dueDate else { return false }
                return EntryDates.isSameDay(dueDate, input.now, calendar: input.calendar)
            }
            .min { older($0, $1) }
        return due.map(TodayCard.dueToday)
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

    private static func stillOpen(_ input: TodayInput) -> LooseEndFacts? {
        input.looseEnds.filter { $0.status == .open }.min { older($0, $1) }
    }

    private static func beenAWhile(_ input: TodayInput) -> EntityFacts? {
        let cutoff = input.now.addingTimeInterval(-staleAfter)
        return input.entities
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
            .first
    }

    private static func older(_ first: LooseEndFacts, _ second: LooseEndFacts) -> Bool {
        (first.sourceEntryDate, first.id.uuidString) < (second.sourceEntryDate, second.id.uuidString)
    }
}
