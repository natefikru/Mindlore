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
    @ObservationIgnored private var drafts: [UUID: Task<Void, Never>] = [:]

    init(
        diagnostics: DiagnosticsLog = .shared,
        resolveText: @escaping () -> Result<ResolvedTextGenerator, AIJobFailure> = { .failure(AIJobFailure(raw: "settings.aiOff")) },
        automaticBiosUsable: @escaping () -> Bool = { false }
    ) {
        indexer = GraphIndexer(diagnostics: diagnostics)
        editor = GraphEditor(diagnostics: diagnostics)
        drafter = EntityBioDrafter(diagnostics: diagnostics)
        self.diagnostics = diagnostics
        self.resolveText = resolveText
        self.automaticBiosUsable = automaticBiosUsable
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

    @discardableResult
    func rename(_ entityID: UUID, to name: String, keepingOldNameAsAlias: Bool = false, force: Bool = false, in context: ModelContext) -> GraphEditor.EditOutcome {
        edit(entityID, in: context) { editor.rename($0, to: name, keepingOldNameAsAlias: keepingOldNameAsAlias, force: force, in: context) }
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
                entity = existing
            } else {
                entity = Entity(name: trimmed, key: EntityNormalizer.key(for: trimmed, kind: mention.kind), kind: mention.kind)
            }
        }
        guard link.entityID != entity.id || addingAlias else { return .applied(entity.id) }
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
                .init(surface: link.surface, kind: link.kind, entityID: $0, inferred: link.inferred, entityHidden: hidden.contains($0))
            }
        })
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
            let outcome = await drafter.draft(entityID: entityID, using: generator, in: context)
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

    // The counters are dated by the entry, so moving one moves them.
    func entryDateChanged(in context: ModelContext) {
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
