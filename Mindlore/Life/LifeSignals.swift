import Foundation

// Every number Reflect's Life side shows, from facts the caller already fetched. No SwiftData, the
// `ReflectAggregator` split: `LifeSource` fetches, this decides. Code finds a pattern and a model
// may only word it later (tasks/reflect-tab-and-life.md, Life's rules), so every card here comes
// with the counts it stands on and a floor below which it says nothing.
//
// Two things shape every comparison. Mood is measured against the author's own baseline, never
// absolutely, because people write more on hard days and a journal reads heavier than a life. And
// an area's share is of the entries in the window, where an entry may carry two areas, so shares
// can sum past a whole and are never shown as parts of one.
nonisolated enum LifeSignals {
    // MARK: - Facts in

    struct EntryFact: Sendable, Equatable {
        let id: UUID
        let date: Date
        let areas: [LifeArea]
        // -1, 0, or +1 from the primary mood (`MoodCategory.valence`); nil when there's no mood,
        // which is every note and creative piece.
        let valence: Int?
        let tags: [String]

        init(id: UUID = UUID(), date: Date, areas: [LifeArea] = [], valence: Int? = nil, tags: [String] = []) {
            self.id = id
            self.date = date
            self.areas = areas
            self.valence = valence
            self.tags = tags
        }
    }

    struct ThreadFact: Sendable, Equatable {
        let id: UUID
        let status: LooseEndStatus
        // The raising entry's journal day, as Reflect's Loose ends reads it.
        let raisedOn: Date
        // When it closed, for a closed one.
        let closedAt: Date?
        // The raising entry's areas: a loose end has none of its own.
        let areas: [LifeArea]

        init(id: UUID = UUID(), status: LooseEndStatus, raisedOn: Date, closedAt: Date? = nil, areas: [LifeArea] = []) {
            self.id = id
            self.status = status
            self.raisedOn = raisedOn
            self.closedAt = closedAt
            self.areas = areas
        }
    }

    // MARK: - Floors

    // A reading needs this much journal behind it, counted over every entry with insights.
    static let minimumEntries = 20
    static let minimumDays = 21
    // An area shows with this many entries in the window, and gets a height with this many moods.
    static let areaMinimumEntries = 3
    static let areaMinimumMoods = 3
    // The headline names a height only on this much, and only a difference this large.
    static let headlineMinimumMoods = 8
    static let headlineMinimumHeight = 0.25
    // Quiet: at least this share and count in the window before, and a third of it or less now.
    static let quietMinimumShare = 0.10
    static let quietMinimumEntries = 6
    // Changed: the smallest move worth a sentence.
    static let changeMinimumShare = 0.08
    static let changeMinimumHeight = 0.30
    static let changeMinimumMoods = 5
    // Follow-through: an area needs this many threads closed in the window.
    static let followMinimumClosed = 4
    static let maxRecurring = 3
    static let maxChanges = 2

    // MARK: - Out

    struct Progress: Sendable, Equatable {
        let entries: Int
        let days: Int
        var isEnough: Bool { entries >= LifeSignals.minimumEntries && days >= LifeSignals.minimumDays }
    }

    struct AreaReading: Sendable, Equatable, Identifiable {
        let area: LifeArea
        let entries: Int
        let share: Double
        let moods: Int
        // Mean valence minus the baseline, -2 to 2; nil below `areaMinimumMoods` or with no
        // baseline, drawn on the line.
        let height: Double?

        var id: LifeArea { area }
    }

    enum Tone: Sendable, Equatable {
        case lighter, heavier
    }

    struct Headline: Sendable, Equatable {
        let areas: [LifeArea]
        let tone: Tone?
    }

    struct Recurring: Sendable, Equatable, Identifiable {
        let tag: String
        let entries: Int
        // Distinct months (a year) or weeks (three months) it came up in.
        let periods: Int
        let periodIsMonth: Bool
        // Every period start (month or week) it came up in, oldest first, for the dots under it.
        let periodStarts: [Date]

        var id: String { tag }
    }

    struct Quiet: Sendable, Equatable, Identifiable {
        let area: LifeArea
        let shareBefore: Double
        let shareNow: Double
        let lastEntry: Date?

        var id: LifeArea { area }
    }

    struct Change: Sendable, Equatable, Identifiable {
        enum Kind: Sendable, Equatable {
            case share(before: Double, now: Double)
            case tone(Tone)
        }

        let area: LifeArea
        let kind: Kind
        // How big the move is, to rank by.
        let magnitude: Double

        var id: String {
            switch kind {
            case .share: "\(area.rawValue)-share"
            case .tone: "\(area.rawValue)-tone"
            }
        }
    }

    struct FollowThrough: Sendable, Equatable, Identifiable {
        let area: LifeArea
        let closed: Int
        let resolved: Int
        let faded: Int
        let dismissed: Int
        // Median whole days from raised to done, over the resolved ones.
        let medianDaysToResolve: Int?

        var id: LifeArea { area }
        var resolvedShare: Double { closed == 0 ? 0 : Double(resolved) / Double(closed) }
        var fadedShare: Double { closed == 0 ? 0 : Double(faded) / Double(closed) }
    }

    // Two areas that close their threads differently enough to say so.
    struct Contrast: Sendable, Equatable {
        let closes: FollowThrough
        let fades: FollowThrough
    }

    struct Reading: Sendable, Equatable {
        let window: MindWindow
        let interval: DateInterval
        let entries: Int
        let baseline: Double?
        let areas: [AreaReading]
        let headline: Headline?
        let recurring: [Recurring]
        let quiet: [Quiet]
        let changes: [Change]
        let followThrough: [FollowThrough]
        let contrast: Contrast?
        let openThreads: Int
    }

    // MARK: - Reading

    static func progress(_ entries: [EntryFact]) -> Progress {
        guard let first = entries.map(\.date).min(), let last = entries.map(\.date).max() else {
            return Progress(entries: 0, days: 0)
        }
        let days = Int((last.timeIntervalSince(first) / 86_400).rounded(.down))
        return Progress(entries: entries.count, days: days)
    }

    // nil until `progress` is enough. `entries` are every non-draft entry with insights, all
    // time; `hidden` areas never appear.
    static func reading(
        entries: [EntryFact],
        threads: [ThreadFact],
        window: MindWindow,
        now: Date,
        hidden: Set<LifeArea> = [],
        calendar: Calendar = .current
    ) -> Reading? {
        guard progress(entries).isEnough, let interval = window.interval(endingAt: now) else { return nil }
        let inside = entries.filter { isInside($0.date, interval) }
        let before = window.interval(endingAt: interval.start).map { previous in entries.filter { isInside($0.date, previous) } } ?? []
        let base = baseline(entries, now: now)
        let areas = areaReadings(inside, baseline: base, hidden: hidden)
        let previousAreas = areaReadings(before, baseline: base, hidden: hidden, floor: 1)
        let quiet = quietAreas(now: areas, before: previousAreas, beforeCount: before.count, inside: inside)
        let follow = followThrough(threads, in: interval, hidden: hidden)
        return Reading(
            window: window,
            interval: interval,
            entries: inside.count,
            baseline: base,
            areas: areas,
            headline: headline(areas),
            recurring: window == .month ? [] : recurring(inside, window: window, calendar: calendar),
            quiet: quiet,
            changes: changes(now: areas, before: previousAreas, skipping: Set(quiet.map(\.area))),
            followThrough: follow,
            contrast: contrast(follow),
            openThreads: threads.filter { $0.status == .open }.count
        )
    }

    // Start-exclusive, like `MindStats`, so a window and the one before never share an entry.
    static func isInside(_ date: Date, _ interval: DateInterval) -> Bool {
        date > interval.start && date <= interval.end
    }

    // The mean valence of every entry with a mood in the year before `now`.
    static func baseline(_ entries: [EntryFact], now: Date) -> Double? {
        let year = DateInterval(start: now.addingTimeInterval(-365 * 86_400), end: now)
        let valences = entries.filter { isInside($0.date, year) }.compactMap(\.valence)
        guard !valences.isEmpty else { return nil }
        return Double(valences.reduce(0, +)) / Double(valences.count)
    }

    static func areaReadings(_ entries: [EntryFact], baseline: Double?, hidden: Set<LifeArea>, floor: Int = areaMinimumEntries) -> [AreaReading] {
        guard !entries.isEmpty else { return [] }
        var counts: [LifeArea: Int] = [:]
        var valences: [LifeArea: [Int]] = [:]
        for entry in entries {
            for area in Set(entry.areas) where !hidden.contains(area) {
                counts[area, default: 0] += 1
                if let valence = entry.valence { valences[area, default: []].append(valence) }
            }
        }
        return counts
            .filter { $0.value >= floor }
            .map { area, count in
                let moods = valences[area] ?? []
                let height: Double? = {
                    guard let baseline, moods.count >= areaMinimumMoods else { return nil }
                    return Double(moods.reduce(0, +)) / Double(moods.count) - baseline
                }()
                return AreaReading(area: area, entries: count, share: Double(count) / Double(entries.count), moods: moods.count, height: height)
            }
            .sorted { $0.entries != $1.entries ? $0.entries > $1.entries : $0.area.rawValue < $1.area.rawValue }
    }

    // The biggest area, with the next when it's nearly as big, and a tone only on enough moods.
    static func headline(_ areas: [AreaReading]) -> Headline? {
        guard let first = areas.first else { return nil }
        var named = [first.area]
        if areas.count > 1, Double(areas[1].entries) >= 0.8 * Double(first.entries) {
            named.append(areas[1].area)
        }
        var tone: Tone?
        if named.count == 1, first.moods >= headlineMinimumMoods, let height = first.height, abs(height) >= headlineMinimumHeight {
            tone = height > 0 ? .lighter : .heavier
        }
        return Headline(areas: named, tone: tone)
    }

    // Tags that came back across the window: in 3 distinct months of a year, or 4 distinct weeks
    // of three months.
    static func recurring(_ entries: [EntryFact], window: MindWindow, calendar: Calendar = .current) -> [Recurring] {
        let byMonth = window == .year
        let floor = byMonth ? 3 : 4
        var periods: [String: Set<Date>] = [:]
        var counts: [String: Int] = [:]
        for entry in entries {
            let month = calendar.dateInterval(of: .month, for: entry.date)?.start ?? entry.date
            let week = calendar.dateInterval(of: .weekOfYear, for: entry.date)?.start ?? entry.date
            for tag in Set(entry.tags) {
                periods[tag, default: []].insert(byMonth ? month : week)
                counts[tag, default: 0] += 1
            }
        }
        let found: [Recurring] = periods.compactMap { tag, seen in
            guard seen.count >= floor else { return nil }
            let starts: [Date] = seen.sorted()
            return Recurring(tag: tag, entries: counts[tag] ?? 0, periods: seen.count, periodIsMonth: byMonth, periodStarts: starts)
        }
        let ranked = found.sorted(by: recurringOrder)
        return Array(ranked.prefix(maxRecurring))
    }

    // Most periods first, then most entries, then by name so the order never shuffles.
    private static func recurringOrder(_ a: Recurring, _ b: Recurring) -> Bool {
        if a.periods != b.periods { return a.periods > b.periods }
        if a.entries != b.entries { return a.entries > b.entries }
        return a.tag < b.tag
    }

    static func quietAreas(now: [AreaReading], before: [AreaReading], beforeCount: Int, inside: [EntryFact]) -> [Quiet] {
        guard beforeCount > 0 else { return [] }
        let current = Dictionary(uniqueKeysWithValues: now.map { ($0.area, $0) })
        return before
            .filter { $0.share >= quietMinimumShare && $0.entries >= quietMinimumEntries }
            .compactMap { previous in
                let shareNow = current[previous.area]?.share ?? 0
                guard shareNow <= previous.share / 3 else { return nil }
                let last = inside.filter { $0.areas.contains(previous.area) }.map(\.date).max()
                return Quiet(area: previous.area, shareBefore: previous.share, shareNow: shareNow, lastEntry: last)
            }
            .sorted { $0.shareBefore - $0.shareNow > $1.shareBefore - $1.shareNow }
    }

    static func changes(now: [AreaReading], before: [AreaReading], skipping: Set<LifeArea>) -> [Change] {
        let previous = Dictionary(uniqueKeysWithValues: before.map { ($0.area, $0) })
        var result: [Change] = []
        for current in now where !skipping.contains(current.area) {
            let old = previous[current.area]
            let shareBefore = old?.share ?? 0
            let delta = current.share - shareBefore
            if (old?.entries ?? 0) >= 1, abs(delta) >= changeMinimumShare {
                result.append(Change(area: current.area, kind: .share(before: shareBefore, now: current.share), magnitude: abs(delta)))
            }
            if let old, let heightNow = current.height, let heightBefore = old.height,
               current.moods >= changeMinimumMoods, old.moods >= changeMinimumMoods,
               abs(heightNow - heightBefore) >= changeMinimumHeight {
                result.append(Change(area: current.area, kind: .tone(heightNow > heightBefore ? .lighter : .heavier), magnitude: abs(heightNow - heightBefore) / 2))
            }
        }
        // One sentence per area: its bigger move.
        var seen: Set<LifeArea> = []
        return result
            .sorted { $0.magnitude > $1.magnitude }
            .filter { seen.insert($0.area).inserted }
            .prefix(maxChanges)
            .map { $0 }
    }

    static func followThrough(_ threads: [ThreadFact], in interval: DateInterval, hidden: Set<LifeArea>) -> [FollowThrough] {
        var byArea: [LifeArea: [ThreadFact]] = [:]
        for thread in threads where thread.status != .open {
            guard let closed = thread.closedAt, isInside(closed, interval) else { continue }
            for area in Set(thread.areas) where !hidden.contains(area) {
                byArea[area, default: []].append(thread)
            }
        }
        return byArea
            .filter { $0.value.count >= followMinimumClosed }
            .map { area, closed in
                let resolved = closed.filter { $0.status == .resolved }
                let days = resolved.compactMap { thread in
                    thread.closedAt.map { max(0, Int(($0.timeIntervalSince(thread.raisedOn) / 86_400).rounded(.down))) }
                }
                return FollowThrough(
                    area: area,
                    closed: closed.count,
                    resolved: resolved.count,
                    faded: closed.filter { $0.status == .faded }.count,
                    dismissed: closed.filter { $0.status == .dismissed }.count,
                    medianDaysToResolve: median(days)
                )
            }
            .sorted { $0.closed != $1.closed ? $0.closed > $1.closed : $0.area.rawValue < $1.area.rawValue }
    }

    // The area that closes its threads best against the one that lets them fade most, when they're
    // 30 points apart.
    static func contrast(_ follow: [FollowThrough]) -> Contrast? {
        guard follow.count >= 2,
              let closes = follow.max(by: { $0.resolvedShare < $1.resolvedShare }),
              let fades = follow.max(by: { $0.fadedShare < $1.fadedShare }),
              closes.area != fades.area,
              closes.resolvedShare - fades.resolvedShare >= 0.3 else { return nil }
        return Contrast(closes: closes, fades: fades)
    }

    static func median(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    // MARK: - What matters

    static let maxPriorities = 3

    struct Priority: Sendable, Equatable, Identifiable {
        let area: LifeArea
        let share: Double
        // The share an area would have if the writing were spread evenly over the visible areas.
        let even: Double
        // Under half the even share: said to matter, rarely written about.
        var isGap: Bool { share < even / 2 }

        var id: LifeArea { area }
    }

    // Each area the user said matters, against where the writing actually went in the window. An
    // area with no entries at all is a share of zero, which is the gap worth saying most.
    static func priorities(_ picked: [LifeArea], reading: Reading, visibleCount: Int) -> [Priority] {
        let shares = Dictionary(uniqueKeysWithValues: reading.areas.map { ($0.area, $0.share) })
        let total = reading.areas.map(\.share).reduce(0, +)
        let even = visibleCount > 0 ? max(total, 1) / Double(visibleCount) : 0
        return picked.prefix(maxPriorities).map { Priority(area: $0, share: shares[$0] ?? 0, even: even) }
    }

    // MARK: - One area

    struct MonthMood: Sendable, Equatable, Identifiable {
        let month: Date
        let entries: Int
        // Mean valence minus the baseline; nil with no mood that month.
        let height: Double?

        var id: Date { month }
    }

    struct AreaDetail: Sendable, Equatable {
        let area: LifeArea
        let reading: AreaReading?
        // The window's months, oldest first, each with this area's entries and feeling.
        let months: [MonthMood]
        let tags: [(tag: String, count: Int)]
        let followThrough: FollowThrough?
        let entryIDs: [UUID]

        static func == (lhs: AreaDetail, rhs: AreaDetail) -> Bool {
            lhs.area == rhs.area && lhs.reading == rhs.reading && lhs.months == rhs.months
                && lhs.tags.map(\.tag) == rhs.tags.map(\.tag) && lhs.tags.map(\.count) == rhs.tags.map(\.count)
                && lhs.followThrough == rhs.followThrough && lhs.entryIDs == rhs.entryIDs
        }
    }

    static func detail(
        for area: LifeArea,
        entries: [EntryFact],
        threads: [ThreadFact],
        window: MindWindow,
        now: Date,
        calendar: Calendar = .current
    ) -> AreaDetail? {
        guard let interval = window.interval(endingAt: now) else { return nil }
        let inside = entries.filter { isInside($0.date, interval) }
        let base = baseline(entries, now: now)
        let mine = inside.filter { $0.areas.contains(area) }
        var months: [MonthMood] = []
        var cursor = calendar.dateInterval(of: .month, for: interval.start)?.start ?? interval.start
        while cursor <= interval.end {
            guard let month = calendar.dateInterval(of: .month, for: cursor) else { break }
            let those = mine.filter { $0.date >= month.start && $0.date < month.end }
            let valences = those.compactMap(\.valence)
            let height = base.flatMap { base in valences.isEmpty ? nil : Double(valences.reduce(0, +)) / Double(valences.count) - base }
            months.append(MonthMood(month: month.start, entries: those.count, height: height))
            cursor = month.end
        }
        var tagCounts: [String: Int] = [:]
        for entry in mine { for tag in Set(entry.tags) { tagCounts[tag, default: 0] += 1 } }
        let tags = tagCounts
            .filter { $0.value >= 2 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(8)
            .map { (tag: $0.key, count: $0.value) }
        let follow = followThrough(threads, in: interval, hidden: [])
        return AreaDetail(
            area: area,
            reading: areaReadings(inside, baseline: base, hidden: [], floor: 1).first { $0.area == area },
            months: months,
            tags: Array(tags),
            followThrough: follow.first { $0.area == area },
            entryIDs: mine.sorted { $0.date > $1.date }.map(\.id)
        )
    }
}
