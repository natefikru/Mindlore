import Foundation
import SwiftData
import Observation

// The one graph object the app shares. RootView builds it once and puts it in the environment,
// so views and coordinators use the same indexer, editor, and log instead of building their own.
//
// `revision` moves after every change the graph makes on a view's behalf; screens that show
// entities use it as their refresh key.
@MainActor
@Observable
final class GraphServices {
    let indexer: GraphIndexer
    let editor: GraphEditor
    let drafter: EntityBioDrafter
    let diagnostics: DiagnosticsLog
    private(set) var revision = 0

    // Bio drafts in flight, and what the last attempt for an entity came to this session.
    private(set) var drafting: Set<UUID> = []
    private(set) var bioFailures: [UUID: AIJobFailure] = [:]
    // Nothing in the entries the provider has seen names these; no request was sent.
    private(set) var withoutExcerpts: Set<UUID> = []

    @ObservationIgnored private let resolveText: () -> Result<ResolvedTextGenerator, AIJobFailure>
    @ObservationIgnored private let automaticBiosUsable: () -> Bool
    @ObservationIgnored private let promptVoice: () -> PromptVoice
    @ObservationIgnored private var drafts: [UUID: Task<Void, Never>] = [:]

    init(
        diagnostics: DiagnosticsLog = .shared,
        resolveText: @escaping () -> Result<ResolvedTextGenerator, AIJobFailure> = { .failure(AIJobFailure(raw: "settings.aiOff")) },
        automaticBiosUsable: @escaping () -> Bool = { false },
        promptVoice: @escaping () -> PromptVoice = { .default }
    ) {
        indexer = GraphIndexer(diagnostics: diagnostics)
        editor = GraphEditor(diagnostics: diagnostics)
        drafter = EntityBioDrafter(diagnostics: diagnostics)
        self.diagnostics = diagnostics
        self.resolveText = resolveText
        self.automaticBiosUsable = automaticBiosUsable
        self.promptVoice = promptVoice
    }

    // MARK: - Edits from a page
    //
    // Callers flush EntrySaver first, so no entry has unsaved edits of its own and a plain save
    // can't stamp one by accident.

    func setBio(_ bio: String?, on entityID: UUID, in context: ModelContext) {
        edit(entityID, in: context) {
            editor.setBio(bio, on: $0)
            return .applied
        }
    }

    // Not through `edit`: a rename also fixes the name in the app's own sentences, and rewriting
    // an entry's summary or title marks that entry changed without it being an edit the user
    // made. Those entries are exempted so their updatedAt stays where it is.
    @discardableResult
    func rename(_ entityID: UUID, to name: String, force: Bool = false, in context: ModelContext) -> GraphEditor.EditOutcome {
        guard let entity = editor.entity(withID: entityID, in: context) else { return .applied }
        let result = editor.rename(entity, to: name, force: force, in: context)
        guard result.outcome == .applied else { return result.outcome }

        let exempt = result.touchedEntryIDs.isEmpty ? [] : Set(
            ((try? context.fetch(FetchDescriptor<Entry>())) ?? [])
                .filter { result.touchedEntryIDs.contains($0.id) }
                .map(\.persistentModelID)
        )
        do {
            try context.saveStampingEntries(except: exempt)
        } catch {
            diagnostics.record("graph.saveFailed", ["error": .errorCode(error)])
        }
        revision += 1
        return .applied
    }

    @discardableResult
    func linkContact(_ entityID: UUID, identifier: String, in context: ModelContext) -> GraphEditor.EditOutcome {
        edit(entityID, in: context) { editor.linkContact($0, identifier: identifier, in: context) }
    }

    @discardableResult
    func unlinkContact(_ entityID: UUID, in context: ModelContext) -> GraphEditor.EditOutcome {
        edit(entityID, in: context) { editor.unlinkContact($0, in: context) }
    }

    @discardableResult
    func linkPlace(_ entityID: UUID, identifier: String?, coordinate: PlaceCoordinate, in context: ModelContext) -> GraphEditor.EditOutcome {
        edit(entityID, in: context) { editor.linkPlace($0, identifier: identifier, coordinate: coordinate, in: context) }
    }

    @discardableResult
    func unlinkPlace(_ entityID: UUID, in context: ModelContext) -> GraphEditor.EditOutcome {
        edit(entityID, in: context) { editor.unlinkPlace($0, in: context) }
    }

