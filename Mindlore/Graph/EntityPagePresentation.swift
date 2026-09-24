import Foundation

// A page on the navigation stack. `follow` shows where a merged entity went, which is what the
// user was looking at; a row listing a merged entity opts out so it shows that entity itself.
nonisolated struct EntityRoute: Hashable, Sendable {
    let id: UUID
    var follow = true
}

// One mention in one entry, by what it says rather than by link id: regenerating insights
// replaces links, and a sheet holding an old id would act on nothing.
nonisolated struct MentionRef: Hashable, Identifiable, Sendable {
    var id: Self { self }
    let entryID: UUID
    let surface: String
    let kind: EntityKind
}

// What an entity page shows, decided from plain values so it can be tested without a view.
nonisolated enum EntityPagePresentation {
    enum Resolution: Equatable {
        case show(UUID)
        case gone
    }

    // `mergedIntoID` is always one hop from a live root, so one step is enough.
    static func resolve(_ route: EntityRoute, exists: Bool, mergedIntoID: UUID?) -> Resolution {
        guard exists else { return .gone }
        if route.follow, let winner = mergedIntoID { return .show(winner) }
        return .show(route.id)
    }

    // A fresh, single-mention, never-touched name is worth double-checking: dictation is the
    // likeliest source of a wrong spelling, and nobody has confirmed this one is right yet.
    // Restricted to the kinds bio auto-drafting already limits itself to (5a): tags rarely
    // appear word for word, so a misspelling there isn't the scenario this is for.
    static func showsSpellingPrompt(confirmedByUser: Bool, linkCount: Int, kind: EntityKind) -> Bool {
        !confirmedByUser && linkCount <= 1 && EntityBioDrafter.automaticKinds.contains(kind)
    }

    // After a merge made from a page, the page's route names the winner itself, so undoing
    // that merge later doesn't flip the page back to the loser. Only the top route that shows
    // the loser is replaced.
    static func replacing(_ loserID: UUID, with winnerID: UUID, in path: [EntityRoute]) -> [EntityRoute] {
        guard let index = path.lastIndex(where: { $0.id == loserID }) else { return path }
        var path = path
        path[index] = EntityRoute(id: winnerID)
        return path
    }

    // MARK: - Header

    static func mentionSummary(count: Int) -> String {
        switch count {
        case 0: "Not mentioned in any entry"
        case 1: "Mentioned in 1 entry"
        default: "Mentioned in \(count) entries"
        }
    }

    static func dateRange(first: Date?, last: Date?) -> String? {
        guard let first, let last else { return nil }
        let firstText = first.formatted(date: .abbreviated, time: .omitted)
        let lastText = last.formatted(date: .abbreviated, time: .omitted)
        return firstText == lastText ? firstText : "\(firstText) to \(lastText)"
    }

    // MARK: - Entries

    struct EntryInput: Equatable {
        let entryID: UUID
        let date: Date
        let title: String
        let text: String
        let surfaces: [String]
        // The mention the resolver linked by guessing, which the row offers to correct.
        let guessed: MentionRef?
    }

    struct EntryRow: Equatable, Identifiable {
        let id: UUID
        let date: Date
        let heading: String
        // Where the entry names them, if it still does.
        let sentence: String?
        let guessed: MentionRef?
    }

    static let headingWords = 8

    static func entryRows(_ inputs: [EntryInput]) -> [EntryRow] {
        inputs.sorted { $0.date > $1.date }.map { input in
            EntryRow(
                id: input.entryID,
                date: input.date,
                heading: heading(title: input.title, text: input.text),
                sentence: BioExcerpts.sentences(in: input.text, naming: input.surfaces).first,
                guessed: input.guessed
            )
        }
    }

    static func heading(title: String, text: String) -> String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        guard !words.isEmpty else { return "Untitled entry" }
        let opening = words.prefix(headingWords).joined(separator: " ")
        return words.count > headingWords ? opening + "…" : opening
    }

    // MARK: - Bio

    enum BioState: Equatable {
        case userWritten(String)
        case drafted(String, disclosure: String, canRedraft: Bool)
        case drafting
        case failed(String, canRetry: Bool)
        // The model or the entries had too little to say.
        case notEnough(canDraft: Bool)
        case empty(canDraft: Bool)
    }

    struct BioInput: Equatable {
        var bio: String?
        var wasGenerated = false
        var editedByUser = false
        var draftedAt: Date?
        var sourceEntries = 0
        var modelUsed: String?
        var drafting = false
        var failure: AIJobFailure?
        var withoutExcerpts = false
        var textUsable = false
    }

    static func bioState(_ input: BioInput) -> BioState {
        if input.drafting { return .drafting }
        if let bio = input.bio {
            guard input.wasGenerated, !input.editedByUser else { return .userWritten(bio) }
            return .drafted(bio, disclosure: disclosure(entries: input.sourceEntries, model: input.modelUsed), canRedraft: input.textUsable)
        }
        if let failure = input.failure {
            return .failed(BioDraftPresentation.message(for: failure), canRetry: input.textUsable)
        }
        let triedAndFoundLittle = input.draftedAt != nil || input.withoutExcerpts
        if triedAndFoundLittle && !input.editedByUser {
            return .notEnough(canDraft: input.textUsable)
        }
        return .empty(canDraft: input.textUsable)
    }

    static func disclosure(entries: Int, model: String?) -> String {
        let sent = entries == 1 ? "1 entry sent to OpenAI" : "\(entries) entries sent to OpenAI"
        let model = model?.trimmingCharacters(in: .whitespaces) ?? ""
        return (["Drafted by AI", sent] + (model.isEmpty ? [] : [model])).joined(separator: " · ")
    }

    // MARK: - Mentioned with

    struct CoOccurrenceRow: Equatable, Identifiable {
        let id: UUID
        let name: String
        let kind: EntityKind
        // Entries the two share, the number printed beside the name.
        var entries = 0
    }

    // GraphServices.mentionedWith already orders by shared entries and applies the limit; this
    // keeps the count, which the page prints, and drops the weight, which is only ordering.
    static func coOccurrenceRows(_ inputs: [GraphServices.CoOccurrence]) -> [CoOccurrenceRow] {
        inputs.map { CoOccurrenceRow(id: $0.id, name: $0.name, kind: $0.kind, entries: $0.entries) }
    }

    // Names and themes apart, in the order they came: tags share the most entries with anyone,
    // so together they crowded the people out, the same split the peek card makes.
    static func partners(_ rows: [CoOccurrenceRow]) -> (names: [CoOccurrenceRow], themes: [CoOccurrenceRow]) {
        (rows.filter { $0.kind != .tag }, rows.filter { $0.kind == .tag })
    }

    // MARK: - Merged in

    struct MergedInput: Equatable {
        let id: UUID
        let name: String
        let mergedIntoID: UUID?
        let mergedAt: Date?
    }

    static func mergedIn(_ inputs: [MergedInput], into id: UUID) -> [MergedInput] {
        inputs.filter { $0.mergedIntoID == id }
            .sorted { ($0.mergedAt ?? .distantPast) > ($1.mergedAt ?? .distantPast) }
    }
}

