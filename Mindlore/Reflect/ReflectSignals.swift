import Foundation

// The one reused signal a week's queue always carries, asked about that week's end rather than
// now: a loose end still open then. Pure, the same split TodayComposer keeps from TodaySource, so
// a stale cache of "still open" can never be wrong once a loose end resolves; it's computed fresh
// on every read, never stored in a ReflectSummary. Surfaces at most one card, exactly like
// Today's own single "still open" card: this is a curated queue, not a full listing of everything
// that qualifies. "Been quiet" (a name gone quiet as of a week) was cut (owner, 2026-09-21): it
// added a card nobody wanted read against every week.
nonisolated enum ReflectSignals {
    static func compose(looseEnds: [LooseEndFacts], weekEnd: Date) -> [ReflectQueueItem] {
        stillOpen(looseEnds, asOf: weekEnd).map { end in
            ReflectQueueItem(
                id: "looseEnd:\(end.id.uuidString)",
                source: .looseEnd(end.id),
                title: "Still open",
                body: end.text,
                prompt: end.text
            )
        }
    }

    // The one oldest still-open thread, exactly the shape TodayComposer.stillOpen picks for "right
    // now" (`.min`, not every open loose end): a journal that never resolves anything would
    // otherwise flood every week with the same growing pile.
    static func stillOpen(_ looseEnds: [LooseEndFacts], asOf date: Date) -> [LooseEndFacts] {
        let candidates = looseEnds
            .filter { $0.status == .open && $0.sourceEntryDate <= date }
            .sorted { ($0.sourceEntryDate, $0.id.uuidString) < ($1.sourceEntryDate, $1.id.uuidString) }
        return Array(candidates.prefix(1))
    }
}
