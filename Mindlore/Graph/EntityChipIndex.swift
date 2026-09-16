import Foundation

// Which entity each tag, theme, and name on an entry's insights opens. Built from that entry's
// links, looked up by the link's kind: the exact words first, then the normalized key, so a
// value still finds its link when only case or punctuation differs.
nonisolated struct EntityChipIndex: Equatable {
    struct LinkInput: Equatable {
        let surface: String
        let kind: EntityKind
        let entityID: UUID
        let inferred: Bool
        // Hidden entities open nothing: the user asked not to see them.
        let entityHidden: Bool
    }

    struct Chip: Equatable {
        let entityID: UUID
        let guessed: Bool
    }

    private struct Lookup: Hashable {
        let text: String
        let kind: EntityKind
    }

    private var exact: [Lookup: Chip] = [:]
    private var keyed: [Lookup: Chip] = [:]

    static let empty = EntityChipIndex(links: [])

    init(links: [LinkInput]) {
        for link in links where !link.entityHidden {
            let chip = Chip(entityID: link.entityID, guessed: link.inferred)
            exact[Lookup(text: link.surface, kind: link.kind)] = exact[Lookup(text: link.surface, kind: link.kind)] ?? chip
            let key = EntityNormalizer.key(for: link.surface, kind: link.kind)
            if !key.isEmpty {
                keyed[Lookup(text: key, kind: link.kind)] = keyed[Lookup(text: key, kind: link.kind)] ?? chip
            }
        }
    }

    func chip(for value: String, kind: EntityKind) -> Chip? {
        if let chip = exact[Lookup(text: value, kind: kind)] { return chip }
        let key = EntityNormalizer.key(for: value, kind: kind)
        guard !key.isEmpty else { return nil }
        return keyed[Lookup(text: key, kind: kind)]
    }
}
