import Foundation
import SwiftData

// Ask's search-as-you-type: entries, entities, and tags, with no AI and no network.
//
// Entries and tags come from the same AskIndex the prompt is built from, so the panel and the
// question stop being two search engines that disagree: before this, typing "What did I do by the
// river?" showed "Nothing in the journal matches that" while the line underneath said asking would
// send one entry, because the panel matched the whole question as a substring and retrieval
// tokenized it. Entities still reuse Mind's rows.
enum JournalSearch {
    static let minimumQueryCharacters = 2
    static let maxEntries = 30
    static let maxEntities = 8
    static let maxTags = 8
    static let snippetCharacters = 90

    nonisolated struct EntryRow: Equatable, Identifiable, Sendable {
        let id: UUID
        let title: String
        let date: Date
        let isDayOnly: Bool
        let snippet: String
        // Why this row is here, when the words are not in the entry itself.
        var reason: String?
    }

    nonisolated struct TagRow: Equatable, Identifiable, Sendable {
        var id: String { tag }
        let tag: String
        let count: Int
    }

    nonisolated struct Results: Equatable, Sendable {
        var entries: [EntryRow] = []
        var entities: [EntitySearch.Row] = []
        var tags: [TagRow] = []

        var isEmpty: Bool { entries.isEmpty && entities.isEmpty && tags.isEmpty }
    }

    static func results(for query: String, index: AskIndex, now: Date = .now, in context: ModelContext) -> Results {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumQueryCharacters else { return Results() }
        return Results(
            entries: entryRows(matching: trimmed, index: index, now: now, in: context),
            entities: Array(EntitySearch.rank(EntitySearch.filter(MindDirectory.rows(in: context).visible, segment: .all, query: trimmed), query: trimmed).prefix(maxEntities)),
            tags: index.tagCounts(matching: trimmed).prefix(maxTags).map { TagRow(tag: $0.tag, count: $0.count) }
        )
    }

    // Every entry carrying a tag, for the row that fills the entries section with that tag. Read
    // from the index, like the count on the row above it, so the two cannot say different numbers.
    static func entries(taggedWith tag: String, index: AskIndex, in context: ModelContext) -> [EntryRow] {
        let folded = AskIndex.fold(tag)
        let ids = index.documents
            .filter { $0.tags.contains { AskIndex.fold($0) == folded } }
            .sorted { $0.date > $1.date }
            .prefix(maxEntries)
            .map(\.id)
        let byID = Dictionary(fetch(ids: Array(ids), in: context).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }.map { row(for: $0, around: nil) }
    }

    // Ranked by the index, then one bounded fetch for the titles and snippets of the thirty it
    // chose. Two full-journal scans per keystroke pause become none.
    private static func entryRows(matching query: String, index: AskIndex, now: Date, in context: ModelContext) -> [EntryRow] {
        let ranked = Array(index.search(text: query, asOf: now).prefix(maxEntries))
        guard !ranked.isEmpty else { return substringRows(matching: query, in: context) }
        let wanted = ranked.map { index.documents[Int($0.document)].id }
        return zip(wanted, ranked).compactMap { id, scored in
            guard let entry = fetch(ids: [id], in: context).first else { return nil }
            return row(for: entry, around: query, document: index.documents[Int(scored.document)], index: index)
        }
    }

    // The one thing prefix matching loses: typing "iver" and finding "river", or typing a word the
    // stop list drops ("my", "go", "today") and finding it anyway. It runs only when the ranked path
    // came back with nothing, so it costs one predicate fetch on a query that was about to show an
    // empty panel.
    private static func substringRows(matching query: String, in context: ModelContext) -> [EntryRow] {
        var descriptor = FetchDescriptor<Entry>(
            predicate: #Predicate { !$0.isDraft && ($0.text.localizedStandardContains(query) || $0.title.localizedStandardContains(query)) },
            sortBy: [SortDescriptor(\.entryDate, order: .reverse)]
        )
        descriptor.fetchLimit = maxEntries
        return ((try? context.fetch(descriptor)) ?? [])
            .filter { !$0.isDeleted }
            .map { row(for: $0, around: query) }
    }

