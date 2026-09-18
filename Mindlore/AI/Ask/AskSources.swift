import Foundation
import SwiftData

// What Ask is allowed to read, gathered once per question. Everything the builder sees comes
// from here, so the rules about what may leave the phone live in one place.
enum AskSources {
    struct Journal {
        var entries: [AskContextBuilder.EntryInput] = []
        var entities: [AskContextBuilder.EntityInput] = []
    }

    // Every entry the app would run AI on, however old. Transcription keeps the aiEnabledAt
    // boundary because it uploads recordings the user never asked it to; a question is the
    // opposite, and a journal that answers only the last few weeks answers nothing worth asking.
    static func journal(in context: ModelContext) -> Journal {
        let all = ((try? context.fetch(FetchDescriptor<Entry>())) ?? []).filter { !$0.isDeleted }
        let eligible = all.filter(InsightsCoordinator.canRunAI)
        guard !eligible.isEmpty else { return Journal() }

        let directory = EntityDirectory(in: context)
        var entityIDsByEntry: [UUID: [UUID]] = [:]
        for link in ((try? context.fetch(FetchDescriptor<EntityLink>())) ?? []).filter({ !$0.isDeleted }) {
            guard let entryID = link.entryID, let entityID = link.entityID else { continue }
            let root = directory.root(of: entityID)
            entityIDsByEntry[entryID, default: []].append(root)
        }

        let entries = eligible.map { entry in
            AskContextBuilder.EntryInput(
                id: entry.id,
                date: entry.entryDate,
                title: entry.title,
                text: entry.text,
                entityIDs: Array(Set(entityIDsByEntry[entry.id] ?? []))
            )
        }

        var openLooseEnds: [UUID: [String]] = [:]
        for looseEnd in LooseEnd.all(in: context) where looseEnd.isOpen {
            for root in Set(looseEnd.entityIDs.map(directory.root(of:))) {
                openLooseEnds[root, default: []].append(looseEnd.text)
            }
        }

        let mentioned = Set(entries.flatMap(\.entityIDs))
        let entities = ((try? context.fetch(FetchDescriptor<Entity>())) ?? [])
            .filter { !$0.isDeleted && $0.isBrowsable && mentioned.contains($0.id) }
            .map { entity in
                AskContextBuilder.EntityInput(
                    id: entity.id,
                    name: entity.name,
                    aliases: entity.aliases,
                    bio: entity.bio,
                    openLooseEnds: openLooseEnds[entity.id] ?? []
                )
            }

        return Journal(entries: entries, entities: entities)
    }

    // MARK: - The index

    nonisolated struct Gathered: Sendable {
        var documents: [AskIndex.DocumentInput] = []
        var entities: [AskIndex.Entity] = []
    }

