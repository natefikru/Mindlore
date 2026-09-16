import Foundation

// Pure filter and sort for the Connections list. The view builds `ConnectionRow` from `Entity`
// and calls these; nothing here touches SwiftData.
nonisolated enum ConnectionsPresentation {
    struct ConnectionRow: Equatable, Identifiable {
        let id: UUID
        let name: String
        let aliases: [String]
        let kind: EntityKind
        let linkCount: Int
        let lastLinkedAt: Date?
    }

    enum SortOption: CaseIterable {
        case name, mostMentioned, recent
    }

    static func filter(_ rows: [ConnectionRow], kind: EntityKind?, search: String) -> [ConnectionRow] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return rows.filter { row in
            (kind == nil || row.kind == kind)
                && (query.isEmpty || row.name.localizedStandardContains(query) || row.aliases.contains { $0.localizedStandardContains(query) })
        }
    }

    static func sort(_ rows: [ConnectionRow], by option: SortOption) -> [ConnectionRow] {
        switch option {
        case .name:
            return rows.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .mostMentioned:
            return rows.sorted { lhs, rhs in
                if lhs.linkCount != rhs.linkCount { return lhs.linkCount > rhs.linkCount }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        case .recent:
            return rows.sorted { lhs, rhs in
                switch (lhs.lastLinkedAt, rhs.lastLinkedAt) {
                case (let l?, let r?): return l > r
                case (nil, nil): return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                case (nil, _): return false
                case (_, nil): return true
                }
            }
        }
    }
}
