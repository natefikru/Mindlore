import Foundation
import SwiftData

// The half of Life that touches the store: it turns entries, their insights, loose ends, and links
// into `LifeSignals` facts, the split `TodaySource` keeps from `TodayComposer`.
@MainActor
enum LifeSource {
    struct Facts {
        let entries: [LifeSignals.EntryFact]
        let threads: [LifeSignals.ThreadFact]
    }

    // Every finished entry that insights have read. Only a journal entry carries a mood (a note or
    // a creative piece never has one), so every kind counts toward where the writing went and only
    // journal entries toward how it felt. A tag whose entity is hidden never shows.
    static func facts(in context: ModelContext) -> Facts {
        let entries = ((try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { !$0.isDraft }))) ?? [])
            .filter { !$0.isDeleted && $0.insights != nil }
        let hiddenTags = hiddenTagNames(in: context)
        let entryFacts = entries.map { entry in
            let insights = entry.insights
            return LifeSignals.EntryFact(
                id: entry.id,
                date: entry.entryDate,
                areas: insights?.areas ?? [],
                valence: entry.kind.keepsMoods ? insights?.primaryMood?.category.valence : nil,
                tags: (insights?.tags ?? []).filter { !hiddenTags.contains($0.lowercased()) },
                thinking: entry.kind.keepsMoods ? (insights?.thinkingPatterns ?? []) : []
            )
        }
        let areasByEntry = Dictionary(entryFacts.map { ($0.id, $0.areas) }, uniquingKeysWith: { first, _ in first })
        let directory = EntityDirectory(in: context)
        let threads = LooseEnd.all(in: context).compactMap { end -> LifeSignals.ThreadFact? in
            // The same rule as Reflect's Loose ends: a thread about a hidden name is left out whole.
            guard !end.entityIDs.contains(where: { directory.entity(directory.root(of: $0))?.hidden == true }) else { return nil }
            return LifeSignals.ThreadFact(
                id: end.id,
                status: end.status,
                raisedOn: end.sourceEntryDate,
                closedAt: end.isOpen ? nil : end.statusChangedAt,
                areas: end.sourceEntryID.flatMap { areasByEntry[$0] } ?? []
            )
        }
        return Facts(entries: entryFacts, threads: threads)
    }

    private static func hiddenTagNames(in context: ModelContext) -> Set<String> {
        let tag = EntityKind.tag.rawValue
        let hidden = (try? context.fetch(FetchDescriptor<Entity>(predicate: #Predicate { $0.hidden && $0.kindRaw == tag }))) ?? []
        return Set(hidden.flatMap { [$0.name] + $0.aliases }.map { $0.lowercased() })
    }

    // MARK: - One area's page

    struct Person: Identifiable, Equatable {
        let id: UUID
        let name: String
        let kind: EntityKind
        let entries: Int
    }

    // The names in the given entries, merges walked, hidden and muted ones left out, most shared
    // first. Tags are the recurring-topics list's, not people.
    static func people(in entryIDs: [UUID], limit: Int = 6, context: ModelContext) -> [Person] {
        let wanted = Set(entryIDs)
        guard !wanted.isEmpty else { return [] }
        let links = ((try? context.fetch(FetchDescriptor<EntityLink>())) ?? []).filter { link in
            !link.isDeleted && link.kind != .tag && link.entryID.map(wanted.contains) == true
        }
        let directory = EntityDirectory(in: context)
        var entriesByRoot: [UUID: Set<UUID>] = [:]
        for link in links {
            guard let entityID = link.entityID, let entryID = link.entryID else { continue }
            entriesByRoot[directory.root(of: entityID), default: []].insert(entryID)
        }
        return entriesByRoot.compactMap { root, entries -> Person? in
            guard let entity = directory.entity(root), !entity.hidden, !entity.resurfacingMuted,
                  entity.kind != .tag, !entity.name.isEmpty else { return nil }
            return Person(id: root, name: entity.name, kind: entity.kind, entries: entries.count)
        }
        .sorted { $0.entries != $1.entries ? $0.entries > $1.entries : $0.name < $1.name }
        .prefix(limit)
        .map { $0 }
    }

    struct EntryRow: Identifiable, Equatable {
        let id: UUID
        let date: Date
        let title: String
        let preview: String
    }

    static func entryRows(_ ids: [UUID], limit: Int = 5, context: ModelContext) -> [EntryRow] {
        ids.prefix(limit).compactMap { id in
            let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id })
            guard let entry = (try? context.fetch(descriptor))?.first, !entry.isDeleted else { return nil }
            return EntryRow(id: entry.id, date: entry.entryDate, title: entry.title, preview: entry.previewText ?? "")
        }
    }

    // Open loose ends raised by an entry in this area, soonest due first.
    static func openThreads(area: LifeArea, context: ModelContext) -> [ReflectLooseEnds.Item] {
        let items = ReflectLooseEndSource.items(in: context).filter(\.isOpen)
        let sourceIDs = Set(items.compactMap(\.sourceEntryID))
        var inArea: Set<UUID> = []
        for id in sourceIDs {
            let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id })
            if let entry = (try? context.fetch(descriptor))?.first, entry.insights?.areas.contains(area) == true {
                inArea.insert(id)
            }
        }
        return ReflectLooseEnds.openFirst(items.filter { $0.sourceEntryID.map(inArea.contains) == true })
    }
}
