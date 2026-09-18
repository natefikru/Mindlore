import Foundation

// What to send, decided before a single character of entry text is read.
//
// The old builder let the budget define the list: it appended matching entries in score order until
// 24,000 characters ran out, which is how one common word came to fill a prompt with whatever
// mentioned it. Here the ranked list defines the list and the budget only trims it, and the budget
// is divided into named slices so a rollup can never eat the room the entries needed.
//
// Nothing in here reads text. The index knows what rendering each entry would cost, which is what
// lets the line under the field say what asking costs without reading the journal.
nonisolated enum AskRetrieval {
    // A second brake beside the budget. Fifteen entries is more than any answer needs, and it stops
    // a long tail of weak matches arriving just because there was room.
    static let maxRankedEntriesOpenAI = 15
    static let maxRankedEntriesOnDevice = 5

    // Absolute, per provider, not shares of the budget. On device the whole budget lands near 3,300
    // characters, where a 20% slice is 660 and a single entry block can be 2,050.
    static let aboutBudgetOpenAI = 3_600
    static let rollupBudgetOpenAI = 6_000
    static let continuityBudgetOpenAI = 4_800
    static let aboutBudgetOnDevice = 800

    // What a counts-only rollup line costs: "March 2026: 31 entries, 2 to 30 March".
    static let rollupCharactersPerMonth = 64
    static let maxRollupMonthsOpenAI = 24
    // An entry has to be this close to the best match to count as matching at all. Counting every
    // non-zero score would make the number meaningless: a journal where most entries carry the same
    // life area matches most of itself on "how was work", and "12 of 3,000" teaches everyone to
    // ignore the line.
    static let matchRelevanceFloor = 0.25
    // A matched set this much larger than what fits is an aggregate question whatever its wording.
    static let aggregateSizeFactor = 3

    nonisolated struct Slices: Sendable, Equatable {
        var about = 0
        var rollups = 0
        var continuity = 0
        var ranked = 0

        var total: Int { about + rollups + continuity + ranked }
    }

    nonisolated struct Plan: Sendable, Equatable {
        var aboutEntityIDs: [UUID] = []
        var rollupMonths: [DateInterval] = []
        var continuityEntryIDs: [UUID] = []
        // Best first.
        var rankedEntryIDs: [UUID] = []
        // Matched on context alone, so they render as the sentences naming the entity rather than
        // two thousand characters of an entry about something else.
        var excerptOnlyEntryIDs: Set<UUID> = []
        // How many entries matched before the cut, which is the "84" in "12 of 84".
        var matchedCount = 0
        var estimatedCharacters = 0
        var appliedRange: DateInterval?
        var rangeWasInherited = false
        var isAggregate = false
        var slices = Slices()

        var entryIDs: [UUID] { rankedEntryIDs + continuityEntryIDs }
        var isEmpty: Bool { entryIDs.isEmpty && aboutEntityIDs.isEmpty }
        // Whether the prompt has to own up to a cut.
        var wasCut: Bool { matchedCount > rankedEntryIDs.count }
    }

    // The caps. The renderer applies each as min(cap, what is left) in this order, so a slice that
    // goes unused rolls forward into ranked rather than being wasted, and an earlier slice still
    // cannot eat the room ranked needed.
    static func slices(budget: Int, provider: AskProviderKind) -> Slices {
        guard budget > 0 else { return Slices() }
        switch provider {
        case .openAI:
            let about = min(aboutBudgetOpenAI, budget)
            let rollups = min(rollupBudgetOpenAI, budget - about)
            let continuity = min(continuityBudgetOpenAI, budget - about - rollups)
            return Slices(about: about, rollups: rollups, continuity: continuity,
                          ranked: budget - about - rollups - continuity)
        case .onDevice:
            // No rollups and no continuity here: one entry block is most of the budget, and an
            // answer with nothing to quote is worse than one that lost the thread.
            let about = min(aboutBudgetOnDevice, budget)
            return Slices(about: about, rollups: 0, continuity: 0, ranked: budget - about)
        }
    }

    static func plan(
        query: AskRetrievalQuery,
        index: AskIndex,
        budget: Int,
        provider: AskProviderKind,
        calendar: Calendar = .current
    ) -> Plan {
        var plan = Plan()
        plan.slices = slices(budget: budget, provider: provider)
        plan.appliedRange = query.namedRange ?? query.inheritedRange
        plan.rangeWasInherited = query.namedRange == nil && query.inheritedRange != nil
        plan.aboutEntityIDs = query.namedEntityIDs + query.carriedEntityIDs.filter { !query.namedEntityIDs.contains($0) }

        guard budget > 0 else { return plan }

        let scored = index.search(query.indexQuery)
        guard !scored.isEmpty else {
            plan.isAggregate = query.aggregateHint
            return plan
        }

        let limit = provider == .openAI ? maxRankedEntriesOpenAI : maxRankedEntriesOnDevice
        let floor = (scored.first?.score ?? 0) * matchRelevanceFloor
        plan.matchedCount = scored.filter { $0.score >= floor }.count
        // A question that named a stretch of time is asking about the whole stretch, so the entries
        // in it are the denominator whether or not they share a word with the question. Without
        // this, "how have I been feeling this year" matches the few entries using the word
        // "feeling", reports "8 of 8", and answers a year from two weeks with nothing to hedge
        // against. This is the honest-truncation half of the phase, and it only works here.
        if query.namedRange != nil {
            plan.matchedCount = max(plan.matchedCount, index.candidateCount(for: query.indexQuery))
        }
        plan.isAggregate = query.aggregateHint || plan.matchedCount > aggregateSizeFactor * limit

        // Rollups first, because what they take decides how much is left to rank into.
        var rollupCharacters = 0
        if plan.isAggregate, plan.slices.rollups > 0 {
            let affordable = plan.slices.rollups / rollupCharactersPerMonth
            let available = months(of: scored, in: index, calendar: calendar)
            plan.rollupMonths = Array(available.prefix(min(affordable, maxRollupMonthsOpenAI)))
            rollupCharacters = plan.rollupMonths.count * rollupCharactersPerMonth
        }

        // An About block's size can't be known here: an entity's bio isn't in the index, and
        // fetching one would put the journal back on the keystroke path. So its slice is reserved
        // whole when there is anyone to describe. The cost line then under-promises rather than
        // over-promising, which is the right direction for a line about what leaves the phone.
        let aboutReserve = plan.aboutEntityIDs.isEmpty ? 0 : plan.slices.about
        var remaining = max(0, budget - aboutReserve - rollupCharacters)

        var taken: Set<UUID> = []
        for result in scored.prefix(limit) {
            let document = index.documents[Int(result.document)]
            let cost = document.blockCharacters + blockSeparator
            guard cost <= remaining else { continue }
            remaining -= cost
            taken.insert(document.id)
            plan.rankedEntryIDs.append(document.id)
            if !result.matchedInBody { plan.excerptOnlyEntryIDs.insert(document.id) }
        }

        // What the conversation was already talking about, from its own slice, and only what the
        // ranked list didn't already pick up.
        if plan.slices.continuity > 0 {
            var continuityRemaining = min(plan.slices.continuity, remaining)
            for id in query.continuityEntryIDs where !taken.contains(id) {
                guard let document = index.document(withID: id), document.isSendable else { continue }
                let cost = document.blockCharacters + blockSeparator
                guard cost <= continuityRemaining else { continue }
                continuityRemaining -= cost
                remaining -= cost
                taken.insert(id)
                plan.continuityEntryIDs.append(id)
            }
        }

        // "12 of 8" would be nonsense. The floor can cut below what the ranked list then takes,
        // since ranking is not limited to what counts as a match.
        plan.matchedCount = max(plan.matchedCount, plan.rankedEntryIDs.count)

        plan.estimatedCharacters = rollupCharacters + plan.entryIDs.compactMap {
            index.document(withID: $0)?.blockCharacters
        }.reduce(0) { $0 + $1 + blockSeparator }

        return plan
    }

    // The blank line between two blocks, which the renderer pays for too.
    private static let blockSeparator = 2

    // Every month the matched set touches, newest first. The rollup itself is rendered elsewhere;
    // all the plan needs is which stretches of time to summarize.
    private static func months(of scored: [AskIndex.Scored], in index: AskIndex, calendar: Calendar) -> [DateInterval] {
        var seen: Set<Date> = []
        var months: [DateInterval] = []
        for result in scored {
            let date = index.documents[Int(result.document)].date
            guard let month = calendar.dateInterval(of: .month, for: date), seen.insert(month.start).inserted else { continue }
            months.append(month)
        }
        return months.sorted { $0.start > $1.start }
    }
}
