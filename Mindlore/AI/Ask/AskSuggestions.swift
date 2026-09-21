import Foundation

// A question the empty Ask screen offers, and what it was made from, so the view can give each
// one a glyph that says what kind of question it is.
nonisolated struct AskSuggestion: Hashable, Sendable {
    enum Source: Hashable, Sendable {
        case name(EntityKind)
        case thread
        case area(LifeArea)
        case time
    }

    let text: String
    let source: Source
}

// What the empty Ask screen suggests, decided in one pure pass. Nothing here reads SwiftData;
// AskSuggestionSource drops hidden and muted names, and faded or concealed threads, into plain
// values first, the same split as TodayComposer and TodaySource.
//
// Five kinds of question so the three on screen have different shapes: the most recent name, an
// open thread, the area the last month leaned on, a question about time, and a second name. Which
// three show turns with the day and holds still within it, so opening Ask twice never reshuffles.
nonisolated enum AskSuggestions {
    static let limit = 3
    // A thread longer than this makes a question nobody would type. It is skipped, not cut short.
    static let threadCharacterLimit = 60

    struct Name: Hashable, Sendable {
        let name: String
        let kind: EntityKind
    }

    struct Area: Hashable, Sendable {
        let area: LifeArea
        // The user's name for it, since an area can be renamed.
        let name: String
    }

    struct Input: Sendable {
        // Newest first. Only the first two are used.
        var names: [Name] = []
        // Oldest first, already filtered to open threads with no hidden or muted subject.
        var threads: [String] = []
        // The area the recent entries leaned on most.
        var area: Area?
        var now: Date = .now
        var calendar: Calendar = .current
    }

    static let timeQuestions = [
        "What did I do last week?",
        "What stood out last month?",
    ]

    // Holds the screen up when the journal has almost nothing to go on.
    static let fallback = AskSuggestion(text: "What's been on my mind lately?", source: .time)

    static func suggestions(_ input: Input) -> [AskSuggestion] {
        let day = dayOrdinal(input.now, calendar: input.calendar)

        var slots: [AskSuggestion] = []
        if let first = input.names.first {
            slots.append(question(about: first))
        }
        if let thread = input.threads.first(where: { $0.count <= threadCharacterLimit }) {
            slots.append(AskSuggestion(text: "What happened with \u{201C}\(thread)\u{201D}?", source: .thread))
        }
        if let area = input.area {
            slots.append(AskSuggestion(text: "How has \(area.name) been lately?", source: .area(area.area)))
        }
        slots.append(AskSuggestion(text: timeQuestions[day % timeQuestions.count], source: .time))
        if input.names.count > 1 {
            slots.append(question(about: input.names[1]))
        }

        guard slots.count > limit else {
            return slots.count < limit && !slots.contains(fallback) ? slots + [fallback] : slots
        }
        // A window of three, starting further along each day and wrapping.
        let start = day % slots.count
        return (0..<limit).map { slots[(start + $0) % slots.count] }
    }

    // Phrased for what the name is, since "going on with" suits a person and not a place.
    static func question(about name: Name) -> AskSuggestion {
        let text = switch name.kind {
        case .person: "What's been going on with \(name.name)?"
        case .place: "What happened at \(name.name)?"
        case .organization: "What's been happening at \(name.name)?"
        case .project: "How is \(name.name) going?"
        case .event: "How did \(name.name) go?"
        case .tag, .other: "What have I written about \(name.name)?"
        }
        return AskSuggestion(text: text, source: .name(name.kind))
    }

    // Days since a fixed reference, in the user's calendar, so the turn happens at local midnight.
    static func dayOrdinal(_ date: Date, calendar: Calendar) -> Int {
        let reference = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))
        let days = calendar.dateComponents([.day], from: reference, to: calendar.startOfDay(for: date)).day ?? 0
        return max(days, 0)
    }
}
