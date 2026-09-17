import Foundation

// Which life areas the Journal list offers and which entries a picked area keeps. Filtering happens
// in memory over the list's one query, never through the insights relationship in a predicate.
nonisolated enum JournalFilter {
    // A hidden area can't stay picked: it would filter by something the user can no longer see.
    static func active(_ picked: LifeArea?, hidden: Set<String>) -> LifeArea? {
        guard let picked, !hidden.contains(picked.rawValue) else { return nil }
        return picked
    }

    static func matches(areasRaw: [String], area: LifeArea?) -> Bool {
        guard let area else { return true }
        return areasRaw.contains(area.rawValue)
    }

    // Visible areas that at least one entry is filed under, in the fixed order.
    static func offered(entryAreas: [[String]], hidden: Set<String>) -> [LifeArea] {
        let used = Set(entryAreas.joined())
        return LifeArea.allCases.filter { used.contains($0.rawValue) && !hidden.contains($0.rawValue) }
    }
}
