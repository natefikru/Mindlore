import Foundation

// What a question is actually asking, given the questions before it.
//
// This is the piece Ask has never had. Retrieval re-runs every turn today, but it runs on the
// current question's literal words, so turn two retrieves as if turn one never happened. Ask
// "What's going on with Maya?" and then "Why do you think that started?": every word of the
// follow-up is a stop word except "started", so Maya is gone and the prompt fills with whatever
// else used that word. Ask "Why?" alone and nothing survives at all.
//
// So the last three questions contribute terms, decayed, and the entries the last two answers
// cited come along separately. Nothing here is stored: a reopened conversation rebuilds all of it
// from the messages it already saved.
nonisolated struct AskRetrievalQuery: Sendable, Equatable {
    // How much a term from an earlier question is worth. A topic fades over three turns rather
    // than sticking until someone changes the subject.
    static let carryDecay = 0.5
    static let carryDepth = 3
    // Answers whose citations are worth re-sending. The model can see it said something about
    // Maya; without these it cannot re-read the entry it said it from.
    static let continuityTurns = 2

    var terms: [AskIndex.Term] = []
    // This question's own range. A hard filter.
    var namedRange: DateInterval?
    // The previous question's range, carried one turn. A boost only: used as a filter, "What did I
    // do last week?" followed by "What about Maya?" would discard every older entry about her.
    var inheritedRange: DateInterval?
    var namedEntityIDs: [UUID] = []
    var carriedEntityIDs: [UUID] = []
    var continuityEntryIDs: [UUID] = []
    // A marker in the wording suggests an aggregate question. Only a hint: AskRetrieval.Plan
    // decides, because the size of the matched set is the other half of the answer.
    var aggregateHint = false
    var asOf: Date = .distantPast

    // What the index is handed. The panel builds its own query; this is Ask's.
    var indexQuery: AskIndex.Query {
        AskIndex.Query(
            terms: terms,
            namedRange: namedRange,
            inheritedRange: inheritedRange,
            expandsLastTerm: false,
            sendableOnly: true,
            asOf: asOf
        )
    }

    static func build(
        question: String,
        previousQuestions: [String] = [],   // newest first
        citedEntryIDs: [[UUID]] = [],       // newest answer first
        index: AskIndex,
        now: Date,
        calendar: Calendar = .current
    ) -> AskRetrievalQuery {
        var query = AskRetrievalQuery()
        query.asOf = now

        let named = index.entities(namedIn: question).filter(\.isBrowsable)
        query.namedEntityIDs = named.map(\.id)

        // Weights, highest wins. A term the person just typed is worth full weight even if an
        // earlier turn also used it; summing would let a word repeated three times outrank the
        // rare word that actually distinguishes the question.
        var weights: [String: Double] = [:]
        // Kept in order, this question's words first and the oldest turn's last, so the list reads
        // the way the conversation ran.
        var order: [String] = []
        func add(_ texts: [String], weight: Double) {
            for text in texts {
                for term in terms(in: text) {
                    if weights[term] == nil { order.append(term) }
                    if weight > (weights[term] ?? 0) { weights[term] = weight }
                }
            }
        }

        let current = [question] + named.flatMap { [$0.name] + $0.aliases.prefix(AskContextBuilder.maxAliasesPerEntity) }
        add(current, weight: 1)

        var carried: [UUID] = []
        for (offset, previous) in previousQuestions.prefix(carryDepth - 1).enumerated() {
            let weight = pow(carryDecay, Double(offset + 1))
            let entities = index.entities(namedIn: previous).filter(\.isBrowsable)
            for entity in entities where !query.namedEntityIDs.contains(entity.id) && !carried.contains(entity.id) {
                carried.append(entity.id)
            }
            let texts = [previous] + entities.flatMap { [$0.name] + $0.aliases.prefix(AskContextBuilder.maxAliasesPerEntity) }
            add(texts, weight: weight)
        }
        query.carriedEntityIDs = carried
        query.terms = order.compactMap { term in
            weights[term].map { AskIndex.Term(text: term, weight: $0) }
        }

        query.namedRange = AskDates.range(in: question, now: now, calendar: calendar)
        // One turn, and only when this question neither named a range nor named someone. A question
        // that names a person has changed the subject, and the old range would only hide them.
        if query.namedRange == nil, query.namedEntityIDs.isEmpty, let previous = previousQuestions.first {
            query.inheritedRange = AskDates.range(in: previous, now: now, calendar: calendar)
        }

        query.continuityEntryIDs = citedEntryIDs.prefix(continuityTurns).reduce(into: [UUID]()) { result, ids in
            for id in ids where !result.contains(id) { result.append(id) }
        }

        query.aggregateHint = isAggregate(question)
        return query
    }

    // MARK: - Words

    // Tokenized the same way the index is, so a term always matches something a document could
    // hold, then filtered by the stop list. The three-letter floor AskContextBuilder.keywords
    // applies is gone: the stop list already covers the two-letter English noise, and dropping it
    // cost "AI" and "NY".
    static func terms(in text: String) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for token in AskIndex.tokens(in: text) where !AskContextBuilder.stopWords.contains(token) {
            if seen.insert(token).inserted { result.append(token) }
        }
        return result
    }

    // A question about the shape of a stretch of journal rather than about what is in one entry.
    // Fixed and English, like the stop list and the date phrases. A false positive costs one
    // compact rollup block; a false negative is how "how have I been feeling this year" gets
    // answered confidently from the last two weeks.
    static let aggregatePhrases: Set<String> = [
        "how often", "how many", "how much", "every time", "in general", "on average",
        "keep coming back", "come back to", "better than", "worse than", "more often",
        "less often", "over time", "do i usually", "do i always", "do i tend",
    ]

    // Words that can only be asking about a shape. "never" and "compare" were here and came out:
    // "did I ever tell her, or never?" is a question about one evening, and a false positive costs
    // a rollup block that says nothing about what was asked.
    static let aggregateWords: Set<String> = [
        "most", "usually", "always", "pattern", "patterns", "trend", "trends",
        "generally", "typically", "often",
    ]

    static func isAggregate(_ question: String) -> Bool {
        let folded = AskIndex.fold(question)
        if aggregatePhrases.contains(where: folded.contains) { return true }
        let words = Set(AskIndex.tokens(in: question))
        return !words.isDisjoint(with: aggregateWords)
    }
}
