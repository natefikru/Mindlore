import Foundation

// The name search Mind's panel runs over every entity, and Ask's entity results will too. Pure:
// callers build `Row` from their own fetch.
nonisolated enum EntitySearch {
    struct Row: Equatable, Identifiable, Sendable {
        let id: UUID
        let name: String
        var aliases: [String] = []
        let kind: EntityKind
        var linkCount = 0
        var lastMentioned: Date?
        var openLooseEnds = 0
    }

    enum Segment: String, CaseIterable, Sendable {
        case all, people, places, projects, tags

        var title: String {
            switch self {
            case .all: "All"
            case .people: "People"
            case .places: "Places"
            case .projects: "Projects"
            case .tags: "Tags"
            }
        }

        func includes(_ kind: EntityKind) -> Bool {
            switch self {
            case .all: true
            case .people: kind == .person
            case .places: kind == .place
            case .projects: kind == .project
            case .tags: kind == .tag
            }
        }
    }

    static func filter(_ rows: [Row], segment: Segment, query: String) -> [Row] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return rows.filter { row in
            segment.includes(row.kind)
                && (query.isEmpty || row.name.localizedStandardContains(query) || row.aliases.contains { $0.localizedStandardContains(query) })
        }
    }

    // With a query: names starting with it, then names with a word starting with it, then the
    // rest (a match inside a word, or an alias). Within a group, and with no query at all, the most
    // recently mentioned come first.
    static func rank(_ rows: [Row], query: String) -> [Row] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        func group(_ row: Row) -> Int {
            guard !query.isEmpty else { return 0 }
            let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .anchored]
            if row.name.range(of: query, options: options) != nil { return 0 }
            let words = row.name.split(whereSeparator: { $0.isWhitespace || $0 == "-" })
            if words.contains(where: { $0.range(of: query, options: options) != nil }) { return 1 }
            return 2
        }
        return rows
            .map { (row: $0, group: group($0)) }
            .sorted { lhs, rhs in
                if lhs.group != rhs.group { return lhs.group < rhs.group }
                switch (lhs.row.lastMentioned, rhs.row.lastMentioned) {
                case (let l?, let r?) where l != r: return l > r
                case (_?, nil): return true
                case (nil, _?): return false
                default: return lhs.row.name.localizedStandardCompare(rhs.row.name) == .orderedAscending
                }
            }
            .map(\.row)
    }
}
