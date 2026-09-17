import Foundation

// The path of focused entities in Mind, most recent last, for the breadcrumb row. Refocusing
// something already on the trail steps back to it rather than repeating it.
nonisolated struct FocusTrail: Equatable, Sendable {
    static let cap = 8

    private(set) var ids: [UUID] = []

    var current: UUID? { ids.last }

    mutating func focus(_ id: UUID) {
        if let index = ids.firstIndex(of: id) {
            ids.removeSubrange((index + 1)...)
        } else {
            ids.append(id)
            if ids.count > Self.cap { ids.removeFirst(ids.count - Self.cap) }
        }
    }

    mutating func back(to id: UUID) {
        guard let index = ids.firstIndex(of: id) else { return }
        ids.removeSubrange((index + 1)...)
    }

    mutating func clear() {
        ids = []
    }

    mutating func replace(_ loser: UUID, with winner: UUID) {
        normalize(root: { $0 == loser ? winner : $0 }, exists: { _ in true })
    }

    // After every refresh: a merged id becomes its winner (a merge can happen from anywhere, not
    // just a pushed page), neighbours that became the same entity collapse into one, and ids
    // whose entity is gone drop out.
    mutating func normalize(root: (UUID) -> UUID, exists: (UUID) -> Bool) {
        var result: [UUID] = []
        for id in ids {
            let resolved = root(id)
            guard exists(resolved) else { continue }
            if let index = result.firstIndex(of: resolved) {
                // The same entity twice: keep the later visit, as refocusing would.
                result.removeSubrange(index...)
            }
            result.append(resolved)
        }
        ids = result
    }
}
