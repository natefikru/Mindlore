import Foundation

// Which life areas the Journal list offers and which entries the picked ones keep. Filtering
// happens in memory over the list's one query, never through the insights relationship in a
// predicate.
nonisolated enum JournalFilter {
    // A hidden area can't stay picked: it would filter by something the user can no longer see.
    static func active(_ picked: Set<LifeArea>, hidden: Set<String>) -> Set<LifeArea> {
        picked.filter { !hidden.contains($0.rawValue) }
    }

    // Any of them, not all: an entry filed under Work or Health shows when either is picked.
    // Nothing picked means no filter at all.
    static func matches(areasRaw: [String], areas: Set<LifeArea>) -> Bool {
        guard !areas.isEmpty else { return true }
        return areasRaw.contains { raw in areas.contains { $0.rawValue == raw } }
    }

    // Visible areas that at least one entry is filed under, in the fixed order.
    static func offered(entryAreas: [[String]], hidden: Set<String>) -> [LifeArea] {
        let used = Set(entryAreas.joined())
        return LifeArea.allCases.filter { used.contains($0.rawValue) && !hidden.contains($0.rawValue) }
    }

    // "Nothing in Work or Health", capped so a wide selection doesn't run off the screen.
    static func emptyStateTitle(_ areas: [String]) -> String {
        switch areas.count {
        case 0: return "Nothing here"
        case 1: return "Nothing in \(areas[0])"
        case 2: return "Nothing in \(areas[0]) or \(areas[1])"
        case 3: return "Nothing in \(areas[0]), \(areas[1]) or \(areas[2])"
        default:
            let rest = areas.count - 2
            return "Nothing in \(areas[0]), \(areas[1]) and \(rest) more"
        }
    }
}
