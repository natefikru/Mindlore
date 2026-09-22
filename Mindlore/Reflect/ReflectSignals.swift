import Foundation

// The two reused signals a week's queue always carries, asked about that week's end rather than
// now: a loose end still open then, and a name gone quiet as of then. Pure, the same split
// TodayComposer keeps from TodaySource, so a stale cache of "still open" can never be wrong once a
// loose end resolves; these are computed fresh on every read, never stored in a ReflectSummary.
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

    // Open now, and it already existed by the week's end: a loose end opened after a past week
    // closed can't have been open "at" that week.
    static func stillOpen(_ looseEnds: [LooseEndFacts], asOf date: Date) -> [LooseEndFacts] {
        looseEnds
            .filter { $0.status == .open && $0.sourceEntryDate <= date }
            .sorted { ($0.sourceEntryDate, $0.id.uuidString) < ($1.sourceEntryDate, $1.id.uuidString) }
    }

    // The same threshold and shape as TodayComposer.beenAWhile, measured from the week's end
    // instead of now: an entity last linked well before that week closed, not one that just went
    // quiet since.
    static func quiet(_ entities: [EntityFacts], asOf date: Date) -> [EntityFacts] {
        let cutoff = date.addingTimeInterval(-TodayComposer.staleAfter)
        return entities
            .filter { entity in
                guard let last = entity.lastLinkedAt else { return false }
                return entity.linkCount > 0 && entity.kind.isAName && last < cutoff
            }
            .sorted { first, second in
                let firstSeen = first.lastLinkedAt ?? .distantPast
                let secondSeen = second.lastLinkedAt ?? .distantPast
                if firstSeen != secondSeen { return firstSeen < secondSeen }
                return first.id.uuidString < second.id.uuidString
            }
    }
}
