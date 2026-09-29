import Foundation
import SwiftData

// A voluntary thumbs up or down on an Ask answer or an entry's insights: whether it was right, out
// of the way, the way Life's "That's right"/"Not quite" already works for the portrait
// (LifeWords.give). Stored and counted only for now; nothing here is read into any prompt. Like
// Life's feedback, it rides in ReflectSummary rows under a free-string periodKindRaw, so no
// CloudKit schema change is needed.
@MainActor
enum AnswerFeedback {
    enum Surface: String {
        case ask = "ask.feedback"
        case insights = "insights.feedback"
    }

    enum Verdict: String {
        case up, down
    }

    static func rows(_ surface: Surface, in context: ModelContext) -> [ReflectSummary] {
        let kind = surface.rawValue
        let descriptor = FetchDescriptor<ReflectSummary>(predicate: #Predicate { $0.periodKindRaw == kind })
        return ((try? context.fetch(descriptor)) ?? []).filter { !$0.isDeleted }
    }

    static func verdict(on key: String, surface: Surface, in context: ModelContext) -> Verdict? {
        rows(surface, in: context).flatMap(\.items).last { $0.title == key }.flatMap { Verdict(rawValue: $0.prompt) }
    }

    // Tapping the same verdict again clears it; tapping the other one replaces it. One row holds
    // every verdict for a surface, the same shape as Life's feedback row.
    @discardableResult
    static func toggle(_ verdict: Verdict, on key: String, surface: Surface, in context: ModelContext, diagnostics: DiagnosticsLog = .shared) -> Verdict? {
        let existing = rows(surface, in: context)
        let current = existing.flatMap(\.items).last { $0.title == key }.flatMap { Verdict(rawValue: $0.prompt) }
        var items = existing.flatMap(\.items).filter { $0.title != key }
        let next: Verdict? = current == verdict ? nil : verdict
        if let next {
            items.append(ReflectQueueItem(id: UUID().uuidString, source: .generated, title: key, body: "", prompt: next.rawValue))
        }
        existing.forEach(context.delete)
        let row = ReflectSummary(kind: .month, periodStart: .distantPast, generatedAt: .now, items: items)
        row.periodKindRaw = surface.rawValue
        context.insert(row)
        try? context.saveStampingEntries()
        diagnostics.record(surface.rawValue, ["verdict": .string(next?.rawValue ?? "cleared")])
        return next
    }
}