// Wording for a bio that could not be drafted. The insights and title wording talks about
// entries and titles, which would be wrong here.
nonisolated enum BioDraftPresentation {
    static func message(for failure: AIJobFailure) -> String {
        if failure.raw == "settings.aiOff" { return "Turn on AI in Settings to draft a description." }
        switch failure.aiError {
        case .missingKey, .invalidKey, .permissionDenied:
            return "Add a working OpenAI key in AI settings to draft a description."
        case .offline:
            return "You're offline. Try again when you're connected."
        case .rateLimited:
            return "OpenAI is busy right now. Try again in a moment."
        case .quotaExceeded:
            return "Your OpenAI account is out of credit."
        default:
            return "Couldn't draft a description. Try again."
        }
    }
}

nonisolated extension EntityPagePresentation {
    // MARK: - Loose ends

    struct LooseEndItem: Equatable, Identifiable {
        let id: UUID
        let entityIDs: [UUID]
        let isOpen: Bool
        let lastMentionedAt: Date
        let statusChangedAt: Date?
    }

    // The loose ends about one entity, through merges: open ones by latest mention, then the
    // rest (settled, faded, let go) by when that happened.
    static func looseEnds(_ items: [LooseEndItem], about entityID: UUID, root: (UUID) -> UUID) -> (open: [UUID], earlier: [UUID]) {
        let about = items.filter { $0.entityIDs.contains { root($0) == entityID } }
        let open = about.filter(\.isOpen).sorted { $0.lastMentionedAt > $1.lastMentionedAt }
        let earlier = about.filter { !$0.isOpen }.sorted {
            ($0.statusChangedAt ?? $0.lastMentionedAt) > ($1.statusChangedAt ?? $1.lastMentionedAt)
        }
        return (open.map(\.id), earlier.map(\.id))
    }
}

