import Foundation
import SwiftData

// Which loose ends go with an insights request, and what its answer does to them.
enum LooseEndWriter {
    // At most `limit`: this entry's own earlier loose ends first (so a rerun reuses them), then
    // the ones it settled last time (so a rerun can settle them again: the write reopens them
    // before applying the answer), then open ones from earlier-dated entries, those about
    // someone this entry names first, most recently mentioned first. A later-dated loose end is
    // never offered, so an old page can't settle something that hadn't happened yet.
    static func candidates(for entry: Entry, in context: ModelContext, limit: Int = InsightsPromptBuilder.maxKnownLooseEnds) -> [InsightsPromptBuilder.KnownLooseEnd] {
        let entryID = entry.id
        let all = LooseEnd.all(in: context)
        let own = all.filter { $0.sourceEntryID == entryID }.sorted { $0.createdAt < $1.createdAt }.prefix(5)
        let settledHere = all.filter { $0.resolvedByEntryID == entryID && $0.sourceEntryID != entryID && !$0.userTouched }
            .sorted { $0.createdAt < $1.createdAt }
        let others = all.filter { $0.isOpen && $0.sourceEntryID != entryID && $0.sourceEntryDate < entry.entryDate }
        guard !own.isEmpty || !settledHere.isEmpty || !others.isEmpty else { return [] }

        let entities = EntityDirectory(in: context)
        let named = entities.rootsNamed(in: entry.text, among: Set(others.flatMap(\.entityIDs)))
        let ranked = others.sorted { first, second in
            let firstNamed = first.entityIDs.contains { named.contains(entities.root(of: $0)) }
            let secondNamed = second.entityIDs.contains { named.contains(entities.root(of: $0)) }
            if firstNamed != secondNamed { return firstNamed }
            return first.lastMentionedAt > second.lastMentionedAt
        }
        let known = own.map { InsightsPromptBuilder.KnownLooseEnd(id: $0.id, text: $0.text, own: true) }
            + (settledHere + ranked).map { InsightsPromptBuilder.KnownLooseEnd(id: $0.id, text: $0.text, own: false) }
        return Array(known.prefix(limit))
    }

    struct Outcome: Equatable {
        var created = 0
        var createdFaded = 0
        var mentioned = 0
        var resolved = 0
    }

    // Runs inside the insights write, after the graph has indexed the entry, before the save.
    // Every loose end is fetched again by id: the request took a while, and the user may have
    // closed or deleted one meanwhile. Their call stands.
    @discardableResult
    static func apply(_ result: LooseEndResult, to entry: Entry, in context: ModelContext, now: Date = .now) -> Outcome {
        let entryID = entry.id
        let entryDate = entry.entryDate
        LooseEnd.rollback(forEntryID: entryID, .regenerating(keeping: Set(result.mentioned)), in: context)

        var outcome = Outcome()
        let about = AboutResolver(entryID: entryID, in: context)
        for id in result.mentioned {
            guard let looseEnd = LooseEnd.fetch(id, in: context) else { continue }
            looseEnd.lastMentionedAt = max(looseEnd.lastMentionedAt, entryDate)
            outcome.mentioned += 1
        }
        for id in result.resolved {
            guard let looseEnd = LooseEnd.fetch(id, in: context), looseEnd.isOpen, !looseEnd.userTouched,
                  looseEnd.sourceEntryID != entryID, looseEnd.sourceEntryDate < entryDate else { continue }
            looseEnd.setStatus(.resolved, at: now, resolvedBy: entryID)
            looseEnd.lastMentionedAt = max(looseEnd.lastMentionedAt, entryDate)
            outcome.resolved += 1
        }
        for new in result.new.prefix(InsightsPromptBuilder.maxNewLooseEnds) {
            let looseEnd = LooseEnd(text: new.text, sourceEntryID: entryID, sourceEntryDate: entryDate, entityIDs: about.ids(for: new.about), dueDate: new.due)
            context.insert(looseEnd)
            outcome.created += 1
            if LooseEnd.shouldFade(looseEnd, now: now) {
                looseEnd.setStatus(.faded, at: now)
                outcome.createdFaded += 1
            }
        }
        return outcome
    }
}

// Names from the answer's `about`, matched against what this entry's own links say.
private struct AboutResolver {
    private var idsByName: [String: UUID] = [:]

    init(entryID: UUID, in context: ModelContext) {
        let links = ((try? context.fetch(FetchDescriptor<EntityLink>(predicate: #Predicate { $0.entryID == entryID }))) ?? [])
            .filter { !$0.isDeleted }
        let directory = EntityDirectory(in: context)
        for link in links {
            guard let entityID = link.entityID else { continue }
            var names = [link.surface]
            if let written = link.writtenSurface { names.append(written) }
            if let entity = directory.entity(entityID) { names += [entity.name] + entity.aliases }
            for name in names {
                let key = Self.key(name)
                if !key.isEmpty, idsByName[key] == nil { idsByName[key] = entityID }
            }
        }
    }

    func ids(for names: [String]) -> [UUID] {
        var result: [UUID] = []
        for name in names {
            if let id = idsByName[Self.key(name)], !result.contains(id) { result.append(id) }
        }
        return result
    }

    private static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
