import Foundation

// The two reused signals a week's queue always carries, asked about that week's end rather than
// now: a loose end still open then, and a name gone quiet as of then. Pure, the same split
// TodayComposer keeps from TodaySource, so a stale cache of "still open" can never be wrong once a
// loose end resolves; these are computed fresh on every read, never stored in a ReflectSummary.
// Each kind surfaces at most one card, exactly like Today's own single "still open" and "been
// awhile" cards: this is a curated queue, not a full listing of everything that qualifies.
nonisolated enum ReflectSignals {
    static func compose(looseEnds: [LooseEndFacts], entities: [EntityFacts], weekEnd: Date) -> [ReflectQueueItem] {
        stillOpen(looseEnds, asOf: weekEnd).map { end in
            ReflectQueueItem(
                id: "looseEnd:\(end.id.uuidString)",
                source: .looseEnd(end.id),
                title: "Still open",
                body: end.text,
                prompt: end.text
            )
        } + quiet(entities, asOf: weekEnd).map { entity in
            ReflectQueueItem(
                id: "quietName:\(entity.id.uuidString)",
                source: .quietName(entity.id),
                title: "Been quiet",
                body: "Haven't mentioned \(entity.name) in a while.",
                prompt: "What's going on with \(entity.name)?"
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

    // The one best quiet name, exactly the shape and ranking TodayComposer.beenAWhile picks for
    // "right now" (linkCount first, so the person who matters most wins ties, then staleness),
    // measured from the week's end instead of now. Returning every entity that qualifies, rather
    // than the one most worth surfacing, is what used to flood a week with dozens of cards: most
    // of a journal's cast goes 30 days unmentioned in any given week.
    static func quiet(_ entities: [EntityFacts], asOf date: Date) -> [EntityFacts] {
        let cutoff = date.addingTimeInterval(-TodayComposer.staleAfter)
        let candidates = entities
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
        return Array(candidates.prefix(1))
    }
}