    // What a rename would rewrite, for the sheet's warning before it happens.
    func renamePreview(_ entityID: UUID, in context: ModelContext) -> EntityProseRewriter.Counts {
        guard let entity = editor.entity(withID: entityID, in: context) else { return .init() }
        return editor.renamePreview(entity, in: context)
    }

    @discardableResult
    func setKind(_ kind: EntityKind, on entityID: UUID, in context: ModelContext) -> GraphEditor.EditOutcome {
        edit(entityID, in: context) { editor.setKind(kind, on: $0, in: context) }
    }

    @discardableResult
    func addAlias(_ alias: String, to entityID: UUID, force: Bool = false, in context: ModelContext) -> GraphEditor.EditOutcome {
        edit(entityID, in: context) { editor.addAlias(alias, to: $0, force: force, in: context) }
    }

    func removeAlias(_ alias: String, from entityID: UUID, in context: ModelContext) {
        edit(entityID, in: context) {
            editor.removeAlias(alias, from: $0)
            return .applied
        }
    }

    func setHidden(_ hidden: Bool, on entityID: UUID, in context: ModelContext) {
        edit(entityID, in: context) {
            editor.setHidden(hidden, on: $0)
            return .applied
        }
    }

    func setResurfacingMuted(_ muted: Bool, on entityID: UUID, in context: ModelContext) {
        edit(entityID, in: context) {
            editor.setResurfacingMuted(muted, on: $0)
            return .applied
        }
    }

    // Returns the entity the merged one now stands for, which is where its page should go.
    @discardableResult
    func merge(_ loserID: UUID, into targetID: UUID, in context: ModelContext) -> UUID? {
        guard let loser = editor.entity(withID: loserID, in: context),
              let target = editor.entity(withID: targetID, in: context),
              editor.merge(loser, into: target, in: context) == .merged
        else { return nil }
        revision += 1
        return loser.mergedIntoID
    }

    func unmerge(_ loserID: UUID, in context: ModelContext) {
        guard let loser = editor.entity(withID: loserID, in: context), editor.unmerge(loser, in: context) else { return }
        revision += 1
    }

    // The Review list's "Not the same": takes two entities out of each other's suggestions for
    // good, since `EntityMatcher` would otherwise keep finding the same pair.
    func markNotSame(_ oneID: UUID, _ otherID: UUID, in context: ModelContext) {
        guard let one = editor.entity(withID: oneID, in: context), let other = editor.entity(withID: otherID, in: context) else { return }
        editor.markNotSame(one, as: other)
        save(context)
    }

    // The Review list's "Which one?": links the resolver couldn't tell apart between two or
    // more live, unhidden candidates (5c.4). Each candidate id is resolved through `root(of:)`
    // in case it was merged since the tie was recorded, and a link left with one or zero live
    // candidates that way is quietly cleared, since the tie already answered itself.
    struct UnsureMention: Identifiable {
        struct Candidate: Identifiable {
            let id: UUID
            let name: String
        }
        let mention: MentionRef
        let candidates: [Candidate]
        var id: MentionRef { mention }
    }

    func unsureLinks(in context: ModelContext) -> [UnsureMention] {
        let links = indexer.allLinks(in: context).filter { !$0.unsureAmong.isEmpty }
        guard !links.isEmpty else { return [] }
        var result: [UnsureMention] = []
        var resolvedAutomatically = false
        for link in links {
            guard let entryID = link.entryID else { continue }
            var seen: Set<UUID> = []
            var candidates: [UnsureMention.Candidate] = []
            for id in link.unsureAmong {
                guard let found = editor.entity(withID: id, in: context) else { continue }
                let root = editor.root(of: found, in: context)
                guard !root.hidden, seen.insert(root.id).inserted else { continue }
                candidates.append(.init(id: root.id, name: root.name))
            }
            if candidates.count > 1 {
                result.append(UnsureMention(mention: MentionRef(entryID: entryID, surface: link.surface, kind: link.kind), candidates: candidates))
            } else {
                // A tie down to exactly one visible candidate is a real answer, not just an
                // empty list to clear: without actually repointing, the link stays wherever it
                // was left (possibly a now-hidden loser filtered out above) and, with
                // unsureAmong now empty, "Which one?" never offers to fix it again.
                if let onlyCandidate = candidates.first, link.entityID != onlyCandidate.id,
                   let target = editor.entity(withID: onlyCandidate.id, in: context) {
                    editor.repoint(link, to: target, addingAlias: false, in: context)
                }
                link.unsureAmong = []
                resolvedAutomatically = true
            }
        }
        if resolvedAutomatically { try? context.save() }
        return result
    }

