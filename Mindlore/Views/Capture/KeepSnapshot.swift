import Foundation
import SwiftData

// What the Keep card says the app noticed in one entry, read from what Phase A already stores: the
// entry's links, the loose ends it settled, and how the graph grew. No AI call is made for the card.
//
// Rebuilt from a fresh fetch every time the graph's revision moves, never held across an await, so an
// entity merged or pruned while the card is up simply reads differently on the next refresh.
struct KeepSnapshot: Equatable {
    struct Noticed: Equatable, Identifiable {
        let id: UUID
        let name: String
        let kind: EntityKind
        let contactIdentifier: String?
        // Every mention of it is in this entry: the journal met it here.
        let isNew: Bool
    }

    struct Closed: Equatable, Identifiable {
        let id: UUID
        let text: String
        let openSince: Date
    }

    var noticed: [Noticed] = []
    var closed: [Closed] = []
    // Loose ends this entry opened.
    var opened: [String] = []
    // Names on the map: visible, unmerged, mentioned somewhere. Tags are not names.
    var namesOnTheMap = 0

    var newCount: Int { noticed.count(where: \.isNew) }

    static let empty = KeepSnapshot()
    // The card is a glance; a long entry's tenth name belongs on the entry.
    static let noticedLimit = 6

    static func make(entryID: UUID, links: [EntityLink], in context: ModelContext) -> KeepSnapshot {
        let entities = ((try? context.fetch(FetchDescriptor<Entity>())) ?? []).filter { !$0.isDeleted }
        let byID = Dictionary(entities.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        func root(_ id: UUID) -> Entity? {
            guard var current = byID[id] else { return nil }
            var seen: Set<UUID> = [current.id]
            while let nextID = current.mergedIntoID, let next = byID[nextID], seen.insert(next.id).inserted {
                current = next
            }
            return current
        }

        // Which entries mention each entity, after merges.
        var entriesByRoot: [UUID: Set<UUID>] = [:]
        for link in links {
            guard let entityID = link.entityID, let entry = link.entryID, let root = root(entityID) else { continue }
            entriesByRoot[root.id, default: []].insert(entry)
        }

        var snapshot = KeepSnapshot()
        var seen: Set<UUID> = []
        for link in links where link.entryID == entryID {
            guard let entityID = link.entityID, let entity = root(entityID), !entity.hidden, entity.kind.isAName else { continue }
            guard seen.insert(entity.id).inserted else { continue }
            snapshot.noticed.append(.init(
                id: entity.id,
                name: entity.name,
                kind: entity.kind,
                contactIdentifier: entity.contactIdentifier,
                isNew: entriesByRoot[entity.id] == [entryID]
            ))
        }
        // New names first, then the better known, and a stable order under both.
        snapshot.noticed.sort { lhs, rhs in
            if lhs.isNew != rhs.isNew { return lhs.isNew }
            let (left, right) = (entriesByRoot[lhs.id]?.count ?? 0, entriesByRoot[rhs.id]?.count ?? 0)
            return left != right ? left > right : lhs.name < rhs.name
        }
        snapshot.noticed = Array(snapshot.noticed.prefix(noticedLimit))

        snapshot.namesOnTheMap = entities.count { entity in
            entity.mergedIntoID == nil && !entity.hidden && entity.kind.isAName && !(entriesByRoot[entity.id] ?? []).isEmpty
        }

        for looseEnd in LooseEnd.all(in: context) {
            if looseEnd.resolvedByEntryID == entryID, looseEnd.status == .resolved {
                snapshot.closed.append(.init(id: looseEnd.id, text: looseEnd.text, openSince: looseEnd.sourceEntryDate))
            } else if looseEnd.sourceEntryID == entryID, looseEnd.isOpen {
                snapshot.opened.append(looseEnd.text)
            }
        }
        snapshot.closed.sort { $0.openSince < $1.openSince }
        return snapshot
    }
}

extension EntityKind {
    // A person, place, organization, project, or event. A tag is a word, not a name, and "other" is
    // whatever the model couldn't place.
    var isAName: Bool {
        switch self {
        case .person, .place, .organization, .project, .event: true
        case .tag, .other: false
        }
    }
}

extension AIPassTrigger {
    // A recording that ends in the Keep card never opens the editor, so no editor closes to start its
    // automatic pass, and a live-transcribed one never reaches the transcription queue either, so no
    // text "arrives". Without this its insights would wait for the next launch sweep.
    // An entry still waiting for its text is not eligible yet; `.textReady` takes it from there.
    func recordingKept(_ entry: Entry, in context: ModelContext) {
        guard fire(for: entry, at: .kept) else { return }
        try? context.saveStampingEntries()
        onFlagged?()
    }
}
