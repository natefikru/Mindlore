import Foundation
import SwiftData

// Experiments Life offered and what became of them: one `ReflectSummary` row each under
// `life.experiment` (no model change), dated the day it was picked or turned down. Accepting one
// makes a loose end with no entry behind it, due at the end of the week, so Today shows it, the
// recorder can ask about it, a later entry can settle it, and it fades like any other if left.
@MainActor
enum LifeExperiments {
    static let kind = "life.experiment"

    enum State: String {
        case trying, declined
    }

    struct Experiment: Identifiable, Equatable {
        let id: UUID
        let subject: LifeSignals.Suggestion.Subject
        let state: State
        let since: Date
        let looseEndID: UUID?
    }

    nonisolated static func encode(_ subject: LifeSignals.Suggestion.Subject) -> String {
        switch subject {
        case .tag(let tag): "tag:\(tag)"
        case .area(let area): "area:\(area.rawValue)"
        }
    }

    nonisolated static func decode(_ raw: String) -> LifeSignals.Suggestion.Subject? {
        if raw.hasPrefix("tag:") { return .tag(String(raw.dropFirst(4))) }
        if raw.hasPrefix("area:") { return LifeArea(rawValue: String(raw.dropFirst(5))).map { .area($0) } }
        return nil
    }

    static func all(in context: ModelContext) -> [Experiment] {
        LifeWords.rows(kind, in: context).compactMap { row in
            guard let item = row.items.first, let subject = decode(item.title), let state = State(rawValue: item.body) else { return nil }
            return Experiment(id: row.id, subject: subject, state: state, since: row.periodStart, looseEndID: UUID(uuidString: item.id))
        }
    }

    // Everything already offered, so the same thing isn't offered twice.
    static func offered(in context: ModelContext) -> Set<LifeSignals.Suggestion.Subject> {
        Set(all(in: context).map(\.subject))
    }

    @discardableResult
    static func accept(_ suggestion: LifeSignals.Suggestion, threadText: String, now: Date = .now, calendar: Calendar = .current, in context: ModelContext) -> LooseEnd {
        let due = calendar.dateInterval(of: .weekOfYear, for: now).map { $0.end.addingTimeInterval(-1) } ?? now.addingTimeInterval(6 * 86_400)
        let thread = LooseEnd(text: threadText, sourceEntryID: UUID(), sourceEntryDate: now, dueDate: due)
        // No entry raised it: Life did, at the author's yes.
        thread.sourceEntryID = nil
        context.insert(thread)
        insert(suggestion.subject, state: .trying, looseEndID: thread.id, now: now, in: context)
        DiagnosticsLog.shared.record("life.experiment", ["accepted": .bool(true), "subject": .string(suggestion.subject.isTag ? "tag" : "area")])
        return thread
    }

    static func decline(_ subject: LifeSignals.Suggestion.Subject, now: Date = .now, in context: ModelContext) {
        insert(subject, state: .declined, looseEndID: nil, now: now, in: context)
        DiagnosticsLog.shared.record("life.experiment", ["accepted": .bool(false), "subject": .string(subject.isTag ? "tag" : "area")])
    }

    private static func insert(_ subject: LifeSignals.Suggestion.Subject, state: State, looseEndID: UUID?, now: Date, in context: ModelContext) {
        let item = ReflectQueueItem(id: looseEndID?.uuidString ?? UUID().uuidString, source: .generated, title: encode(subject), body: state.rawValue, prompt: "")
        let row = ReflectSummary(kind: .month, periodStart: now, generatedAt: now, items: [item])
        row.periodKindRaw = kind
        context.insert(row)
        try? context.saveStampingEntries()
    }
}

extension LifeSignals.Suggestion.Subject {
    nonisolated var isTag: Bool {
        if case .tag = self { return true }
        return false
    }
}
