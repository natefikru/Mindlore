import Foundation

// One ranked list where Ask used to have four tiers. An immutable snapshot of the journal's words,
// built off the main actor and holding no entry text: the plan chooses ids, and AskSources fetches
// the text for the few entries that won. That is what lets the cost line under the field cost
// nothing, where today every pause in typing reads the whole journal.
//
// A document is indexed twice over. Its own words are the body. Its entities, tags, life areas,
// mood, and month are context, which is how "What's going on with Maya?" reaches an entry that
// never spells her name. Terms are folded and interned, so the index can say an entry holds a word
// without being able to hand the word's sentence back. The two are scored apart and the body counts for more, or forty entries
// linked to the same person would all score the same and length would pick the winner.
nonisolated struct AskIndex: Sendable {
    // MARK: - Shapes

    // What the caller hands over. Text goes in and does not come out.
    nonisolated struct DocumentInput: Sendable {
        let id: UUID
        let date: Date
        var title: String = ""
        var text: String = ""
        var entityIDs: [UUID] = []
        // Names and aliases of those entities, resolved through their roots by the caller.
        var entityNames: [String] = []
        var tags: [String] = []
        var areas: [String] = []
        var mood: String?
        // Whether this entry may be sent to a provider (InsightsCoordinator.canRunAI). The panel
        // searches everything; Ask searches only these.
        var isSendable: Bool = true
        // What rendering this entry as a block would cost, so a plan can divide a budget without
        // reading any text.
        var blockCharacters: Int = 0
    }

    // Enough to find a name in a question without fetching. Bios and loose ends stay out: they
    // are needed only once the plan has chosen, and AskSources fetches them then.
    nonisolated struct Entity: Sendable, Equatable {
        let id: UUID
        let name: String
        var aliases: [String] = []
        var kindRaw: String = ""
        var isBrowsable: Bool = true
        // What describing this entity would cost, so the plan can reserve what an About block will
        // actually take instead of the whole slice. A length, never the bio itself: the index holds
        // no prose.
        var aboutCharacters: Int = 0
    }

    nonisolated struct Document: Sendable, Equatable {
        let id: UUID
        let date: Date
        var entityIDs: [UUID] = []
        var tags: [String] = []
        var areas: [String] = []
        var mood: String?
        var isSendable: Bool = true
        var blockCharacters: Int = 0
        // Tokens in the body and title, for BM25's length normalization.
        var length: Int = 0
        // Context tokens, normalized against each other rather than against the body. A two-word
        // entry linked to Maya should not out-score a long, detailed one about her.
        var contextLength: Int = 0
    }

    nonisolated struct Term: Sendable, Equatable {
        let text: String
        // The conversation's decay ladder: a carried term counts for less than one just typed.
        var weight: Double = 1
    }

    nonisolated struct Query: Sendable, Equatable {
        var terms: [Term] = []
        // A range this question named. A hard filter: a question naming a stretch of time means it.
        var namedRange: DateInterval?
        // A range an earlier question named. A boost and never a filter, or "what did I do last
        // week" followed by "what about Maya" would throw away every older entry about her.
        var inheritedRange: DateInterval?
        // The panel's last word is half-typed. A sent question is finished, so Ask never sets this.
        var expandsLastTerm = false
        var sendableOnly = true
        var asOf: Date = .distantPast
    }

    nonisolated struct Scored: Sendable, Equatable {
        let document: Int32
        let score: Double
        // Whether a query term appeared in the entry's own words rather than only in its entities,
        // tags, area, or month. True on the fallback paths, where no term was scored at all.
        let matchedInBody: Bool
    }

    // MARK: - Constants

    static let k1 = 1.2
    static let b = 0.75
    // A word in the title is worth two in paragraph nine.
    static let titleWeight: Double = 2
    static let contextWeight: Double = 1.5
    // How much a context hit counts against a body hit. Below 1 on purpose.
    static let contextFactor = 0.4
    // A two-year-old entry that answers the question shouldn't be buried under last Tuesday, so
    // age can cost a score 1.43x at most. It breaks ties; it doesn't overturn relevance.
    //
    // Measured, because 0.5 read as reasonable and wasn't. An entry 400 days old with the word in
    // its title and twice in its body scores 1.708 against 0.979 for a fresh entry mentioning it
    // once, a 1.74x win. At a floor of 0.5 age costs 1.91x and the passing mention wins, which is
    // the old tier order's mistake in a new coat. At 0.7 the cost is 1.40x, relevance holds, and
    // two entries that genuinely tie still sort newest first.
    static let recencyFloor = 0.7
    static let inheritedRangeBoost: Double = 2
    // One-letter tokens carry nothing. Two-letter ones do ("AI", "NY"), and the query's stop list
    // already covers the two-letter English noise.
    static let minimumTermLength = 2
    // A bound on how wide a two-letter prefix may reach while typing.
    static let maxPrefixExpansions = 64

    // MARK: - Stored

    let documents: [Document]
    let entities: [Entity]

    private let termIDs: [String: Int32]
    // Parallel, sorted by term, for prefix lookup by binary search.
    private let sortedTerms: [String]
    private let sortedTermIDs: [Int32]
    private let postings: [Int32: Posting]
    private let averageLength: Double
    private let averageContextLength: Double
    private let documentIndexByID: [UUID: Int]
    private let tagDocuments: [String: [Int32]]
    private let tagSpellings: [String: String]

    // Packed columns rather than an array of structs: at five thousand entries this is roughly
    // three quarters of a million postings, and the per-element overhead is the whole cost.
    private struct Posting: Sendable {
        var documents: [Int32] = []
        var body: [Float] = []
        var context: [Float] = []

        mutating func append(document: Int32, body bodyWeight: Float, context contextWeight: Float) {
            documents.append(document)
            body.append(bodyWeight)
            context.append(contextWeight)
        }
    }

    static let empty = AskIndex()

    private init(
        documents: [Document] = [],
        entities: [Entity] = [],
        termIDs: [String: Int32] = [:],
        sortedTerms: [String] = [],
        sortedTermIDs: [Int32] = [],
        postings: [Int32: Posting] = [:],
        averageLength: Double = 0,
        averageContextLength: Double = 0,
        documentIndexByID: [UUID: Int] = [:],
        tagDocuments: [String: [Int32]] = [:],
        tagSpellings: [String: String] = [:]
    ) {
        self.documents = documents
        self.entities = entities
        self.termIDs = termIDs
        self.sortedTerms = sortedTerms
        self.sortedTermIDs = sortedTermIDs
        self.postings = postings
        self.averageLength = averageLength
        self.averageContextLength = averageContextLength
        self.documentIndexByID = documentIndexByID
        self.tagDocuments = tagDocuments
        self.tagSpellings = tagSpellings
    }

    var isEmpty: Bool { documents.isEmpty }
    var termCount: Int { termIDs.count }
    var postingCount: Int { postings.values.reduce(0) { $0 + $1.documents.count } }

    // MARK: - Building

    static func build(from inputs: [DocumentInput], entities: [Entity] = []) -> AskIndex {
        var termIDs: [String: Int32] = [:]
        var postings: [Int32: Posting] = [:]
        var documents: [Document] = []
        var tagDocuments: [String: [Int32]] = [:]
        var tagSpellings: [String: String] = [:]
        var totalLength = 0
        var totalContextLength = 0

        documents.reserveCapacity(inputs.count)

        for (offset, input) in inputs.enumerated() {
            let document = Int32(offset)
            var weights: [Int32: (body: Float, context: Float)] = [:]
            var length = 0
            var contextLength = 0

            func add(_ text: String, weight: Double, isBody: Bool) {
                for token in tokens(in: text) {
                    let id = intern(token, into: &termIDs)
                    var found = weights[id] ?? (0, 0)
                    if isBody {
                        found.body += Float(weight)
                        length += 1
                    } else {
                        found.context += Float(weight)
                        contextLength += 1
                    }
                    weights[id] = found
                }
            }

            add(input.text, weight: 1, isBody: true)
            add(input.title, weight: titleWeight, isBody: true)
            for name in input.entityNames { add(name, weight: contextWeight, isBody: false) }
            for tag in input.tags { add(tag, weight: contextWeight, isBody: false) }
            for area in input.areas { add(area, weight: contextWeight, isBody: false) }
            if let mood = input.mood { add(mood, weight: contextWeight, isBody: false) }
            // "in March" and "2025" are things people ask, and the entry's own day knows both.
            add(monthAndYear(of: input.date), weight: contextWeight, isBody: false)

            for (id, weight) in weights {
                postings[id, default: Posting()].append(document: document, body: weight.body, context: weight.context)
            }

            for tag in input.tags {
                let key = fold(tag)
                guard !key.isEmpty else { continue }
                tagDocuments[key, default: []].append(document)
                if tagSpellings[key] == nil { tagSpellings[key] = tag }
            }

            documents.append(
                Document(
                    id: input.id,
                    date: input.date,
                    entityIDs: input.entityIDs,
                    tags: input.tags,
                    areas: input.areas,
                    mood: input.mood,
                    isSendable: input.isSendable,
                    blockCharacters: input.blockCharacters,
                    length: length,
                    contextLength: contextLength
                )
            )
            totalLength += length
            totalContextLength += contextLength
        }

        let sorted = termIDs.sorted { $0.key < $1.key }
        return AskIndex(
            documents: documents,
            entities: entities,
            termIDs: termIDs,
            sortedTerms: sorted.map(\.key),
            sortedTermIDs: sorted.map(\.value),
            postings: postings,
            averageLength: documents.isEmpty ? 0 : Double(totalLength) / Double(documents.count),
            averageContextLength: documents.isEmpty ? 0 : Double(totalContextLength) / Double(documents.count),
            documentIndexByID: Dictionary(documents.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first }),
            tagDocuments: tagDocuments,
            tagSpellings: tagSpellings
        )
    }

    private static func intern(_ token: String, into ids: inout [String: Int32]) -> Int32 {
        if let existing = ids[token] { return existing }
        let id = Int32(ids.count)
        ids[token] = id
        return id
    }

    // Case and diacritics fold once, at index time, so "Renée" and "renee" are one term and the
    // panel's old predicate behaviour survives the move to a ranked list.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: posixLocale)
    }

    static func tokens(in text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        let folded = fold(text)
        var tokens: [String] = []
        folded.enumerateSubstrings(in: folded.startIndex..., options: .byWords) { substring, _, _, _ in
            guard let substring else { return }
            // Word enumeration keeps a contraction whole, so "what's" arrives as one token and the
            // stop list, which holds "what", never sees it. Splitting on the apostrophe drops the
            // tail ("s", "t", "re" are all too short to index) and leaves the word itself, which is
            // also what makes "Maya's" find Maya.
            for part in substring.split(whereSeparator: apostrophes.contains) where part.count >= minimumTermLength {
                tokens.append(String(part))
            }
        }
        return tokens
    }

    private static let apostrophes: Set<Character> = ["'", "\u{2019}"]

    static func monthAndYear(of date: Date) -> String {
        monthYearFormatter.string(from: date)
    }

    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    // English, like the stop list and the date phrases, and fixed so a device's locale can't
    // change what a term is.
    private static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = posixLocale
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    // MARK: - Searching

    func search(_ query: Query) -> [Scored] {
        guard !documents.isEmpty else { return [] }

        var allowed = [Bool](repeating: true, count: documents.count)
        for (offset, document) in documents.enumerated() {
            if query.sendableOnly, !document.isSendable {
                allowed[offset] = false
                continue
            }
            if let range = query.namedRange, !(document.date >= range.start && document.date < range.end) {
                allowed[offset] = false
            }
        }

        var bodyScores = [Double](repeating: 0, count: documents.count)
        var contextScores = [Double](repeating: 0, count: documents.count)
        var matchedInBody = [Bool](repeating: false, count: documents.count)

        for (offset, term) in query.terms.enumerated() {
            let expands = query.expandsLastTerm && offset == query.terms.count - 1
            let ids = expands ? prefixTermIDs(for: term.text) : exactTermID(for: term.text).map { [$0] } ?? []
            guard !ids.isEmpty else { continue }

            // One term contributes once per document, at its best expansion rather than the sum of
            // them, or typing "mar" would let an entry holding march, market, and marathon outrank
            // the one entry about Maria.
            var bestBody: [Int: Double] = [:]
            var bestContext: [Int: Double] = [:]

            for id in ids {
                guard let posting = postings[id] else { continue }
                let idf = inverseDocumentFrequency(documentsWithTerm: posting.documents.count)
                for (position, document) in posting.documents.enumerated() {
                    let index = Int(document)
                    guard allowed[index] else { continue }
                    let body = Double(posting.body[position])
                    let context = Double(posting.context[position])
                    if body > 0 {
                        let normalizer = Self.lengthNormalizer(length: documents[index].length, average: averageLength)
                        let score = term.weight * idf * Self.saturation(frequency: body, normalizer: normalizer)
                        if score > bestBody[index] ?? 0 { bestBody[index] = score }
                    }
                    if context > 0 {
                        // Its own normalizer. Sharing the body's would mean a two-word entry linked
                        // to Maya scores a bigger context hit than a long, detailed one about her,
                        // which is the inverse of what the body and context split is for.
                        let normalizer = Self.lengthNormalizer(length: documents[index].contextLength, average: averageContextLength)
                        let score = term.weight * idf * Self.saturation(frequency: context, normalizer: normalizer)
                        if score > bestContext[index] ?? 0 { bestContext[index] = score }
                    }
                }
            }

            for (index, score) in bestBody {
                bodyScores[index] += score
                matchedInBody[index] = true
            }
            for (index, score) in bestContext {
                contextScores[index] += score
            }
        }

        // A question that is nothing but stop words ("Why?") has only recency to go on. What carries
        // the conversation there is the carried terms and the continuity slice, not this.
        func assemble(scoringTerms: Bool) -> [Scored] {
            var scored: [Scored] = []
            for index in documents.indices where allowed[index] {
                var score: Double
                if scoringTerms {
                    score = bodyScores[index] + Self.contextFactor * contextScores[index]
                    guard score > 0 else { continue }
                } else {
                    score = 1
                }
                let document = documents[index]
                if let range = query.inheritedRange, document.date >= range.start, document.date < range.end {
                    score *= Self.inheritedRangeBoost
                }
                score *= recencyMultiplier(for: document.date, asOf: query.asOf)
                // Nothing was scored on the fallback paths, so there is no body-or-context answer to
                // give and claiming "context only" would be a guess.
                scored.append(Scored(document: Int32(index), score: score, matchedInBody: scoringTerms ? matchedInBody[index] : true))
            }
            return scored
        }

        var scored = assemble(scoringTerms: !query.terms.isEmpty)
        // A question that named a stretch of time is asking for that stretch, so it gets it even
        // when none of its words appear in any of it. "How have I been feeling this year?" shares
        // "feeling" with almost no entry, and returning nothing would be a regression: the old tier
        // 3 sent the range. A question that names no time and matches nothing still sends nothing.
        if scored.isEmpty, !query.terms.isEmpty, query.namedRange != nil {
            scored = assemble(scoringTerms: false)
        }

        return scored.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            let left = documents[Int(lhs.document)]
            let right = documents[Int(rhs.document)]
            // A stable order, newest first, so two identical scores don't shuffle between runs.
            return left.date == right.date ? lhs.document < rhs.document : left.date > right.date
        }
    }

    // How many entries the question could be answered from at all, before a single term is scored.
    // When a question names a stretch of time, this is the honest denominator: the person asked
    // about a period, and the period is what the answer is being generalized from.
    // What the panel searches with: a raw string rather than a conversation. The last word is
    // half-typed, so it expands by prefix. A query this finds nothing for, including one that is
    // nothing but stop words ("my", "go", "today"), is the caller's cue to fall back to matching the
    // middle of a word, which is what the old predicate did and what JournalSearch still does.
    func search(text: String, sendableOnly: Bool = false, asOf: Date) -> [Scored] {
        let terms = AskRetrievalQuery.terms(in: text).map { Term(text: $0) }
        guard !terms.isEmpty else { return [] }
        return search(Query(terms: terms, expandsLastTerm: true, sendableOnly: sendableOnly, asOf: asOf))
    }

    // Which of the query's words a document actually holds, for a panel row that has to say why it
    // is there and for windowing a snippet on something the entry really contains.
    func matchedTerms(of text: String, in document: Document) -> (tags: [String], areas: [String], mood: String?, month: Bool) {
        let words = Set(AskRetrievalQuery.terms(in: text))
        guard !words.isEmpty else { return ([], [], nil, false) }
        return (
            document.tags.filter { words.contains(Self.fold($0)) },
            document.areas.filter { words.contains(Self.fold($0)) },
            document.mood.flatMap { words.contains(Self.fold($0)) ? $0 : nil },
            !words.isDisjoint(with: Set(Self.tokens(in: Self.monthAndYear(of: document.date))))
        )
    }

    func candidateCount(for query: Query) -> Int {
        candidateIndices(for: query).count
    }

    // Everything the question could be answered from, before a term is scored. When a question names
    // a stretch of time this is the set the answer is being generalized from, so it is what both the
    // "12 of 84" denominator and the rollup's counts are built from.
    func candidateIndices(for query: Query) -> [Int32] {
        documents.indices.compactMap { offset in
            let document = documents[offset]
            if query.sendableOnly, !document.isSendable { return nil }
            if let range = query.namedRange, !(document.date >= range.start && document.date < range.end) { return nil }
            return Int32(offset)
        }
    }

    func entities(namedIn question: String) -> [Entity] {
        entities.filter { entity in
            ([entity.name] + entity.aliases).contains { name in
                !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && NameMatching.range(of: name, in: question) != nil
            }
        }
    }

    // The panel's tag rows: the whole tag, not a prefix, since a tag row is an exact thing to tap.
    func tagCounts(matching query: String) -> [(tag: String, count: Int)] {
        let key = Self.fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !key.isEmpty, let documents = tagDocuments[key], let spelling = tagSpellings[key] else { return [] }
        return [(spelling, documents.count)]
    }

    // Called once per planned entry, which is once per pause in typing, so it is not a linear scan.
    func document(withID id: UUID) -> Document? {
        documentIndexByID[id].map { documents[$0] }
    }

    // MARK: - Scoring pieces

    private func inverseDocumentFrequency(documentsWithTerm count: Int) -> Double {
        let total = Double(documents.count)
        let holding = Double(count)
        return log(1 + (total - holding + 0.5) / (holding + 0.5))
    }

    private static func lengthNormalizer(length: Int, average: Double) -> Double {
        1 - b + b * Double(length) / max(average, 1)
    }

    private static func saturation(frequency: Double, normalizer: Double) -> Double {
        (frequency * (k1 + 1)) / (frequency + k1 * normalizer)
    }

    private func recencyMultiplier(for date: Date, asOf: Date) -> Double {
        let age = max(0, asOf.timeIntervalSince(date))
        let decay = pow(0.5, age / EntityGraph.defaultHalfLife)
        return Self.recencyFloor + (1 - Self.recencyFloor) * decay
    }

    // MARK: - Terms

    private func exactTermID(for text: String) -> Int32? {
        termIDs[Self.fold(text)]
    }

    private func prefixTermIDs(for text: String) -> [Int32] {
        let prefix = Self.fold(text)
        guard !prefix.isEmpty else { return [] }
        var ids: [Int32] = []
        var index = lowerBound(of: prefix)
        while index < sortedTerms.count, sortedTerms[index].hasPrefix(prefix) {
            ids.append(sortedTermIDs[index])
            index += 1
        }
        guard ids.count > Self.maxPrefixExpansions else { return ids }
        // Keep the rarest, not the alphabetically first. Truncating in order meant typing "ma"
        // spent the whole budget on made, mail, main, make, man, many, map and never reached the
        // one name the person was typing.
        return Array(ids.sorted { (postings[$0]?.documents.count ?? 0) < (postings[$1]?.documents.count ?? 0) }
            .prefix(Self.maxPrefixExpansions))
    }

    private func lowerBound(of prefix: String) -> Int {
        var low = 0
        var high = sortedTerms.count
        while low < high {
            let middle = (low + high) / 2
            if sortedTerms[middle] < prefix {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }
}
