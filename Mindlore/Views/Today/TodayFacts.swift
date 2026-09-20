import Foundation

// What Today is composed from. Plain values only, the way EntityGraph takes LinkInput: the caller
// has already walked mergedIntoID, dropped hidden and muted entities, and filtered future-dated
// entries, so nothing here has to know SwiftData exists.

nonisolated struct EntryFacts: Equatable, Sendable, Identifiable {
    let id: UUID
    let entryDate: Date
    let entryDateIsDayOnly: Bool
    let title: String
    let summary: String?
    let areas: [LifeArea]

    init(
        id: UUID,
        entryDate: Date,
        entryDateIsDayOnly: Bool = false,
        title: String = "",
        summary: String? = nil,
        areas: [LifeArea] = []
    ) {
        self.id = id
        self.entryDate = entryDate
        self.entryDateIsDayOnly = entryDateIsDayOnly
        self.title = title
        self.summary = summary
        self.areas = areas
    }
}

nonisolated struct LooseEndFacts: Equatable, Sendable, Identifiable {
    let id: UUID
    let text: String
    let status: LooseEndStatus
    let sourceEntryDate: Date
    let dueDate: Date?
    let resolvedByEntryID: UUID?

    init(
        id: UUID,
        text: String,
        status: LooseEndStatus = .open,
        sourceEntryDate: Date,
        dueDate: Date? = nil,
        resolvedByEntryID: UUID? = nil
    ) {
        self.id = id
        self.text = text
        self.status = status
        self.sourceEntryDate = sourceEntryDate
        self.dueDate = dueDate
        self.resolvedByEntryID = resolvedByEntryID
    }
}

nonisolated struct EntityFacts: Equatable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let kind: EntityKind
    let linkCount: Int
    let lastLinkedAt: Date?

    init(id: UUID, name: String, kind: EntityKind = .person, linkCount: Int = 0, lastLinkedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.linkCount = linkCount
        self.lastLinkedAt = lastLinkedAt
    }
}

nonisolated struct TodayInput: Sendable {
    var entries: [EntryFacts]
    var looseEnds: [LooseEndFacts]
    var entities: [EntityFacts]
    var now: Date
    var calendar: Calendar
    var dismissed: Set<String>
    var resurfacingEnabled: Bool
    var name: String

    init(
        entries: [EntryFacts] = [],
        looseEnds: [LooseEndFacts] = [],
        entities: [EntityFacts] = [],
        now: Date,
        calendar: Calendar = .current,
        dismissed: Set<String> = [],
        resurfacingEnabled: Bool = true,
        name: String = ""
    ) {
        self.entries = entries
        self.looseEnds = looseEnds
        self.entities = entities
        self.now = now
        self.calendar = calendar
        self.dismissed = dismissed
        self.resurfacingEnabled = resurfacingEnabled
        self.name = name
    }
}

// How long ago an on-this-day entry was, in the only spans Today looks for.
nonisolated enum TodaySpan: Equatable, Sendable {
    case yearsAgo(Int)
    case monthAgo
    case sixMonthsAgo
}

// The kind alone, for diagnostics: a fixed string that can never carry a name or a quote.
nonisolated enum TodayCardKind: String, Sendable {
    case closed, dueToday, onThisDay, stillOpen, beenAWhile, latestSummary
}

nonisolated enum TodayCard: Equatable, Sendable, Identifiable {
    case closed(LooseEndFacts)
    case dueToday(LooseEndFacts)
    case onThisDay(EntryFacts, TodaySpan)
    case stillOpen(LooseEndFacts)
    case beenAWhile(EntityFacts)
    case latestSummary(EntryFacts)

    var kind: TodayCardKind {
        switch self {
        case .closed: .closed
        case .dueToday: .dueToday
        case .onThisDay: .onThisDay
        case .stillOpen: .stillOpen
        case .beenAWhile: .beenAWhile
        case .latestSummary: .latestSummary
        }
    }

    // The dismissal key, and the view's identity. Built from ids, never from a name or a quote,
    // so the stored "not today" value says nothing about the journal.
    var id: String {
        switch self {
        case .closed(let end), .dueToday(let end), .stillOpen(let end):
            "\(kind.rawValue):\(end.id.uuidString)"
        case .onThisDay(let entry, _), .latestSummary(let entry):
            "\(kind.rawValue):\(entry.id.uuidString)"
        case .beenAWhile(let entity):
            "\(kind.rawValue):\(entity.id.uuidString)"
        }
    }
}

nonisolated struct WeekDay: Equatable, Sendable, Identifiable {
    let date: Date
    let hasEntry: Bool
    let tint: LifeArea?

    var id: Date { date }
}

nonisolated struct Today: Equatable, Sendable {
    var greeting: String = ""
    var week: [WeekDay] = []
    var cards: [TodayCard] = []

    var isEmpty: Bool { week.isEmpty && cards.isEmpty }
}