    // "This is someone else", for one mention. The mention is found again by what it says,
    // because Generate again may have replaced the link since the sheet opened.
    enum RepointTarget: Equatable {
        case existing(UUID)
        case new(name: String)
    }

    enum RepointOutcome: Equatable {
        case applied(UUID)
        // Moved, but a third entity already answers to the name: probably the same one.
        case aliasCollides(entityID: UUID, with: UUID)
        // Moved, and the entity it came from keeps the name for its other mentions. The user
        // just said these are different, so this is never a merge offer.
        case aliasStaysWith(entityID: UUID, owner: UUID)
        case mentionChanged
    }

    func repoint(_ mention: MentionRef, to target: RepointTarget, addingAlias: Bool, in context: ModelContext) -> RepointOutcome {
        guard let link = indexer.allLinks(in: context).first(where: {
            $0.entryID == mention.entryID && $0.surface == mention.surface && $0.kind == mention.kind
        }) else { return .mentionChanged }

        let entity: Entity
        switch target {
        case .existing(let id):
            guard let found = editor.entity(withID: id, in: context) else { return .mentionChanged }
            entity = editor.root(of: found, in: context)
        case .new(let name):
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return .mentionChanged }
            if let existing = editor.entity(answering: trimmed, kind: mention.kind, in: context) {
                // Typing a name that happens to key-match a hidden entity means that is who the
                // user means, the same reasoning merge already applies to its winner: chosen by
                // name is not something left out of sight any more.
                if existing.hidden { editor.setHidden(false, on: existing) }
                entity = existing
            } else {
                entity = Entity(name: trimmed, key: EntityNormalizer.key(for: trimmed, kind: mention.kind), kind: mention.kind)
            }
        }
        // Already pointing there isn't a no-op when the link was unsure (5c.4): the user just
        // confirmed the resolver's own guess, and that still needs to clear unsureAmong and mark
        // the link theirs, or "Which one?" keeps asking about a mention that's already answered.
        guard link.entityID != entity.id || addingAlias || !link.unsureAmong.isEmpty else { return .applied(entity.id) }
        let previous = link.entityID