    // Bounded by the ids the ranking chose, rather than reading the journal and filtering it.
    private static func fetch(ids: [UUID], in context: ModelContext) -> [Entry] {
        var descriptor = FetchDescriptor<Entry>(predicate: #Predicate { !$0.isDraft && ids.contains($0.id) })
        descriptor.fetchLimit = ids.count
        return ((try? context.fetch(descriptor)) ?? []).filter { !$0.isDeleted }
    }

    private static func row(for entry: Entry, around query: String?, document: AskIndex.Document? = nil, index: AskIndex? = nil) -> EntryRow {
        EntryRow(
            id: entry.id,
            title: displayTitle(for: entry),
            date: entry.entryDate,
            isDayOnly: entry.entryDateIsDayOnly,
            // Windowed on a word the entry actually holds, not on the whole query: typing a question
            // at the panel matched no literal substring, so every row showed its own opening.
            snippet: snippet(in: entry.text, around: matchedWord(of: query, in: entry) ?? query),
            reason: reason(for: entry, query: query, document: document, index: index)
        )
    }

    // The first of the query's words that is really in the entry, for the snippet window.
    static func matchedWord(of query: String?, in entry: Entry) -> String? {
        guard let query else { return nil }
        let text = AskIndex.fold(entry.title + " " + entry.text)
        return AskRetrievalQuery.terms(in: query).first { text.contains($0) }
    }

    // An entry can rank on a tag, a life area, a mood, a month, or a person appearing nowhere in its
    // words, and the snippet is then just the entry's opening: a row with no visible reason for
    // being there. This says which it was, and only ever says what it checked.
    static func reason(for entry: Entry, query: String?, document: AskIndex.Document?, index: AskIndex?) -> String? {
        guard let document, let index, let query, !query.isEmpty else { return nil }
        guard matchedWord(of: query, in: entry) == nil else { return nil }
        let matched = index.matchedTerms(of: query, in: document)
        if let tag = matched.tags.first { return "tag: \(tag)" }
        if let area = matched.areas.first { return "area: \(area)" }
        if let mood = matched.mood { return "mood: \(mood)" }
        if matched.month { return "written in \(AskIndex.monthAndYear(of: entry.entryDate))" }
        // Ranked on a name the entry never spells. The index knows which entities, but not with
        // which words, so this says the shape of it rather than guessing at a name.
        if !document.entityIDs.isEmpty { return "mentions someone by this name" }
        // Ranked on a lemma: the entry says "ran" and the question said "run". Every other reason
        // has been ruled out by here, and a prefix match is not one of them, because "kay" is a
        // substring of "kayak" and matchedWord would have found it. Without this the row that
        // lemmas earned is the one kind of row that appears with nothing said about why.
        return lemmaMatched(query: query, in: entry) ? "a different form of a word you typed" : nil
    }

    // The entry is what gets lemmatized, because the entry is what carries the inflection: the
    // journal says "ran" and the question says "run", not the other way round. Lemmatizing the
    // query instead reads as the cheaper option and answers the rarer half of the pair.
    //
    // It only runs for a row that has no other reason to show, which is a small share of them, and
    // it stops after the first thousand characters. A lemma in paragraph nine of a long entry goes
    // uncaptioned rather than costing the panel a full lemmatization per row per keystroke.
    static let lemmaReasonCharacters = 1_000

    static func lemmaMatched(query: String, in entry: Entry) -> Bool {
        let asked = Set(AskRetrievalQuery.terms(in: query))
        guard !asked.isEmpty else { return false }
        let text = String((entry.title + " " + entry.text).prefix(lemmaReasonCharacters))
        return AskIndex.lemmas(in: text).contains { asked.contains($0) }
    }

    static func displayTitle(for entry: Entry) -> String {
        let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        let firstLine = entry.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Untitled" : String(trimmed.prefix(snippetCharacters))
    }

    // A window of text around the first match, cut at word boundaries, with ellipses where it
    // was cut. With no query it is just the opening of the entry.
    static func snippet(in text: String, around query: String?, length: Int = snippetCharacters) -> String {
        let flat = text.split(whereSeparator: { $0.isNewline }).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !flat.isEmpty else { return "" }
        guard let query, !query.isEmpty,
              let match = flat.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return clipped(flat, from: flat.startIndex, length: length, leadingEllipsis: false)
        }
        let before = length / 3
        var start = flat.startIndex
        if let stepped = flat.index(match.lowerBound, offsetBy: -before, limitedBy: flat.startIndex) {
            start = stepped
        }
        let atStart = start == flat.startIndex
        if !atStart, let space = flat[start...].firstIndex(where: \.isWhitespace) {
            start = flat.index(after: space)
        }
        return clipped(flat, from: start, length: length, leadingEllipsis: !atStart)
    }

    private static func clipped(_ text: String, from start: String.Index, length: Int, leadingEllipsis: Bool) -> String {
        var end = text.endIndex
        var trailingEllipsis = false
        if let limit = text.index(start, offsetBy: length, limitedBy: text.endIndex), limit < text.endIndex {
            end = limit
            trailingEllipsis = true
            if let space = text[start..<limit].lastIndex(where: \.isWhitespace), space > start {
                end = space
            }
        }
        let body = text[start..<end].trimmingCharacters(in: .whitespaces)
        return (leadingEllipsis ? "…" : "") + body + (trailingEllipsis ? "…" : "")
    }
}
