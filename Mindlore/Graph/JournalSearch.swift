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

    // Every entry carrying a tag, for the row that fills the entries section with that tag.
    static func entries(taggedWith tag: String, in context: ModelContext) -> [EntryRow] {
        let entries = searchableEntries(in: context)
            .filter { entry in (entry.insights?.tags ?? []).contains { $0.caseInsensitiveCompare(tag) == .orderedSame } }
        return Array(newestFirst(entries).prefix(maxEntries)).map { row(for: $0, around: nil) }
    }

    // Ranked by the index, then one bounded fetch for the titles and snippets of what it chose.
    // Two full-journal scans per keystroke pause become none.
    private static func entryRows(matching query: String, index: AskIndex, now: Date, in context: ModelContext) -> [EntryRow] {
        let ranked = index.search(text: query, asOf: now).prefix(maxEntries)
        guard !ranked.isEmpty else { return [] }
        let wanted = ranked.map { index.documents[Int($0.document)].id }
        let byID = Dictionary(
            ((try? context.fetch(FetchDescriptor<Entry>())) ?? [])
                .filter { !$0.isDeleted && !$0.isDraft }
                .map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return zip(wanted, ranked).compactMap { id, scored in
            guard let entry = byID[id] else { return nil }
            return row(for: entry, around: query, document: index.documents[Int(scored.document)])
        }
    }

    private static func searchableEntries(in context: ModelContext) -> [Entry] {
        ((try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { !$0.isDraft }))) ?? []).filter { !$0.isDeleted }
    }

    private static func newestFirst(_ entries: [Entry]) -> [Entry] {
        entries.sorted { $0.entryDate > $1.entryDate }
    }

    private static func row(for entry: Entry, around query: String?, document: AskIndex.Document? = nil) -> EntryRow {
        EntryRow(
            id: entry.id,
            title: displayTitle(for: entry),
            date: entry.entryDate,
            isDayOnly: entry.entryDateIsDayOnly,
            snippet: snippet(in: entry.text, around: query),
            reason: reason(for: entry, query: query, document: document)
        )
    }

    // An entry can now rank on a tag, a life area, or a person who appears nowhere in its words, and
    // the snippet then falls back to the opening of the entry: a row with no visible reason for
    // being there. This says why instead.
    static func reason(for entry: Entry, query: String?, document: AskIndex.Document?) -> String? {
        guard let document, let query, !query.isEmpty else { return nil }
        let words = Set(AskRetrievalQuery.terms(in: query))
        guard !words.isEmpty else { return nil }
        let text = AskIndex.fold(entry.title + " " + entry.text)
        guard !words.contains(where: text.contains) else { return nil }
        if let tag = document.tags.first(where: { words.contains(AskIndex.fold($0)) }) {
            return "tag: \(tag)"
        }
        if let area = document.areas.first(where: { words.contains(AskIndex.fold($0)) }) {
            return "area: \(area)"
        }
        return "mentions someone by this name"
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
