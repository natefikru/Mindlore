import Foundation
import SwiftData

// The half of Reflect that touches the store. Fetches, builds `ReflectAggregator` facts, and hands
// off to the pure computation, the same split `TodaySource` keeps from `TodayComposer`.
@MainActor
enum ReflectSource {
    static func period(_ interval: DateInterval, in context: ModelContext) -> ReflectAggregator.Period {
        aggregate(interval, looseEnds: looseEndFacts(in: context), context: context)
    }

    // MARK: - Feed bounds

    static func earliestEntryDate(in context: ModelContext) -> Date? {
        var descriptor = FetchDescriptor<Entry>(sortBy: [SortDescriptor(\Entry.entryDate, order: .forward)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.entryDate
    }

    static func hasEntries(in interval: DateInterval, context: ModelContext) -> Bool {
        let start = interval.start
        let end = interval.end
        let count = (try? context.fetchCount(FetchDescriptor<Entry>(predicate: #Predicate { $0.entryDate >= start && $0.entryDate < end }))) ?? 0
        return count > 0
    }

    // MARK: - Tiered fidelity

    // A week's own entries, sanitized-eligible and in order. Never a digest: a week is small
    // enough that full text is cheap.
    static func weekEntries(in interval: DateInterval, context: ModelContext) -> [ReflectFidelity.WeekEntry] {
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.entryDate >= start && $0.entryDate < end })
        let entries = ((try? context.fetch(descriptor)) ?? [])
            .filter { !$0.isDeleted && InsightsCoordinator.canRunAI(on: $0) }
        return entries
            .sorted { $0.entryDate < $1.entryDate }
            .map { ReflectFidelity.WeekEntry(id: $0.id, date: $0.entryDate, title: $0.title, text: $0.text) }
    }

    // The weeks whose start falls inside a month interval, for both the fold-out UI and the
    // month's own prompt.
    static func weeksStarting(in monthInterval: DateInterval, calendar: Calendar = .current) -> [DateInterval] {
        var weeks: [DateInterval] = []
        var seen: Set<Date> = []
        var cursor = monthInterval.start
        while cursor < monthInterval.end {
            if let week = calendar.dateInterval(of: .weekOfYear, for: cursor),
               week.start >= monthInterval.start, week.start < monthInterval.end,
               seen.insert(week.start).inserted {
                weeks.append(week)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return weeks.sorted { $0.start < $1.start }
    }

    // A month's prompt: every week inside it that already has a cached summary contributes its
    // items free; every other eligible entry in the month gets a digest line. Never a whole
    // month of raw entry text. The entry count is the month's own "anything here at all" check,
    // separate from whether any week was individually visited.
    static func monthPrompt(interval: DateInterval, characterLimit: Int? = nil, calendar: Calendar = .current, context: ModelContext) -> (prompt: String, entryCount: Int) {
        var cachedItems: [[ReflectQueueItem]] = []
        var covered: [DateInterval] = []
        for week in weeksStarting(in: interval, calendar: calendar) {
            guard let summary = ReflectSummaryStore.summary(kind: .week, periodStart: week.start, in: context) else { continue }
            cachedItems.append(summary.items)
            covered.append(week)
        }

        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.entryDate >= start && $0.entryDate < end })
        let monthEntries = ((try? context.fetch(descriptor)) ?? [])
            .filter { !$0.isDeleted && InsightsCoordinator.canRunAI(on: $0) }
        let uncovered = monthEntries
            .filter { entry in !covered.contains { $0.start <= entry.entryDate && entry.entryDate < $0.end } }
            .sorted { $0.entryDate < $1.entryDate }
        let digestLines = uncovered.enumerated().map { index, entry in
            AskDigests.line(handle: "D\(index + 1)", date: entry.entryDate, title: entry.title, text: entry.text)
        }
        return (ReflectFidelity.monthPrompt(cachedWeekItems: cachedItems, digestLines: digestLines, characterLimit: characterLimit), monthEntries.count)
    }

    private static func aggregate(
        _ interval: DateInterval,
        looseEnds: [ReflectAggregator.LooseEndFact],
        context: ModelContext
    ) -> ReflectAggregator.Period {
        ReflectAggregator.aggregate(facts: entryFacts(in: interval, context: context), looseEnds: looseEnds, in: interval)
    }

    private static func entryFacts(in interval: DateInterval, context: ModelContext) -> [ReflectAggregator.EntryFact] {
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<Entry>(
            predicate: #Predicate { !$0.isDraft && $0.entryDate >= start && $0.entryDate < end }
        )
        let entries = (try? context.fetch(descriptor)) ?? []
        return entries.map { entry in
            ReflectAggregator.EntryFact(
                date: entry.entryDate,
                mood: entry.insights?.primaryMood?.category,
                areas: entry.insights?.areas ?? [],
                tags: entry.insights?.tags ?? []
            )
        }
    }

    // No date predicate: loose ends are few and concrete by design (tasks/todo.md), and one opened
    // long before this period can still close inside it, so the interval has to see every loose end
    // to place it, not just ones that started here. `LooseEnd.all(in:)`, not a raw fetch, so a
    // loose end mid-deletion (autosave is off, so a delete can sit uncommitted) is excluded the
    // same way every other LooseEnd read in the app excludes it.
    private static func looseEndFacts(in context: ModelContext) -> [ReflectAggregator.LooseEndFact] {
        LooseEnd.all(in: context).map { looseEnd in
            ReflectAggregator.LooseEndFact(
                openedAt: looseEnd.sourceEntryDate,
                resolvedAt: looseEnd.status == .resolved ? looseEnd.statusChangedAt : nil
            )
        }
    }
}
