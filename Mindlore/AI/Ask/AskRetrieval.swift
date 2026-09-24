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
    // A second brake beside the budget: how many entries go in whole. Past twenty the tail is weak
    // matches arriving because there was room, and what a broad question needs from the tail is
    // coverage, not another two thousand characters of it. That is what the digest tier is for.
    static let maxRankedEntriesOpenAI = 20
    static let maxRankedEntriesOnDevice = 5

    // The digest tier. An entry that matched but didn't fit goes in as one line, so "what happened
    // this year" sees the year instead of whichever twenty entries ranked highest. A hundred and
    // fifty lines cost about what seven whole entries do.
    static let maxDigestEntries = 150

    // Absolute, per provider, not shares of the budget. On device the whole budget lands near 3,300
    // characters, where a 20% slice is 660 and a single entry block can be 2,050.
    static let aboutBudgetOpenAI = 3_600
    static let rollupBudgetOpenAI = 6_000
    // Exactly what the cap's worth of lines costs at their worst, so the slice and the cap can
    // never disagree about how many lines fit.
    static let digestBudgetOpenAI = AskDigests.estimatedCharacters(lineCount: maxDigestEntries)
    static let continuityBudgetOpenAI = 4_800
    // The most the notes Chat made or changed in this conversation may take before anything else.
    // A grocery list is a few hundred characters; this keeps a dozen of them from eating the answer.
    static let conversationNotesBudgetOpenAI = 8_000
    static let aboutBudgetOnDevice = 800

    // An entry has to be this close to the best match to count as matching at all. Counting every
    // non-zero score would make the number meaningless: a journal where most entries carry the same
    // life area matches most of itself on "how was work", and "12 of 3,000" teaches everyone to
    // ignore the line.
    static let matchRelevanceFloor = 0.25
    // A matched set this large is an aggregate question whatever its wording. An absolute number
    // rather than a multiple of the ranked cap, which is what it was: raising the cap from fifteen
    // to twenty silently moved the threshold from forty-five to sixty and turned rollups off for a
    // fifty-entry question. Rollups answer "how often", digests answer "what about"; widening one
    // must not narrow the other.
    static let aggregateMatchCount = 45
    // When nothing matches at all, the newest entries go instead of nothing. A7 chose this and the
    // rewrite dropped it by accident: "nothing to go on" offers no Retry, so a question the journal
    // simply has no word in common with became a dead end.
    static let recencyFallbackCount = 5
    // An About block may never take more than this much of the budget, however many people the
    // question names. On device the whole budget is near 3,300 and the reserve would otherwise
    // leave no room for an entry at all.
    static let aboutShareOfBudget = 0.5
    // The entry a conversation was opened from goes in whole, up to this, rather than at
    // maxEntryCharacters: "talk to me about this entry" answered from its first two thousand
    // characters would miss the end of a long recording. About twenty minutes of speech. On device
    // it takes whatever the budget has, since there the entry is the whole point.
    static let maxFocusCharactersOpenAI = 24_000

    nonisolated struct Slices: Sendable, Equatable {
        var about = 0
        var rollups = 0
        var digests = 0
        var continuity = 0
        var ranked = 0

        var total: Int { about + rollups + digests + continuity + ranked }
    }

    nonisolated struct Plan: Sendable, Equatable {
        // The entry the conversation is about, taken before anything else and rendered first.
        var focusEntryID: UUID?
        // How much of its text goes in: all of it, unless it is longer than the focus allows.
        var focusTextLimit = 0
        // Notes Chat made or changed earlier in this conversation, taken right after the focus so
        // a follow-up ("add butter to that list") always has the list in front of it.
        var noteEntryIDs: [UUID] = []
        var aboutEntityIDs: [UUID] = []
        var rollupMonths: [DateInterval] = []
        var continuityEntryIDs: [UUID] = []
        // Best first.
        var rankedEntryIDs: [UUID] = []
        // Matched, didn't fit whole, and goes in as one line each. Newest first, which is the order
        // they render in.
        var digestEntryIDs: [UUID] = []
        // What the digest block is allowed to cost, decided here so the renderer holds exactly the
        // slice the plan spent rather than the ceiling it chose from.
        var digestCharacters = 0
        // Entries reached because the question is about someone. They render as the sentences that
        // concern them, the way the old tier 1 did, so ten fit where three whole blocks would.
        var excerptEntryIDs: Set<UUID> = []
        // How many entries matched before the cut, which is the "84" in "12 of 84".
        var matchedCount = 0
        // Which entries those were, so a rollup counts the same set the number describes.
        var matchedEntryIDs: Set<UUID> = []
        // Nothing matched and the newest entries went instead, so an answer shouldn't be written as
        // though these were about the question.
        var matchedNothing = false
        var estimatedCharacters = 0
        var appliedRange: DateInterval?
        var rangeWasInherited = false
        var isAggregate = false
        var slices = Slices()

        // The entries that go in whole.
        var entryIDs: [UUID] { [focusEntryID].compactMap { $0 } + noteEntryIDs + rankedEntryIDs + continuityEntryIDs }
        // Everything whose text has to be fetched, digests included: a one-line digest is still
        // entry text leaving the phone, so it goes through the same gate in AskSources.
        var fetchedEntryIDs: [UUID] { entryIDs + digestEntryIDs }
        var isEmpty: Bool { entryIDs.isEmpty && aboutEntityIDs.isEmpty }
        // Whether the prompt has to own up to a cut. A digest counts as having seen the entry, so a
        // question whose whole matched set fit in lines has nothing to own up to.
        var wasCut: Bool { matchedCount > rankedEntryIDs.count + digestEntryIDs.count + (focusEntryID == nil ? 0 : 1) }
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
            let digests = min(digestBudgetOpenAI, budget - about - rollups)
            let continuity = min(continuityBudgetOpenAI, budget - about - rollups - digests)
            return Slices(about: about, rollups: rollups, digests: digests, continuity: continuity,
                          ranked: budget - about - rollups - digests - continuity)
        case .onDevice:
            // No rollups, no digests, and no continuity here: one entry block is most of the budget,
            // and an answer with nothing to quote is worse than one that lost the thread.
            let about = min(aboutBudgetOnDevice, budget)
            return Slices(about: about, rollups: 0, digests: 0, continuity: 0, ranked: budget - about)
        }
    }

    static func plan(
        query: AskRetrievalQuery,
        index: AskIndex,
        budget: Int,
        provider: AskProviderKind,
        // PR 2 renders rollups. Until it does, planning them would reserve and report characters
        // that never leave the phone.
        rollups: Bool = false,
        // The entry the conversation was opened from, if it was. Nil for an ordinary question.
        focusEntryID: UUID? = nil,
        // Notes Chat made or changed in this conversation, newest first. OpenAI only: the caller
        // passes none on device, where nothing can be written.
        noteEntryIDs: [UUID] = [],
        calendar: Calendar = .current
    ) -> Plan {
        var plan = Plan()
        plan.slices = slices(budget: budget, provider: provider)
        plan.appliedRange = query.namedRange ?? query.inheritedRange
        plan.rangeWasInherited = query.namedRange == nil && query.inheritedRange != nil
        plan.aboutEntityIDs = query.namedEntityIDs + query.carriedEntityIDs.filter { !query.namedEntityIDs.contains($0) }

        guard budget > 0 else { return plan }

        // First claim on the budget. Checked against the index like everything else, so an entry
        // that has become a draft since the conversation opened is simply not sent.
        var focusCost = 0
        if let focusEntryID, let document = index.document(withID: focusEntryID), document.isSendable {
            let overhead = document.blockCharacters - min(document.textCharacters, AskContextBuilder.maxEntryCharacters)
            let cap = provider == .openAI ? min(maxFocusCharactersOpenAI, budget) : budget
            let limit = min(document.textCharacters, cap - overhead)
            if limit > 0 {
                plan.focusEntryID = focusEntryID
                plan.focusTextLimit = limit
                focusCost = overhead + limit + blockSeparator
            }
        }
        // Then the conversation's own notes, whole or not at all, checked against the index like the
        // focus so one that has become a draft since is simply not sent.
        var notesCost = 0
        for id in noteEntryIDs where id != plan.focusEntryID && !plan.noteEntryIDs.contains(id) {
            guard let document = index.document(withID: id), document.isSendable else { continue }
            let cost = document.blockCharacters + blockSeparator
            guard notesCost + cost <= min(conversationNotesBudgetOpenAI, budget - focusCost) else { continue }
            notesCost += cost
            plan.noteEntryIDs.append(id)
        }
        focusCost += notesCost
        let budget = budget - focusCost

        var scored = index.search(query.indexQuery)
        var wasRecencyFallback = false
        // With an entry in hand, a question sharing no word with the journal ("what do you make of
        // this?") is about that entry, not a reason to send the newest five.
        if scored.isEmpty, plan.focusEntryID == nil, plan.noteEntryIDs.isEmpty {
            // A7's tier 4. A question sharing no word with the journal still gets an answer built
            // from the newest entries rather than a failure with no Retry on it.
            scored = Array(index.search(AskIndex.Query(sendableOnly: true, asOf: query.asOf)).prefix(recencyFallbackCount))
            wasRecencyFallback = true
            // The fallback ignores the range: these are the newest entries in the journal, not the
            // newest in March, so the prompt must not go on to say they are from March.
            plan.appliedRange = nil
            plan.rangeWasInherited = false
        }
        guard !scored.isEmpty else {
            plan.isAggregate = query.aggregateHint
            plan.estimatedCharacters = focusCost
            return plan
        }

        let limit = provider == .openAI ? maxRankedEntriesOpenAI : maxRankedEntriesOnDevice
        let floor = (scored.first?.score ?? 0) * matchRelevanceFloor
        plan.matchedNothing = wasRecencyFallback

        // The set the answer is being generalized from, named once so the count, the months, and
        // the rollup's own numbers can never describe different things.
        var matchedIndices = wasRecencyFallback ? [] : scored.filter { $0.score >= floor }.map(\.document)
        // A question that named a stretch of time is asking about the whole stretch, so the entries
        // in it are the denominator whether or not they share a word with the question. Without
        // this, "how have I been feeling this year" matches the few entries using the word
        // "feeling", reports "8 of 8", and answers a year from two weeks with nothing to hedge
        // against. This is the honest-truncation half of the phase, and it only works here.
        if query.namedRange != nil, !wasRecencyFallback {
            let candidates = index.candidateIndices(for: query.indexQuery)
            if candidates.count > matchedIndices.count { matchedIndices = candidates }
        }
        plan.matchedCount = matchedIndices.count
        plan.matchedEntryIDs = Set(matchedIndices.map { index.documents[Int($0)].id })
        plan.isAggregate = query.aggregateHint || plan.matchedCount > aggregateMatchCount

        // Rollups first, because what they take decides how much is left to rank into. The months
        // come from the matched set, not from everything scored: a single weak tail hit should not
        // widen the summary past what the number beside it claims.
        var rollupCharacters = 0
        if rollups, plan.isAggregate, plan.slices.rollups > 0 {
            var available = months(of: matchedIndices, in: index, calendar: calendar)
            // Oldest out first until it fits. Past two years the lines become years, and
            // estimatedCharacters knows that, so twenty-four month lines are not reserved for three
            // year lines' worth of text.
            while !available.isEmpty, AskRollups.estimatedCharacters(monthCount: available.count) > plan.slices.rollups {
                available.removeLast()
            }
            plan.rollupMonths = available
            rollupCharacters = AskRollups.estimatedCharacters(monthCount: available.count)
        }

        // What the About blocks will actually take, from the size hints the index carries, rather
        // than the whole slice. Reserving the slice whole cost two ranked entries on the commonest
        // question shape there is, and on device it could reserve the entire budget and send no
        // entry at all.
        let aboutReserve = self.aboutReserve(for: plan.aboutEntityIDs, in: index, slices: plan.slices, budget: budget)
        var remaining = max(0, budget - aboutReserve - rollupCharacters)

        let subjects = Set(plan.aboutEntityIDs)
        var taken = Set([plan.focusEntryID].compactMap { $0 } + plan.noteEntryIDs)
        for result in scored.prefix(limit) {
            let document = index.documents[Int(result.document)]
            guard !taken.contains(document.id) else { continue }
            let cost = document.blockCharacters + blockSeparator
            guard cost <= remaining else { continue }
            remaining -= cost
            taken.insert(document.id)
            plan.rankedEntryIDs.append(document.id)
            // The old tier 1's rule: an entry reached through a person the question names is quoted
            // at the sentences about them. Keying this off "no query term in the body" instead, as
            // an earlier pass did, inverted it exactly: the entity's own name is a query term, so
            // the set became the entries that never mention her, whose naming sentences do not
            // exist. It fired only on the entries it should have left whole.
            if !subjects.isDisjoint(with: document.entityIDs) { plan.excerptEntryIDs.insert(document.id) }
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

        // Digests take what the entries left, rather than being held back in front of them. Held
        // back, the reserve has to be charged at a line's worst case (160 characters) while a real
        // line costs about sixty, so a question matching two hundred entries lost two of its twenty
        // best-matching entries to room the lines then didn't use. An entry in full is worth more
        // than two and a half lines; when the budget is tight, the lines are what gives.
        //
        // Spread across the stretch rather than the newest run of it (see AskDigests.spread), and
        // only what nothing else already took: a digest of an entry sitting whole three blocks below
        // it would be the same day twice.
        let digestCapacity = min(
            maxDigestEntries,
            AskDigests.lineCapacity(characters: min(plan.slices.digests, remaining))
        )
        if digestCapacity > 0 {
            let candidates = matchedIndices
                .map { index.documents[Int($0)] }
                .filter { $0.isSendable && !taken.contains($0.id) }
                .sorted { $0.date > $1.date }
            plan.digestEntryIDs = AskDigests.spread(candidates.map(\.id), to: digestCapacity)
            plan.digestCharacters = AskDigests.estimatedCharacters(lineCount: plan.digestEntryIDs.count)
        }

        // "12 of 8" would be nonsense. The floor can cut below what the ranked list then takes,
        // since ranking is not limited to what counts as a match.
        plan.matchedCount = max(plan.matchedCount, plan.rankedEntryIDs.count + plan.digestEntryIDs.count)

        plan.estimatedCharacters = focusCost + aboutReserve + rollupCharacters + plan.digestCharacters + (plan.rankedEntryIDs + plan.continuityEntryIDs).compactMap {
            index.document(withID: $0)?.blockCharacters
        }.reduce(0) { $0 + $1 + blockSeparator }

        return plan
    }

    static func aboutReserve(for entityIDs: [UUID], in index: AskIndex, slices: Slices, budget: Int) -> Int {
        guard !entityIDs.isEmpty else { return 0 }
        let wanted = Set(entityIDs)
        let needed = index.entities.filter { wanted.contains($0.id) }.reduce(0) { $0 + $1.aboutCharacters + blockSeparator }
        return min(needed, slices.about, Int(Double(budget) * aboutShareOfBudget))
    }

    // The blank line between two blocks, which the renderer pays for too.
    private static let blockSeparator = 2

    // Every month the matched set touches, newest first. The rollup itself is rendered elsewhere;
    // all the plan needs is which stretches of time to summarize.
    private static func months(of documents: [Int32], in index: AskIndex, calendar: Calendar) -> [DateInterval] {
        var seen: Set<Date> = []
        var months: [DateInterval] = []
        for document in documents {
            let date = index.documents[Int(document)].date
            guard let month = calendar.dateInterval(of: .month, for: date), seen.insert(month.start).inserted else { continue }
            months.append(month)
        }
        return months.sorted { $0.start > $1.start }
    }
}
