import Foundation
import SwiftData

// What Ask is allowed to read. Everything that reaches a provider comes from here, so the rules
// about what may leave the phone live in one place: `documents` says what the index may hold and
// which of it is sendable, and `blocks` is the only thing that reads entry text for a prompt.
enum AskSources {
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

        // What describing each entity would cost, so a plan can reserve the room an About block will
        // really take rather than the whole slice. Lengths only: no bio and no loose-end text is
        // carried into the index.
        var aboutCharacters: [UUID: Int] = [:]
        for looseEnd in LooseEnd.all(in: context) where looseEnd.isOpen {
            for root in Set(looseEnd.entityIDs.map(directory.root(of:))).prefix(AskContextBuilder.maxLooseEndsPerEntity) {
                aboutCharacters[root, default: 0] += looseEnd.text.count + 3
            }
        }

        // Only entities a sendable entry actually mentions. An entity reached only through a draft
        // or an entry still awaiting text has a bio and loose ends written from text Ask may not
        // send, and describing it would be a side door around the rule above. A7's review found this
        // once already.
        let mentioned = Set(documents.filter(\.isSendable).flatMap(\.entityIDs))
        let entities = allEntities
            .filter { $0.isBrowsable && directory.root(of: $0.id) == $0.id && mentioned.contains($0.id) }
            .map { entity in
                let names = entity.name.count + entity.aliases.prefix(AskContextBuilder.maxAliasesPerEntity).reduce(0) { $0 + $1.count + 2 }
                return AskIndex.Entity(
                    id: entity.id,
                    name: entity.name,
                    aliases: entity.aliases,
                    kindRaw: entity.kindRaw,
                    isBrowsable: true,
                    aboutCharacters: AskContextBuilder.aboutBlockOverhead + names
                        + (entity.bio?.count ?? 0) + (aboutCharacters[entity.id] ?? 0)
                )
            }

        return Gathered(documents: documents, entities: entities)
    }

    // MARK: - What the plan chose

    nonisolated struct Selection: Sendable {
        var entries: [AskContextBuilder.EntryInput] = []
        var entities: [AskContextBuilder.EntityInput] = []
    }

    // The only place entry text is read for a prompt. It still fetches the tables and filters in
    // memory, the way the rest of this codebase does rather than reaching through a relationship in
    // a predicate, but it runs once per question rather than on every pause in typing, and only the
    // entries the plan chose are read for their text. Eligibility is checked again here
    // because the index is a snapshot, and an entry can have become a draft, gone back to awaiting
    // text, or been deleted since it was built.
    static func blocks(for plan: AskRetrieval.Plan, in context: ModelContext) -> Selection {
        // Digests included: a single line of an entry is still that entry's text leaving the phone,
        // so it is fetched here, under the same eligibility check, and gets no side door.
        let wanted = Set(plan.fetchedEntryIDs)
        guard !wanted.isEmpty || !plan.aboutEntityIDs.isEmpty else { return Selection() }

        let directory = EntityDirectory(in: context)
        let sendable = ((try? context.fetch(FetchDescriptor<Entry>())) ?? [])
            .filter { !$0.isDeleted && InsightsCoordinator.canRunAI(on: $0) }
        let sendableIDs = Set(sendable.map(\.id))
        let entries = sendable.filter { wanted.contains($0.id) }

        // Every sendable entry's links, not just the chosen ones: whether an entity may be described
        // is a question about the journal, not about what happened to fit in this budget.
        var rootsByEntry: [UUID: Set<UUID>] = [:]
        var mentionedBySendable: Set<UUID> = []
        for link in ((try? context.fetch(FetchDescriptor<EntityLink>())) ?? []).filter({ !$0.isDeleted }) {
            guard let entryID = link.entryID, sendableIDs.contains(entryID), let entityID = link.entityID else { continue }
            let root = directory.root(of: entityID)
            rootsByEntry[entryID, default: []].insert(root)
            mentionedBySendable.insert(root)
        }

        // The plan's order is the ranking, and it survives the fetch, which returns whatever order
        // the store feels like.
        let byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = plan.fetchedEntryIDs.compactMap { byID[$0] }

        var openLooseEnds: [UUID: [String]] = [:]
        for looseEnd in LooseEnd.all(in: context) where looseEnd.isOpen {
            for root in Set(looseEnd.entityIDs.map(directory.root(of:))) {
                openLooseEnds[root, default: []].append(looseEnd.text)
            }
        }

        // The same rule documents() applies, applied again for the same reason: an entity whose only
        // mention has become a draft or gone back to awaiting text has a bio and loose ends written
        // out of text Ask may no longer send, and this is exactly the stale window above.
        let entities = plan.aboutEntityIDs.compactMap { id -> AskContextBuilder.EntityInput? in
            let root = directory.root(of: id)
            guard let entity = directory.entity(root), !entity.isDeleted, entity.isBrowsable,
                  mentionedBySendable.contains(root) else { return nil }
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
                    entityIDs: Array(rootsByEntry[entry.id] ?? []),
                    isCreative: entry.isCreative
                )
            },
            entities: entities
        )
    }
}
