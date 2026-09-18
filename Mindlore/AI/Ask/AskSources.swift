import Foundation
import SwiftData

// What Ask is allowed to read, gathered once per question. Everything the builder sees comes
// from here, so the rules about what may leave the phone live in one place.
enum AskSources {
    struct Journal {
        var entries: [AskContextBuilder.EntryInput] = []
        var entities: [AskContextBuilder.EntityInput] = []
        // Entries that would have been sent but were written before AI was turned on. Without
        // this a journal full of older entries is indistinguishable from an empty one.
        var heldBackAsOlder = 0
    }

    // `sendableOutsideThePhone` is the OpenAI rule: an entry written before AI was turned on
    // stays here unless the user says otherwise. The on-device path passes false, because
    // nothing it reads leaves the phone, and with AI never on the switch would otherwise leave
    // a local-only Ask with nothing to read.
    static func journal(
        in context: ModelContext,
        appliesAIEnabledAt: Bool,
        aiEnabledAt: Date?,
        includesOlderEntries: Bool
    ) -> Journal {
        let all = ((try? context.fetch(FetchDescriptor<Entry>())) ?? []).filter { !$0.isDeleted }
        let runnable = all.filter(InsightsCoordinator.canRunAI)
        let boundary = appliesAIEnabledAt && !includesOlderEntries ? aiEnabledAt : nil
        let eligible = boundary.map { enabledAt in runnable.filter { $0.createdAt >= enabledAt } } ?? runnable
        let heldBack = runnable.count - eligible.count
        guard !eligible.isEmpty else { return Journal(heldBackAsOlder: heldBack) }

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

        return Journal(entries: entries, entities: entities, heldBackAsOlder: heldBack)
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
