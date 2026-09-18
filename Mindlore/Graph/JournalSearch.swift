import Foundation
import SwiftData

// Ask's search-as-you-type: entries, entities, and tags, with no AI and no network. Entries come
// from one predicate fetch; entities reuse Mind's rows; tags are counted off Entry, not
// EntryInsights, because insights carry no entry id and reaching through the relationship is
// what tasks/lessons.md rules out.
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

    static func results(for query: String, in context: ModelContext) -> Results {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumQueryCharacters else { return Results() }
        return Results(
            entries: entryRows(matching: trimmed, in: context),
            entities: Array(EntitySearch.rank(EntitySearch.filter(MindDirectory.rows(in: context).visible, segment: .all, query: trimmed), query: trimmed).prefix(maxEntities)),
            tags: tagRows(matching: trimmed, in: context)
        )
    }

    // Every entry carrying a tag, for the row that fills the entries section with that tag.
    static func entries(taggedWith tag: String, in context: ModelContext) -> [EntryRow] {
        let entries = searchableEntries(in: context)
            .filter { entry in (entry.insights?.tags ?? []).contains { $0.caseInsensitiveCompare(tag) == .orderedSame } }
        return Array(newestFirst(entries).prefix(maxEntries)).map { row(for: $0, around: nil) }
    }

    private static func entryRows(matching query: String, in context: ModelContext) -> [EntryRow] {
        var descriptor = FetchDescriptor<Entry>(
            predicate: #Predicate { !$0.isDraft && ($0.text.localizedStandardContains(query) || $0.title.localizedStandardContains(query)) },
            sortBy: [SortDescriptor(\.entryDate, order: .reverse)]
        )
        descriptor.fetchLimit = maxEntries
        let entries = ((try? context.fetch(descriptor)) ?? []).filter { !$0.isDeleted }
        return entries.map { row(for: $0, around: query) }
    }

    private static func tagRows(matching query: String, in context: ModelContext) -> [TagRow] {
        var counts: [String: (display: String, count: Int)] = [:]
        for entry in searchableEntries(in: context) {
            // The whole tag, not a prefix: a tag row is an exact thing to tap, and a partial
            // match would offer a tag the entries section is already showing.
            for tag in entry.insights?.tags ?? [] where tag.caseInsensitiveCompare(query) == .orderedSame {
                let key = tag.lowercased()
                counts[key] = (counts[key]?.display ?? tag, (counts[key]?.count ?? 0) + 1)
            }
        }
        return counts.values
            .sorted { $0.count == $1.count ? $0.display.localizedStandardCompare($1.display) == .orderedAscending : $0.count > $1.count }
            .prefix(maxTags)
            .map { TagRow(tag: $0.display, count: $0.count) }
    }

    private static func searchableEntries(in context: ModelContext) -> [Entry] {
        ((try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { !$0.isDraft }))) ?? []).filter { !$0.isDeleted }
    }

    private static func newestFirst(_ entries: [Entry]) -> [Entry] {
        entries.sorted { $0.entryDate > $1.entryDate }
    }

    private static func row(for entry: Entry, around query: String?) -> EntryRow {
        EntryRow(
            id: entry.id,
            title: displayTitle(for: entry),
            date: entry.entryDate,
            isDayOnly: entry.entryDateIsDayOnly,
            snippet: snippet(in: entry.text, around: query)
        )
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
