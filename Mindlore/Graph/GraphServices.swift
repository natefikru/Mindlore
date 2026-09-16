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
        self.resolveText = resolveText
        self.automaticBiosUsable = automaticBiosUsable
    }

    // MARK: - Bios

    // An entity page appeared. Drafts once, for the kinds that are named word for word, while
    // automatic insights are on: this sends text, so it follows the same switch.
    func pageOpened(_ entityID: UUID, in context: ModelContext) {
        guard automaticBiosUsable(), drafts[entityID] == nil,
              let entity = editor.entity(withID: entityID, in: context),
              EntityBioDrafter.automaticKinds.contains(entity.kind),
              entity.bio == nil, entity.bioDraftedAt == nil, EntityBioDrafter.mayWrite(entity)
        else { return }
        startDraft(entityID, in: context)
    }

    // The user asked. Works for any kind, and brings back AI for a bio they had cleared.
    func draftBio(_ entityID: UUID, in context: ModelContext) {
        guard drafts[entityID] == nil, let entity = editor.entity(withID: entityID, in: context) else { return }
        if entity.bioEditedByUser && entity.bio == nil {
            entity.bioEditedByUser = false
        }
        guard EntityBioDrafter.mayWrite(entity) else { return }
        startDraft(entityID, in: context)
    }

    // Leaving a page doesn't cancel its draft: the answer is already paid for.
    func cancelDrafts() {
        drafts.values.forEach { $0.cancel() }
    }

    // For tests: waits for a running draft to finish.
    func draftFinished(_ entityID: UUID) async {
        await drafts[entityID]?.value
    }

    private func startDraft(_ entityID: UUID, in context: ModelContext) {
        bioFailures[entityID] = nil
        let generator: ResolvedTextGenerator
        switch resolveText() {
        case .success(let resolved): generator = resolved
        case .failure(let failure):
            bioFailures[entityID] = failure
            return
        }
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