nonisolated extension EntityPagePresentation {
    // MARK: - Presence

    // How the entity has been present across the whole journal: one bar per month from the
    // journal's first month to this one, and the words under them.
    struct Presence: Equatable {
        // Oldest month first.
        let months: [Int]
        let firstMonth: Date
        let total: Int
        let first: Date
        let last: Date
        // The month with the most entries, the latest when two tie. Nil with one month of bars.
        let busiest: Date?
    }

    static func presence(entryDates: [Date], journalStart: Date?, now: Date, calendar: Calendar = .current) -> Presence? {
        let dates = entryDates.filter { $0 <= now }
        guard let first = dates.min(), let last = dates.max() else { return nil }
        let start = min(journalStart ?? first, first)
        guard let firstMonth = calendar.dateInterval(of: .month, for: start)?.start,
              let thisMonth = calendar.dateInterval(of: .month, for: now)?.start
        else { return nil }
        let count = (calendar.dateComponents([.month], from: firstMonth, to: thisMonth).month ?? 0) + 1
        var months = [Int](repeating: 0, count: max(1, count))
        for date in dates {
            guard let month = calendar.dateInterval(of: .month, for: date)?.start else { continue }
            let index = calendar.dateComponents([.month], from: firstMonth, to: month).month ?? 0
            if months.indices.contains(index) { months[index] += 1 }
        }
        var busiest: Date?
        if months.count > 1, let top = months.max(), top > 0, let index = months.lastIndex(of: top) {
            busiest = calendar.date(byAdding: .month, value: index, to: firstMonth)
        }
        return Presence(months: months, firstMonth: firstMonth, total: dates.count, first: first, last: last, busiest: busiest)
    }

    // "87 entries · Oct 2025 to Sep 2026 · busiest in November".
    static func presenceWords(_ presence: Presence, calendar: Calendar = .current) -> String {
        let month = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated).year()
        let firstText = presence.first.formatted(month)
        let lastText = presence.last.formatted(month)
        var parts = [presence.total == 1 ? "1 entry" : "\(presence.total) entries"]
        parts.append(firstText == lastText ? firstText : "\(firstText) to \(lastText)")
        if let busiest = presence.busiest {
            let sameYear = calendar.component(.year, from: presence.firstMonth) == calendar.component(.year, from: presence.last)
            let style = sameYear ? Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).month(.wide) : Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).month(.wide).year()
            parts.append("busiest in \(busiest.formatted(style))")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Feeling

    struct FeelingRow: Equatable, Identifiable {
        var id: MoodCategory { mood }
        let mood: MoodCategory
        let count: Int
        // Of every entry in the journal with a mood, how many carry this one.
        let usualCount: Int
    }

    struct Feeling: Equatable {
        // Entries about this name that carry a mood.
        let total: Int
        let usualTotal: Int
        let rows: [FeelingRow]
    }

    static let feelingMinimum = 5
    static let feelingRows = 3

    // The moods of this name's entries beside the whole journal's, as counts. Nothing under five
    // entries with a mood: three entries make a pattern out of nothing. The house rule holds:
    // this says what the entries carried, never whether that is good.
    static func feeling(moods: [MoodCategory?], usual: [MoodCategory: Int]) -> Feeling? {
        let present = moods.compactMap { $0 }
        guard present.count >= feelingMinimum else { return nil }
        var counts: [MoodCategory: Int] = [:]
        for mood in present { counts[mood, default: 0] += 1 }
        let rows = counts
            .sorted { lhs, rhs in
                lhs.value != rhs.value ? lhs.value > rhs.value
                    : (MoodCategory.allCases.firstIndex(of: lhs.key) ?? 0) < (MoodCategory.allCases.firstIndex(of: rhs.key) ?? 0)
            }
            .prefix(feelingRows)
            .map { FeelingRow(mood: $0.key, count: $0.value, usualCount: usual[$0.key] ?? 0) }
        return Feeling(total: present.count, usualTotal: usual.values.reduce(0, +), rows: rows)
    }

    // "Anxious in 4 of 5 · usually 1 in 8".
    static func feelingWords(_ row: FeelingRow, total: Int, usualTotal: Int) -> String {
        let here = "\(row.mood.name) in \(row.count) of \(total)"
        guard usualTotal > 0, row.usualCount > 0 else { return "\(here) · rarely otherwise" }
        let oneIn = max(1, Int((Double(usualTotal) / Double(row.usualCount)).rounded()))
        return oneIn == 1 ? "\(here) · usually most entries" : "\(here) · usually 1 in \(oneIn)"
    }

    // MARK: - Area

    // The life area this name leans toward across all its entries, the rule the map uses.
    static func primaryArea(_ entries: [(id: UUID, date: Date, areas: [LifeArea])], entityID: UUID) -> LifeArea? {
        let links = entries.map { EntityGraph.LinkInput(entryID: $0.id, entityID: entityID, entryDate: $0.date) }
        let values = Dictionary(entries.map { ($0.id, EntityTally.Entry(values: $0.areas, date: $0.date)) }, uniquingKeysWith: { first, _ in first })
        return EntityTally.primary(links: links, values: values)[entityID]
    }
}