    // Everything the index may hold, which is more than Ask may send. The search panel shows any
    // entry that isn't a draft; Ask sends only what canRunAI allows. One index serves both, and
    // `isSendable` is the difference, so the rule about what leaves the phone still lives here and
    // nowhere else. AskIndex.Query.sendableOnly enforces it on the way out, and blocks(for:) checks
    // again at fetch time in case the index has gone stale.
    static func documents(in context: ModelContext) -> Gathered {
        let entries = ((try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { !$0.isDraft }))) ?? [])
            .filter { !$0.isDeleted }
        let allEntities = ((try? context.fetch(FetchDescriptor<Entity>())) ?? []).filter { !$0.isDeleted }
        let directory = EntityDirectory(in: context)

        // Names and other spellings, by the id a link resolves to, so a renamed or merged entity
        // contributes the words the entries actually used.
        var namesByRoot: [UUID: [String]] = [:]
        var browsableRoots: Set<UUID> = []
        for entity in allEntities {
            let root = directory.root(of: entity.id)
            namesByRoot[root, default: []].append(contentsOf: [entity.name] + entity.aliases)
            if entity.id == root, entity.isBrowsable { browsableRoots.insert(root) }
        }

        var rootsByEntry: [UUID: Set<UUID>] = [:]
        for link in ((try? context.fetch(FetchDescriptor<EntityLink>())) ?? []).filter({ !$0.isDeleted }) {
            guard let entryID = link.entryID, let entityID = link.entityID else { continue }
            rootsByEntry[entryID, default: []].insert(directory.root(of: entityID))
        }

        let documents = entries.map { entry in
            // A hidden entity is the one "don't show me this" control the app has, so its name is
            // not a term an answer can be retrieved by either.
            let roots = (rootsByEntry[entry.id] ?? []).filter(browsableRoots.contains)
            let insights = entry.insights
            return AskIndex.DocumentInput(
                id: entry.id,
                date: entry.entryDate,
                title: entry.title,
                text: entry.text,
                entityIDs: Array(roots),
                entityNames: roots.flatMap { namesByRoot[$0] ?? [] },
                tags: insights?.tags ?? [],
                areas: insights?.areas.map(\.defaultName) ?? [],
                mood: insights?.primaryMood?.rawValue,
                isSendable: InsightsCoordinator.canRunAI(on: entry),
                blockCharacters: AskContextBuilder.blockCharacterEstimate(title: entry.title, text: entry.text)
            )
        }

        let entities = allEntities
            .filter { $0.isBrowsable && directory.root(of: $0.id) == $0.id }
            .map { AskIndex.Entity(id: $0.id, name: $0.name, aliases: $0.aliases, kindRaw: $0.kindRaw, isBrowsable: true) }

        return Gathered(documents: documents, entities: entities)
    }

    // MARK: - What the plan chose

    nonisolated struct Selection: Sendable {
        var entries: [AskContextBuilder.EntryInput] = []
        var entities: [AskContextBuilder.EntityInput] = []
    }

    // The only place entry text is read for a prompt, and a bounded fetch: the plan has already
    // chosen, so this is a dozen entries rather than the journal. Eligibility is checked again here
    // because the index is a snapshot, and an entry can have become a draft, gone back to awaiting
    // text, or been deleted since it was built.
    static func blocks(for plan: AskRetrieval.Plan, in context: ModelContext) -> Selection {
        let wanted = Set(plan.entryIDs)
        guard !wanted.isEmpty || !plan.aboutEntityIDs.isEmpty else { return Selection() }

        let directory = EntityDirectory(in: context)
        let entries = ((try? context.fetch(FetchDescriptor<Entry>())) ?? [])
            .filter { !$0.isDeleted && wanted.contains($0.id) && InsightsCoordinator.canRunAI(on: $0) }
        let eligible = Set(entries.map(\.id))

        var rootsByEntry: [UUID: Set<UUID>] = [:]
        for link in ((try? context.fetch(FetchDescriptor<EntityLink>())) ?? []).filter({ !$0.isDeleted }) {
            guard let entryID = link.entryID, eligible.contains(entryID), let entityID = link.entityID else { continue }
            rootsByEntry[entryID, default: []].insert(directory.root(of: entityID))
        }

        // The plan's order is the ranking, and it survives the fetch, which returns whatever order
        // the store feels like.
        let byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = plan.entryIDs.compactMap { byID[$0] }

        var openLooseEnds: [UUID: [String]] = [:]
        for looseEnd in LooseEnd.all(in: context) where looseEnd.isOpen {
            for root in Set(looseEnd.entityIDs.map(directory.root(of:))) {
                openLooseEnds[root, default: []].append(looseEnd.text)
            }
        }

        let entities = plan.aboutEntityIDs.compactMap { id -> AskContextBuilder.EntityInput? in
            guard let entity = directory.entity(directory.root(of: id)), !entity.isDeleted, entity.isBrowsable else { return nil }
            return AskContextBuilder.EntityInput(
                id: entity.id,
                name: entity.name,
                aliases: entity.aliases,
                bio: entity.bio,
                openLooseEnds: openLooseEnds[entity.id] ?? []
            )
        }

        return Selection(
            entries: ordered.map { entry in
                AskContextBuilder.EntryInput(
                    id: entry.id,
                    date: entry.entryDate,
                    title: entry.title,
                    text: entry.text,
                    entityIDs: Array(rootsByEntry[entry.id] ?? [])
                )
            },
            entities: entities
        )
    }

    // The three example questions the empty state offers, from the journal the user actually has.
    static func examples(in context: ModelContext, limit: Int = 2) -> [String] {
        let recent = ((try? context.fetch(FetchDescriptor<Entity>())) ?? [])
            .filter { !$0.isDeleted && $0.isBrowsable && $0.kind != .tag && $0.lastLinkedAt != nil }
            .sorted { ($0.lastLinkedAt ?? .distantPast) > ($1.lastLinkedAt ?? .distantPast) }
            .prefix(limit)
        return recent.map { "What's been going on with \($0.name)?" } + ["What did I do last week?"]
    }
}
