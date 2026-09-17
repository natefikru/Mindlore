import Foundation

// Decides which entity a single extracted value belongs to. Pure: it reads a snapshot of the
// entities that exist and returns what should happen, so GraphIndexer owns every write and
// this stays testable without a store.
nonisolated enum EntityResolver {
    // One value pulled out of an entry's insights.
    struct Value: Equatable, Sendable {
        let surface: String
        let kind: EntityKind

        var key: String { EntityNormalizer.key(for: surface, kind: kind) }
    }

    // What the resolver knows about one existing entity. Snapshotted so scoring never touches
    // the store, and so the indexer can add entities it just created to the same list.
    struct Candidate: Equatable, Sendable {
        let id: UUID
        let key: String
        let kind: EntityKind
        let aliasKeys: [String]
        let hidden: Bool
        let kindEditedByUser: Bool
        let linkCount: Int
        let confirmedByUser: Bool

        var keys: [String] { [key] + aliasKeys }
    }

    enum Outcome: Equatable, Sendable {
        // Link to this entity. `upgradeKind` promotes an untouched `other` to what the mention says.
        case existing(id: UUID, inferred: Bool, upgradeKind: EntityKind?)
        case create(key: String, kind: EntityKind)
        // Nothing to key on: punctuation, or a name that was only an honorific.
        case skip
    }

    static func resolve(_ value: Value, among candidates: [Candidate]) -> Outcome {
        let key = value.key
        guard !key.isEmpty else { return .skip }

        // 1. Exact match on a name or an alias. Hidden entities count, so hiding something
        //    keeps it hidden instead of quietly recreating it under a new id.
        let exact = candidates.filter { candidate in
            candidate.keys.contains(key) && matches(kind: value.kind, candidate)
        }
        if let winner = bestExact(exact) {
            return .existing(id: winner.id, inferred: false, upgradeKind: upgrade(value.kind, winner))
        }

        // 2. A bare first name joins the only person it could be. Hidden entities are excluded:
        //    a mention that vanished into something the user hid would have nothing to show.
        if value.kind == .person, EntityNormalizer.tokens(of: key).count == 1 {
            let sharingFirstName = candidates.filter { candidate in
                candidate.kind == .person && !candidate.hidden
                    && candidate.keys.contains { other in
                        let tokens = EntityNormalizer.tokens(of: other)
                        return tokens.count > 1 && tokens.first == key
                    }
            }
            let distinct = Set(sharingFirstName.map(\.id))
            if distinct.count == 1, let only = sharingFirstName.first {
                return .existing(id: only.id, inferred: true, upgradeKind: nil)
            }
        }

        // 3. Something new.
        return .create(key: key, kind: value.kind)
    }

    // A value matches its own kind, and either side may be `other`: an untouched `other` gets
    // upgraded, and a mention typed `other` joins whatever is already there.
    //
    // Tags and themes are outside that. They are labels for an entry, not named things, and
    // the Review list only ever offers to merge them by hand when they are written
    // identically. Letting `other` reach them would do that merge silently.
    private static func matches(kind: EntityKind, _ candidate: Candidate) -> Bool {
        if candidate.kind == kind { return true }
        if isLabel(kind) || isLabel(candidate.kind) { return false }
        if candidate.kind == .other && !candidate.kindEditedByUser { return true }
        if kind == .other { return true }
        return false
    }

    private static func upgrade(_ kind: EntityKind, _ candidate: Candidate) -> EntityKind? {
        guard candidate.kind == .other, kind != .other, !isLabel(kind), !candidate.kindEditedByUser else { return nil }
        return kind
    }

    static func isLabel(_ kind: EntityKind) -> Bool {
        kind == .tag || kind == .theme
    }

    // Two live entities can share a key after a rename collision the user pushed through.
    // Prefer the one they confirmed, then the one the journal actually uses.
    private static func bestExact(_ candidates: [Candidate]) -> Candidate? {
        candidates.max {
            ($0.confirmedByUser ? 1 : 0, $0.linkCount, $0.id.uuidString)
                < ($1.confirmedByUser ? 1 : 0, $1.linkCount, $1.id.uuidString)
        }
    }

    // Whether an exact match was ambiguous, so the indexer can record it.
    static func isAmbiguous(_ value: Value, among candidates: [Candidate]) -> Bool {
        let key = value.key
        guard !key.isEmpty else { return false }
        let exact = candidates.filter { $0.keys.contains(key) && matches(kind: value.kind, $0) }
        return Set(exact.map(\.id)).count > 1
    }

    // The full set of exact matches, but only when `bestExact` isn't really choosing anything: a
    // single confirmed candidate among unconfirmed others already reflects a real decision (the
    // same case `bestExact` resolves cleanly), so it isn't tied. Two or more confirmed, or none
    // confirmed at all, is a real tie, and `GraphIndexer` records it on the link instead of
    // silently picking with `bestExact`'s `linkCount`/id tie-break (5c.4).
    static func tied(_ value: Value, among candidates: [Candidate]) -> [UUID] {
        let key = value.key
        guard !key.isEmpty else { return [] }
        let exact = candidates.filter { $0.keys.contains(key) && matches(kind: value.kind, $0) }
        guard Set(exact.map(\.id)).count > 1 else { return [] }
        guard exact.filter(\.confirmedByUser).count != 1 else { return [] }
        return exact.map(\.id)
    }
}
