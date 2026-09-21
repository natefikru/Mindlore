import Foundation
import SwiftData

// The half of Reflect that touches the store. Fetches, builds `ReflectAggregator` facts, and hands
// off to the pure computation, the same split `TodaySource` keeps from `TodayComposer`.
@MainActor
enum ReflectSource {
    static func period(_ interval: DateInterval, in context: ModelContext) -> ReflectAggregator.Period {
        ReflectAggregator.aggregate(
            facts: entryFacts(in: interval, context: context),
            looseEnds: looseEndFacts(in: context),
            in: interval
        )
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
    // to place it, not just ones that started here.
    private static func looseEndFacts(in context: ModelContext) -> [ReflectAggregator.LooseEndFact] {
        let looseEnds = (try? context.fetch(FetchDescriptor<LooseEnd>())) ?? []
        return looseEnds.map { looseEnd in
            ReflectAggregator.LooseEndFact(
                openedAt: looseEnd.sourceEntryDate,
                resolvedAt: looseEnd.status == .resolved ? looseEnd.statusChangedAt : nil
            )
        }
    }
}
