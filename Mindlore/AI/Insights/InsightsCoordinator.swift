import Foundation
import Observation
import SwiftData

// Generates insights for entries flagged by the automatic pass or Run AI, one entry at a time.
@Observable
final class InsightsCoordinator {
    typealias Generator = ResolvedTextGenerator

    private(set) var running: Set<UUID> = []
    // Set by an offline failure so a queue of entries doesn't fire one doomed request each.
    private(set) var pausedForOffline = false
    // Redo insights on every entry (owner, 2026-09-23): how far the run has got, nil when none is
    // running. Lives only as long as the app: the entries' own pending flags are the queue, so a run
    // cut short by a kill still finishes at the next launch, just without the count on screen.
    private(set) var redo: RedoProgress?
    // Voice entries whose cleanup arrived while their editor was open, with "Format voice notes
    // automatically" on. Changing the text under an open editor could land on a caret or a
    // half-typed word, so it is held and applied once the entry closes, and the editor hides its
    // Review offer meanwhile: nobody is asked about a cleanup that is going to apply itself.
    // Memory only: if the app dies first, the cleanup is still in the insights as an offer.
    private(set) var heldCleanups: Set<UUID> = []

    struct RedoProgress: Equatable {
        var total: Int
        var done: Int
    }

    @ObservationIgnored private let resolve: () -> Result<Generator, AIJobFailure>
    @ObservationIgnored private let sections: () -> InsightSections
    @ObservationIgnored private let promptVoice: () -> PromptVoice
    @ObservationIgnored private let autoApplyCleanedText: () -> Bool
    @ObservationIgnored private let autoApplyEntryDate: () -> Bool
    @ObservationIgnored private let presence: EditorPresence
    @ObservationIgnored private let save: (ModelContext, Set<PersistentIdentifier>) throws -> Void
    // Runs after insights are written and before they are saved, so the graph's links go to
    // disk in the same save and the entry is never stamped for work that isn't an edit.
    @ObservationIgnored private let onInsightsWritten: (Entry, ModelContext) -> Void
    // What the journal already calls things, sent with the request so the model reuses the
    // user's own words. Nil until the graph has been built.
    @ObservationIgnored private let vocabulary: (ModelContext, InsightSections) -> InsightsPromptBuilder.JournalVocabulary?
    @ObservationIgnored private let diagnostics: DiagnosticsLog
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private var failedThisSession: Set<UUID> = []
    @ObservationIgnored private var manualRuns: Set<UUID> = []
    @ObservationIgnored private var redoIDs: Set<UUID> = []
    @ObservationIgnored private var isProcessing = false
    @ObservationIgnored private var needsAnotherPass = false

    init(
        resolve: @escaping () -> Result<Generator, AIJobFailure>,
        sections: @escaping () -> InsightSections,
        promptVoice: @escaping () -> PromptVoice = { .default },
        autoApplyCleanedText: @escaping () -> Bool,
        autoApplyEntryDate: @escaping () -> Bool = { false },
        presence: EditorPresence,
        save: @escaping (ModelContext, Set<PersistentIdentifier>) throws -> Void = { try $0.saveStampingEntries(except: $1) },
        onInsightsWritten: @escaping (Entry, ModelContext) -> Void = { _, _ in },
        vocabulary: @escaping (ModelContext, InsightSections) -> InsightsPromptBuilder.JournalVocabulary? = { _, _ in nil },
        diagnostics: DiagnosticsLog = .shared,
        calendar: Calendar = .current
    ) {
        self.resolve = resolve
        self.sections = sections
        self.promptVoice = promptVoice
        self.autoApplyCleanedText = autoApplyCleanedText
        self.autoApplyEntryDate = autoApplyEntryDate
        self.presence = presence
        self.save = save
        self.onInsightsWritten = onInsightsWritten
        self.vocabulary = vocabulary
        self.diagnostics = diagnostics
        self.calendar = calendar
    }

    // Run AI needs text that is final: not still being transcribed and not waiting for page review.
    // Drafts wait for Done: analyzing half-written text costs the user money for a partial entry.
    static func canRunAI(on entry: Entry) -> Bool {
        !entry.isDraft && !entry.awaitingText && !entry.textReviewPending && !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (entry.source != .photo || entry.pagesConfirmed)
    }