        let outcome = editor.repoint(link, to: entity, addingAlias: addingAlias, in: context)
        revision += 1
        switch outcome {
        case .applied: return .applied(entity.id)
        case .collides(let other) where other == previous: return .aliasStaysWith(entityID: entity.id, owner: other)
        case .collides(let other): return .aliasCollides(entityID: entity.id, with: other)
        }
    }

    private func edit(_ entityID: UUID, in context: ModelContext, _ change: (Entity) -> GraphEditor.EditOutcome) -> GraphEditor.EditOutcome {
        guard let entity = editor.entity(withID: entityID, in: context) else { return .applied }
        let outcome = change(entity)
        if outcome == .applied { save(context) }
        return outcome
    }

    private func save(_ context: ModelContext) {
        do {
            try context.saveStampingEntries()
        } catch {
            diagnostics.record("graph.saveFailed", ["error": .errorCode(error)])
        }
        revision += 1
    }

    // MARK: - Chips

    // This entry's links by id, one fetch filtered in memory, never through the relationship.
    func chipIndex(for entryID: UUID, in context: ModelContext) -> EntityChipIndex {
        let links = indexer.allLinks(in: context).filter { $0.entryID == entryID }
        let entityIDs = Set(links.compactMap(\.entityID))
        guard !entityIDs.isEmpty else { return .empty }
        let hidden = Set(((try? context.fetch(FetchDescriptor<Entity>(predicate: #Predicate { entityIDs.contains($0.id) }))) ?? [])
            .filter(\.hidden).map(\.id))
        return EntityChipIndex(links: links.compactMap { link in
            link.entityID.map {
                .init(surface: link.surface, kind: link.kind, entityID: $0, inferred: link.inferred, entityHidden: hidden.contains($0), unsure: !link.unsureAmong.isEmpty)
            }
        })
    }

    // MARK: - The picture

    typealias GraphData = MindMap.Graph

    // One Entity fetch, one link fetch, one Entry fetch, with merges and hidden entities resolved
    // through the same in-memory root(of:) walk mentionedWith uses (left as its own method, since
    // its "touching id, sorted, capped" step is a different shape). Everything the map draws is
    // built from this with MindMap's pure builders.
    private func buildSnapshot(in context: ModelContext) -> MindMapSnapshot {
        snapshotBuildCount += 1
        let entities = ((try? context.fetch(FetchDescriptor<Entity>())) ?? []).filter { !$0.isDeleted }
        let byID = Dictionary(uniqueKeysWithValues: entities.map { ($0.id, $0) })

        func root(of id: UUID) -> Entity? {
            guard var current = byID[id] else { return nil }
            var seen: Set<UUID> = [current.id]
            while let nextID = current.mergedIntoID, let next = byID[nextID], seen.insert(next.id).inserted {
                current = next
            }
            return current
        }

        let links = indexer.allLinks(in: context)
        let entryIDs = Set(links.compactMap(\.entryID))
        let entries = Dictionary(
            (((try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { entryIDs.contains($0.id) }))) ?? [])
                .filter { !$0.isDeleted }
                .map { entry in
                    (entry.id, MindMapSnapshot.EntryInfo(
                        id: entry.id,
                        date: entry.entryDate,
                        areas: entry.insights?.areas ?? [],
                        mood: entry.insights?.primaryMood?.category
                    ))
                }),
            uniquingKeysWith: { first, _ in first }
        )

        let inputs: [EntityGraph.LinkInput] = links.compactMap { link in
            guard let linkEntityID = link.entityID, let entryID = link.entryID,
                  let entry = entries[entryID],
                  let root = root(of: linkEntityID), root.isBrowsable
            else { return nil }
            return .init(entryID: entryID, entityID: root.id, entryDate: entry.date)
        }

        let browsable = Dictionary(uniqueKeysWithValues: entities.filter(\.isBrowsable).map {
            ($0.id, MindMapSnapshot.EntityInfo(id: $0.id, name: $0.name, kind: $0.kind))
        })
        return MindMapSnapshot(entities: browsable, links: inputs, entries: entries)
    }

    // Kept per revision: the map asks on every refresh, and what it draws only moves when
    // insights, moods, or the graph change, which all bump the revision.
    func mapSnapshot(in context: ModelContext) -> MindMapSnapshot {
        if let cached = snapshotCache, cached.revision == revision { return cached.snapshot }
        let snapshot = buildSnapshot(in: context)
        snapshotCache = (revision, snapshot)
        return snapshot
    }

    @ObservationIgnored private var snapshotCache: (revision: Int, snapshot: MindMapSnapshot)?
    // How many times the store was read for the map, for tests.
    @ObservationIgnored private(set) var snapshotBuildCount = 0

    // Every browsable entity as of a date. Always reads the store fresh (callers outside Mind
    // don't bump the revision between their own writes).
    func globalGraph(asOf: Date = .now, kinds: Set<EntityKind>?, minimumLinkCount: Int, in context: ModelContext) -> GraphData {
        MindMap.graph(buildSnapshot(in: context), kinds: kinds, minimumLinkCount: minimumLinkCount, asOf: asOf)
    }

    // Each browsable entity's life area on the map, so a merged entity counts the entries it
    // absorbed.
    func primaryAreas(asOf: Date = .now, in context: ModelContext) -> [UUID: LifeArea] {
        MindMap.primaryAreas(mapSnapshot(in: context), asOf: asOf)
    }

    // The launch sweep writes links without going through here; the map has to hear about it.
    func sweepFinished() {
        revision += 1
    }

    // A mood picked by hand changes what "Mood around" shows.
    func moodsEdited() {
        revision += 1
    }

    // MARK: - Mind

    enum ReviewAnswer: Equatable {
        case same, notSame, skip
        case whichOne(UUID)

        var logName: String {
            switch self {
            case .same: "same"
            case .notSame: "notSame"
            case .skip: "skip"
            case .whichOne: "whichOne"
            }
        }
    }

    // One tap on Mind's review card. "Same" merges the first into the second, as the old review
    // list did; skipping writes nothing. Callers flush EntrySaver first.
    func answer(_ question: ReviewQueue.Question, with answer: ReviewAnswer, in context: ModelContext) {
        switch (question, answer) {
        case (.same(let a, let b), .same):
            guard merge(a, into: b, in: context) != nil else { return }
        case (.same(let a, let b), .notSame):
            markNotSame(a, b, in: context)
        case (.whichOne(let unsure), .whichOne(let id)):
            guard repoint(unsure.mention, to: .existing(id), addingAlias: false, in: context) != .mentionChanged else { return }
        case (_, .skip):
            break
        default:
            return
        }
        diagnostics.record("mind.reviewAnswered", ["kind": .string(answer.logName)])
    }

    enum FocusSource: String {
        case node, search, crumb, showInMind
    }

    func recordMindFocused(source: FocusSource, onMap: Bool) {
        diagnostics.record("mind.focused", ["source": .string(source.rawValue), "onMap": .bool(onMap)])
    }

    func recordMindFiltersChanged(kinds: Int, minimum: Int, entries: Bool, regions: Bool, nodes: Int) {
        diagnostics.record("mind.filtersChanged", [
            "kinds": .int(kinds),
            "minimum": .int(minimum),
            "entries": .bool(entries),
            "regions": .bool(regions),
            "nodes": .int(nodes),
        ])
    }

    func recordMindReplayed(steps: Int, durationMilliseconds: Double, stepP95Milliseconds: Double?, finished: Bool, nodes: Int) {
        var fields: [String: DiagnosticValue] = [
            "steps": .int(steps),
            "durationMilliseconds": .double(durationMilliseconds),
            "finished": .bool(finished),
            "nodes": .int(nodes),
        ]
        if let stepP95Milliseconds { fields["stepP95Milliseconds"] = .double(stepP95Milliseconds) }
        diagnostics.record("mind.replayed", fields)
    }

    func recordMindEntryOpened() {
        diagnostics.record("mind.entryOpened", [:])
    }

    func recordMindLensChanged(_ lens: String) {
        diagnostics.record("mind.lensChanged", ["lens": .string(lens)])
    }

    // Logged once per graph screen appearance, never per frame: the first settle after the
    // screen appeared, and frame-interval and draw-work percentiles over up to 5 seconds of
    // interaction, which is what the Phase A device gate reads.
    func recordGraphRendered(_ stats: GraphRenderStats) {
        var fields: [String: DiagnosticValue] = [
            "nodes": .int(stats.nodes),
            "edges": .int(stats.edges),
            "frameSamples": .int(stats.frameSamples),
            "entryNodes": .int(stats.entryNodes),
            "lens": .string(stats.lens.rawValue),
            "replay": .bool(stats.replay),
        ]
        let optional: [(String, Double?)] = [
            ("settleMilliseconds", stats.settleMilliseconds),
            ("frameP50Milliseconds", stats.frameP50Milliseconds),
            ("frameP95Milliseconds", stats.frameP95Milliseconds),
            ("workP95Milliseconds", stats.workP95Milliseconds),
        ]
        for (key, value) in optional {
            if let value { fields[key] = .double(value) }
        }
        diagnostics.record("graph.rendered", fields)
    }

    // MARK: - Co-occurrence

    struct CoOccurrence: Identifiable {
        let id: UUID
        let name: String
        let kind: EntityKind
        let weight: Double
    }

    // "Mentioned with" on an entity page. Resolves merges and hidden entities against one
    // in-memory map of every entity, never per-link, since this reads every link in the store:
    // a `root(of:)`/`entity(withID:)` call per link would be a fetch per link, the way `recount`
    // avoids by fetching each table exactly once.
    func mentionedWith(of entityID: UUID, in context: ModelContext, limit: Int = 8) -> [CoOccurrence] {
        let entities = ((try? context.fetch(FetchDescriptor<Entity>())) ?? []).filter { !$0.isDeleted }
        let byID = Dictionary(uniqueKeysWithValues: entities.map { ($0.id, $0) })

        func root(of id: UUID) -> Entity? {
            guard var current = byID[id] else { return nil }
            var seen: Set<UUID> = [current.id]
            while let nextID = current.mergedIntoID, let next = byID[nextID], seen.insert(next.id).inserted {
                current = next
            }
            return current
        }

        guard let subjectRoot = root(of: entityID), subjectRoot.isBrowsable else { return [] }

        let links = indexer.allLinks(in: context)
        let entryIDs = Set(links.compactMap(\.entryID))
        guard !entryIDs.isEmpty else { return [] }
        let entryDates = Dictionary(uniqueKeysWithValues:
            (((try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { entryIDs.contains($0.id) }))) ?? [])
                .filter { !$0.isDeleted }
                .map { ($0.id, $0.entryDate) }))

        let inputs: [EntityGraph.LinkInput] = links.compactMap { link in
            guard let linkEntityID = link.entityID, let entryID = link.entryID,
                  let entryDate = entryDates[entryID],
                  let root = root(of: linkEntityID), root.isBrowsable
            else { return nil }
            return .init(entryID: entryID, entityID: root.id, entryDate: entryDate)
        }

        let edges = EntityGraph.build(links: inputs)
        let touching = edges.compactMap { edge -> (UUID, Double)? in
            if edge.a == subjectRoot.id { return (edge.b, edge.weight) }
            if edge.b == subjectRoot.id { return (edge.a, edge.weight) }
            return nil
        }

        return touching
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .compactMap { id, weight in byID[id].map { CoOccurrence(id: $0.id, name: $0.name, kind: $0.kind, weight: weight) } }
    }

    // MARK: - Bios

    // An entity page appeared. Drafts once, for the kinds that are named word for word, while
    // automatic insights are on: this sends text, so it follows the same switch.
    func pageOpened(_ entityID: UUID, in context: ModelContext) {
        // A failure that retrying can't fix waits for the user's Try again.
        if let failure = bioFailures[entityID], !failure.isRetryable { return }
        guard automaticBiosUsable(), drafts[entityID] == nil,
              let entity = editor.entity(withID: entityID, in: context),
              EntityBioDrafter.automaticKinds.contains(entity.kind),
              entity.bio == nil, entity.bioDraftedAt == nil, EntityBioDrafter.mayWrite(entity),
              let generator = resolveGenerator(for: entityID)
        else { return }
        startDraft(entityID, using: generator, in: context)
    }

    // The user asked. Works for any kind, and brings back AI for a bio they had cleared.
    func draftBio(_ entityID: UUID, in context: ModelContext) {
        guard drafts[entityID] == nil, let entity = editor.entity(withID: entityID, in: context), !entity.isMerged else { return }
        let bringingBack = entity.bioEditedByUser && entity.bio == nil
        guard bringingBack || EntityBioDrafter.mayWrite(entity) else { return }
        // The flag only changes once a request can actually go out.
        guard let generator = resolveGenerator(for: entityID) else { return }
        if bringingBack { entity.bioEditedByUser = false }
        startDraft(entityID, using: generator, in: context)
    }

    // Leaving a page doesn't cancel its draft: the answer is already paid for, and the app
    // never cancels one. This exists so tests can reach the drafter's cancellation path.
    func cancelDrafts() {
        drafts.values.forEach { $0.cancel() }
    }

    // For tests: waits for a running draft to finish.
    func draftFinished(_ entityID: UUID) async {
        await drafts[entityID]?.value
    }

    private func resolveGenerator(for entityID: UUID) -> ResolvedTextGenerator? {
        switch resolveText() {
        case .success(let resolved):
            bioFailures[entityID] = nil
            return resolved
        case .failure(let failure):
            bioFailures[entityID] = failure
            return nil
        }
    }

    private func startDraft(_ entityID: UUID, using generator: ResolvedTextGenerator, in context: ModelContext) {
        drafting.insert(entityID)
        drafts[entityID] = Task {
            let outcome = await drafter.draft(entityID: entityID, using: generator, voice: promptVoice(), in: context)
            switch outcome {
            case .failed(let failure): bioFailures[entityID] = failure
            case .noExcerpts: withoutExcerpts.insert(entityID)
            case .drafted, .notEnough: withoutExcerpts.remove(entityID)
            case .skipped, .cancelled: break
            }
            if outcome == .drafted || outcome == .notEnough { revision += 1 }
            drafting.remove(entityID)
            drafts[entityID] = nil
        }
    }

    // Call after the deletion is saved, so the cascade has taken the entries' links with it.
    // Whatever nobody mentions any more goes too.
    func entriesDeleted(in context: ModelContext) {
        indexer.recount(in: context)
        revision += 1
    }

    func insightsDeleted(for entry: Entry, in context: ModelContext) {
        entry.removeInsights(in: context)
        indexer.recount(in: context)
        revision += 1
    }

    // The counters and the entry's loose ends are dated by the entry, so moving one moves them.
    func entryDateChanged(for entry: Entry, in context: ModelContext) {
        LooseEnd.redate(forEntry: entry, in: context)
        indexer.recount(in: context)
        revision += 1
    }

    // After an insights run wrote this entry. The coordinator saves afterwards, and the bump
    // lets an open sheet pick up the new links.
    func insightsWritten(for entry: Entry, in context: ModelContext) {
        indexer.index(entry, in: context)
        indexer.recount(in: context)
        revision += 1
    }
}
