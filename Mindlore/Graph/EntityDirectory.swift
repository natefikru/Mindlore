import Foundation
import SwiftData

// Every entity read once, with merges walked to the entity that stands for them now.
struct EntityDirectory {
    private let byID: [UUID: Entity]

    init(in context: ModelContext) {
        let all = ((try? context.fetch(FetchDescriptor<Entity>())) ?? []).filter { !$0.isDeleted }
        byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func entity(_ id: UUID) -> Entity? {
        byID[id]
    }

    // The merge winner, with a guard against a cycle nobody should be able to make.
    func root(of id: UUID) -> UUID {
        var current = id
        var seen: Set<UUID> = [id]
        while let next = byID[current]?.mergedIntoID, seen.insert(next).inserted {
            current = next
        }
        return current
    }

    // Of the entities behind `ids`, the roots whose name or an alias appears in the text.
    func rootsNamed(in text: String, among ids: Set<UUID>) -> Set<UUID> {
        var result: Set<UUID> = []
        for root in Set(ids.map(root(of:))) {
            guard let entity = byID[root] else { continue }
            if ([entity.name] + entity.aliases).contains(where: { NameMatching.range(of: $0, in: text) != nil }) {
                result.insert(root)
            }
        }
        return result
    }
}