    func isRunning(_ entry: Entry) -> Bool {
        running.contains(entry.id)
    }

    func processQueue(context: ModelContext) async {
        // Before the busy check: a close fires this while a long queue may still be running.
        applyHeldCleanups(context: context)
        guard !isProcessing else {
            needsAnotherPass = true
            return
        }
        isProcessing = true
        defer { isProcessing = false }

        repeat {
            needsAnotherPass = false
            // Journal order, so an entry is analyzed after the ones it follows.
            let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.insightsPending }, sortBy: [SortDescriptor(\.entryDate)])
            for entry in (try? context.fetch(descriptor)) ?? [] {
                let manual = manualRuns.contains(entry.id)
                // Insights may run while the entry is open: they never change its text, and a finished
                // entry's text is final by the user's choice. Cleanup still waits for the entry to close.
                guard manual || !failedThisSession.contains(entry.id) else { continue }
                guard manual || (AIJobPolicy.canRunAutomatically(.insights, entry) && !pausedForOffline) else { continue }
                // Only the phone that made an entry runs its jobs by itself (`LocalOrigin`). The
                // pending flag syncs, so another phone's entry can arrive already asking.
                guard manual || LocalOrigin.isLocal(entry) else { continue }
                let redoing = redoIDs.contains(entry.id)
                // A redo is hundreds of manual runs; offline, each would fail at once, so they wait
                // for the network like automatic work does.
                if redoing && pausedForOffline { continue }
                let id = entry.persistentModelID
                await generate(id, context: context)
                // Done when it finished, failed for good, or had nothing to ask; only an offline
                // failure keeps it for when the network is back.
                if redoing, !(pausedForOffline && Self.fetch(id, in: context)?.insightsPending == true) {
                    finishRedo(entry.id)
                }
            }
        } while needsAnotherPass
        settleRedo(context: context)
    }

    // A redo entry that will never come up again (deleted before its turn, or no longer pending
    // for any other reason) is finished here, or the count would never reach its total and a new
    // redo could never start. One kept for the network stays pending and stays counted.
    private func settleRedo(context: ModelContext) {
        guard !redoIDs.isEmpty else { return }
        let pending = Set(((try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.insightsPending }))) ?? []).map(\.id))
        for id in redoIDs where !running.contains(id) && !pending.contains(id) {
            manualRuns.remove(id)
            finishRedo(id)
        }
    }

    // Creates, retries, or replaces insights for one entry, whatever its history.
    func runAI(for entry: Entry, context: ModelContext) async {
        guard !isRunning(entry), Self.canRunAI(on: entry) else { return }
        // So tapping Run AI with nothing to ask doesn't spend the entry's automatic pass on a request
        // `generate` will refuse to send. It asks the builder itself rather than
        // `InsightSections.isEmpty`, which is wrong for this in both directions: isEmpty ignores the
        // written date, so it blocked a typed entry with only "suggest entry dates" on (a valid
        // one-field request), and it counts cleanup, which a typed entry is never offered. An empty
        // vocabulary gives the same answer as the real one: vocabulary only ever adds a field inside
        // a section that is already on.
        let probe = InsightsPromptBuilder.plan(text: entry.text, source: entry.source, sections: sections(), vocabulary: .empty, model: "")
        guard !probe.asksForNothing else { return }
        // The automatic pass exists so each entry is analyzed once without asking. Asking counts, or
        // closing the entry afterwards would pay for the same analysis again.
        entry.automaticAIPassUsed = true
        AIJobPolicy.manualReset(.insights, entry)
        LocalOrigin.claim(entry)
        failedThisSession.remove(entry.id)
        manualRuns.insert(entry.id)
        try? save(context, [entry.persistentModelID])
        diagnostics.record("insights.requested", ["id": .id(entry.id), "trigger": "runAI"])
        await processQueue(context: context)
    }

    // Every entry Run AI would accept, queued oldest first and run one at a time through the same
    // queue. Each gets the reset Run AI gives one entry. Moods the user picked by hand survive,
    // because redoing a whole journal must not quietly undo every correction in it.
    func redoAll(context: ModelContext) async {
        guard redo == nil else { return }
        let descriptor = FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.entryDate)])
        let entries = ((try? context.fetch(descriptor)) ?? []).filter(Self.canRunAI)
        guard !entries.isEmpty else { return }
        for entry in entries {
            entry.automaticAIPassUsed = true
            AIJobPolicy.manualReset(.insights, entry)
            LocalOrigin.claim(entry)
            failedThisSession.remove(entry.id)
            manualRuns.insert(entry.id)
            redoIDs.insert(entry.id)
        }
        redo = RedoProgress(total: entries.count, done: 0)
        try? save(context, Set(entries.map(\.persistentModelID)))
        diagnostics.record("insights.redoAll", ["count": .int(entries.count)])
        await processQueue(context: context)
    }

    // Stop takes back what hasn't started. The entry being analyzed finishes.
    func stopRedo(context: ModelContext) {
        guard let progress = redo else { return }
        let waiting = redoIDs.subtracting(running)
        var changed: Set<PersistentIdentifier> = []
        for entry in ((try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.insightsPending }))) ?? []) where waiting.contains(entry.id) {
            entry.insightsPending = false
            manualRuns.remove(entry.id)
            changed.insert(entry.persistentModelID)
        }
        try? save(context, changed)
        redoIDs.subtract(waiting)
        diagnostics.record("insights.redoStopped", ["done": .int(progress.done), "total": .int(progress.total)])
        if redoIDs.isEmpty { redo = nil }
    }

    private func finishRedo(_ id: UUID) {
        guard redoIDs.remove(id) != nil else { return }
        redo?.done += 1
        if redoIDs.isEmpty { redo = nil }
    }

    // Work that stopped because the phone was offline picks up as soon as the network is back,
    // without waiting for the next launch. Stored failures still gate what may run.
    func networkBecameAvailable(context: ModelContext) async {
        guard pausedForOffline || !failedThisSession.isEmpty else { return }
        pausedForOffline = false
        failedThisSession = []
        await processQueue(context: context)
    }

    private func generate(_ id: PersistentIdentifier, context: ModelContext) async {
        guard let entry = Self.fetch(id, in: context), entry.insightsPending else { return }
        let entryID = entry.id
        let redoing = redoIDs.contains(entryID)
        let trigger = redoing ? "redoAll" : (manualRuns.remove(entryID) != nil ? "runAI" : "automatic")
        if redoing { manualRuns.remove(entryID) }
        guard Self.canRunAI(on: entry) else {
            // Text went away or back into review since the flag was set; nothing to analyze.
            AIJobPolicy.recordSuccess(.insights, entry)
            try? save(context, [id])
            return
        }

        let generator: Generator
        switch resolve() {
        case .success(let resolved):
            generator = resolved
        case .failure(let failure):
            AIJobPolicy.recordFailure(.insights, entry, failure)
            failedThisSession.insert(entryID)
            try? save(context, [id])
            diagnostics.record("insights.unavailable", ["id": .id(entryID), "error": .string(failure.raw)])
            return
        }

        let sections = sections()
        let source = entry.source
        let analyzedText = entry.text
        let analyzedHash = TextHash.of(analyzedText)
        let revision = entry.contentRevision
        // Before the graph exists there are no entities to read, so tags are counted off the
        // insights themselves. Once it exists, an empty list means the user hid them all.
        var vocabulary = self.vocabulary(context, sections)
            ?? .init(tags: sections.tags ? Self.topTags(in: context) : [])
        if sections.looseEnds {
            vocabulary.looseEnds = LooseEndWriter.candidates(for: entry, in: context)
        }
        let plan = InsightsPromptBuilder.plan(text: analyzedText, source: source, sections: sections, vocabulary: vocabulary, model: generator.model, entryDate: entry.entryDate, voice: promptVoice(), calendar: calendar, budget: generator.onDevice ? .onDevice : .cloud)

        // Every section turned off asks for an empty schema, which the provider rejects. This is the
        // one place that can tell: which sections reach the schema depends on the entry, so a
        // typed entry with only "clean up transcriptions" on asks for nothing while a voice entry
        // with the same settings asks for something. `insightsPending` stays set rather than being
        // cleared like the canRunAI miss above, so turning a section back on runs the entry instead
        // of silently skipping it forever. No attempt is counted: nothing was sent.
        guard !plan.asksForNothing else {
            diagnostics.record("insights.skipped", ["id": .id(entryID), "reason": "emptySchema", "source": .string(source.rawValue)])
            return
        }

        AIJobPolicy.recordAttempt(.insights, entry)
        try? save(context, [id])
        running.insert(entryID)
        defer { running.remove(entryID) }
        diagnostics.record("insights.started", [
            "id": .id(entryID),
            "trigger": .string(trigger),
            "source": .string(source.rawValue),
            "model": .string(generator.label),
            "attempt": .int(entry.insightsAttempts),
            "customPrompts": .int(plan.customKeys.count),
            "knownTags": .int(plan.vocabularySent.tags.count),
            "knownNames": .int(plan.vocabularySent.named.count),
            "knownLooseEnds": .int(plan.vocabularySent.looseEnds.count),
        ])

        var result: InsightsResult
        let usage: TextResult
        do {
            usage = try await generator.generator.generate(plan.request)
            result = try InsightsPromptBuilder.parse(usage.text, plan: plan, calendar: calendar)
        } catch {
            let failure = AIJobFailure(any: error)
            if failure.isOffline {
                if !pausedForOffline { diagnostics.record("ai.offline", ["capability": "insights"]) }
                pausedForOffline = true
            }
            if let current = Self.fetch(id, in: context) {
                AIJobPolicy.recordFailure(.insights, current, failure)
                try? save(context, [id])
            }
            failedThisSession.insert(entryID)
            diagnostics.record("insights.failed", ["id": .id(entryID), "error": .string(failure.raw)])
            return
        }

        // On device the model's own verdict is not trusted: prose is never creative, and text laid
        // out like verse is asked about on its own. Failing that question means life.
        var focused: Bool?
        if generator.onDevice, CreativeSignals.looksLikeVerse(analyzedText) {
            let answer = try? await generator.generator.generate(CreativeSignals.focusedRequest(for: analyzedText))
            focused = answer.flatMap { CreativeSignals.parseFocused($0.text) }
        }
        result.kind = CreativeSignals.decideKind(modelSays: result.kind, text: analyzedText, onDevice: generator.onDevice, focused: focused)

        guard let current = Self.fetch(id, in: context), current.contentRevision == revision else {
            diagnostics.record("insights.discarded", ["id": .id(entryID), "reason": "restarted"])
            return
        }

        // Creative work keeps its title, tags, and a line saying what the piece is. Its names,
        // area, loose ends, and mood are not facts about the author's life: a sad poem is not a
        // sad week in Reflect (owner, 2026-09-22). A note keeps everything but its mood: a list
        // carries no feeling worth charting. The user's own call wins over the model's.
        if !current.creativeSetByUser { current.kind = result.kind }
        result.restrict(to: current.kind)

        let insights = current.insights ?? {
            let created = EntryInsights()
            context.insert(created)
            created.entry = current
            return created
        }()
        insights.generatedAt = .now
        insights.modelUsed = generator.label
        insights.sourceTextHash = analyzedHash
        insights.summary = result.summary
        if !(redoing && insights.moodsEditedByUser) {
            insights.setMoods(primary: result.primaryMood, secondary: result.secondaryMoods, editedByUser: false)
        }
        insights.areas = result.areas
        insights.tags = result.tags
        insights.mentions = result.mentions
        insights.cleanedText = result.cleanedText
        insights.cleanedTextSkippedReasonRaw = plan.cleanedTextSkippedReason
        insights.sections = result.sections
        insights.customResults = result.custom
        insights.thinkingPatterns = result.thinking
        insights.sentTagCount = plan.vocabularySent.tags.count
        insights.sentNameCount = plan.vocabularySent.named.count
        insights.sentLooseEndCount = plan.vocabularySent.looseEnds.filter { !$0.own }.count
        AIJobPolicy.recordSuccess(.insights, current)

        // Suggestions and cleanup only act on the exact text that was analyzed.
        let isCurrent = TextHash.of(current.text) == analyzedHash
        var changedEntry = false
        if isCurrent {
            // A suggestion only offers a date; it isn't an edit until accepted, by the user or by the
            // setting. A photographed page is the exception: the date written at its top is the day
            // it was written, so it becomes the entry's date on its own (owner, 2026-09-23), but
            // only while the entry has no picked day. A day the user or the page already set is
            // never moved by a rerun; a different reading is only offered.
            if let writtenDate = result.writtenDate, current.storeSuggestedEntryDate(writtenDate, calendar: calendar) {
                if autoApplyEntryDate() || (source == .photo && !current.entryDateIsDayOnly) {
                    current.acceptSuggestedEntryDate(calendar: calendar)
                    changedEntry = true
                    diagnostics.record("entryDate.changed", ["id": .id(entryID), "reason": "auto", "source": "insights"])
                } else {
                    diagnostics.record("entryDate.suggested", ["id": .id(entryID), "source": "insights"])
                }
            }
            // Only a voice entry the user hasn't typed into, through the same apply the Review
            // sheet's button calls. The insights stay current: `isCurrent` accepts the cleaned
            // text by `cleanupAppliedHash`, and nothing here flags another pass.
            if result.cleanedText != nil, autoApplyCleanedText(), current.cleanupAppliesAutomatically {
                if presence.isOpen(entryID) {
                    heldCleanups.insert(entryID)
                    diagnostics.record("cleanup.held", ["id": .id(entryID)])
                } else if current.applyCleanedTextAutomatically() {
                    changedEntry = true
                    diagnostics.record("cleanup.applied", ["id": .id(entryID), "trigger": "automatic"])
                }
            }
        }
        onInsightsWritten(current, context)
        if sections.looseEnds {
            let outcome = LooseEndWriter.apply(result.looseEnds, to: current, in: context)
            diagnostics.record("looseEnds.written", [
                "id": .id(entryID),
                "created": .int(outcome.created),
                "createdFaded": .int(outcome.createdFaded),
                "mentioned": .int(outcome.mentioned),
                "resolved": .int(outcome.resolved),
            ])
        }
        // Writing insights or a suggestion isn't an edit to the entry; applying cleanup is.
        try? save(context, changedEntry ? [] : [id])
        diagnostics.record(isCurrent ? "insights.completed" : "insights.stale", [
            "id": .id(entryID),
            "trigger": .string(trigger),
            "sectionsReturned": .int(result.sectionsReturned),
            "tags": .int(result.tags.count),
            "mentions": .int(result.mentions.count),
            "parts": .int(result.sections.count),
            "kind": .string(current.kind.rawValue),
            "inputTokens": .int(usage.inputTokens ?? -1),
            "outputTokens": .int(usage.outputTokens ?? -1),
        ])
    }

    func holdsCleanup(for id: UUID) -> Bool {
        heldCleanups.contains(id)
    }

    // A held cleanup goes in once its editor has closed, if everything that allowed it still
    // holds: the setting, an untouched voice entry, and text that is still exactly what the
    // cleanup was made from. Anything else drops it back to an ordinary offer.
    private func applyHeldCleanups(context: ModelContext) {
        for entryID in heldCleanups where !presence.isOpen(entryID) {
            heldCleanups.remove(entryID)
            guard autoApplyCleanedText() else { continue }
            var descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == entryID })
            descriptor.fetchLimit = 1
            guard let entry = try? context.fetch(descriptor).first, entry.applyCleanedTextAutomatically() else { continue }
            // Applying cleanup is an edit, so the entry is stamped like any other.
            try? save(context, [])
            diagnostics.record("cleanup.applied", ["id": .id(entryID), "trigger": "automatic", "held": true])
        }
    }

    // The journal's most used tags, so new entries reuse them instead of near-duplicates.
    static func topTags(in context: ModelContext, limit: Int = InsightsPromptBuilder.maxExistingTags) -> [String] {
        var counts: [String: Int] = [:]
        for insights in (try? context.fetch(FetchDescriptor<EntryInsights>())) ?? [] {
            for tag in insights.tags {
                counts[tag, default: 0] += 1
            }
        }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(limit).map(\.key)
    }

    private static func fetch(_ id: PersistentIdentifier, in context: ModelContext) -> Entry? {
        var descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.persistentModelID == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
