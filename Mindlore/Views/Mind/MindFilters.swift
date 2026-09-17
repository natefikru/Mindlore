import Foundation

// What the map shows. A young journal has few entities mentioned twice, so its default minimum
// is one mention; from `largeJournal` browsable entities on it's two, which keeps a busy map
// readable.
nonisolated struct MindFilters: Hashable, Sendable {
    static let largeJournal = 60

    var kinds: Set<EntityKind> = Set(EntityKind.allCases)
    var minimumMentions = 2

    static func defaultMinimum(browsableCount: Int) -> Int {
        browsableCount < largeJournal ? 1 : 2
    }
}
