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

    @ObservationIgnored private let resolve: () -> Result<Generator, AIJobFailure>
    @ObservationIgnored private let sections: () -> InsightSections
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
    @ObservationIgnored private var isProcessing = false
    @ObservationIgnored private var needsAnotherPass = false

    init(
        resolve: @escaping () -> Result<Generator, AIJobFailure>,
        sections: @escaping () -> InsightSections,
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
        guard !isProcessing else {
            needsAnotherPass = true
            return
        }
        isProcessing = true
        defer { isProcessing = false }

        repeat {
            needsAnotherPass = false
            let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.insightsPending }, sortBy: [SortDescriptor(\.createdAt)])
            for entry in (try? context.fetch(descriptor)) ?? [] {
                let manual = manualRuns.contains(entry.id)
                // Insights may run while the entry is open: they never change its text, and a finished
                // entry's text is final by the user's choice. Cleanup still waits for the entry to close.
                guard manual || !failedThisSession.contains(entry.id) else { continue }
                guard manual || (AIJobPolicy.canRunAutomatically(.insights, entry) && !pausedForOffline) else { continue }
                await generate(entry.persistentModelID, context: context)
            }
        } while needsAnotherPass
    }

    // Creates, retries, or replaces insights for one entry, whatever its history.
    func runAI(for entry: Entry, context: ModelContext) async {
        guard !isRunning(entry), Self.canRunAI(on: entry) else { return }
        // The automatic pass exists so each entry is analyzed once without asking. Asking counts, or
        // closing the entry afterwards would pay for the same analysis again.
        entry.automaticAIPassUsed = true
        AIJobPolicy.manualReset(.insights, entry)
        failedThisSession.remove(entry.id)
        manualRuns.insert(entry.id)
        try? save(context, [entry.persistentModelID])
        diagnostics.record("insights.requested", ["id": .id(entry.id), "trigger": "runAI"])
        await processQueue(context: context)
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
        let trigger = manualRuns.remove(entryID) != nil ? "runAI" : "automatic"
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
        let vocabulary = self.vocabulary(context, sections)
            ?? .init(tags: sections.tags ? Self.topTags(in: context) : [])
        let plan = InsightsPromptBuilder.plan(text: analyzedText, source: source, sections: sections, vocabulary: vocabulary, model: generator.model)

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
            "knownThemes": .int(plan.vocabularySent.themes.count),
            "knownNames": .int(plan.vocabularySent.named.count),
        ])

        let result: InsightsResult
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

        guard let current = Self.fetch(id, in: context), current.contentRevision == revision else {
            diagnostics.record("insights.discarded", ["id": .id(entryID), "reason": "restarted"])
            return
        }

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
        insights.setMoods(primary: result.primaryMood, secondary: result.secondaryMoods, editedByUser: false)
        insights.themes = result.themes
        insights.tags = result.tags
        insights.mentions = result.mentions
        insights.openThreads = result.openThreads
        insights.cleanedText = result.cleanedText
        insights.cleanedTextSkippedReasonRaw = plan.cleanedTextSkippedReason
        insights.customResults = result.custom
        insights.sentTagCount = plan.vocabularySent.tags.count
        insights.sentThemeCount = plan.vocabularySent.themes.count
        insights.sentNameCount = plan.vocabularySent.named.count
        AIJobPolicy.recordSuccess(.insights, current)

        // Suggestions and cleanup only act on the exact text that was analyzed.
        let isCurrent = TextHash.of(current.text) == analyzedHash
        var changedEntry = false
        if isCurrent {
            // A suggestion only offers a date; it isn't an edit until accepted, by the user or by the setting.
            if let writtenDate = result.writtenDate, current.storeSuggestedEntryDate(writtenDate, calendar: calendar) {
                if autoApplyEntryDate() {
                    current.acceptSuggestedEntryDate(calendar: calendar)
                    changedEntry = true
                    diagnostics.record("entryDate.changed", ["id": .id(entryID), "reason": "auto", "source": "insights"])
                } else {
                    diagnostics.record("entryDate.suggested", ["id": .id(entryID), "source": "insights"])
                }
            }
            if let cleaned = result.cleanedText, autoApplyCleanedText(), !presence.isOpen(entryID) {
                if current.applyCleanedText(cleaned) {
                    changedEntry = true
                    diagnostics.record("cleanup.applied", ["id": .id(entryID), "trigger": "automatic"])
                }
            }
        }
        onInsightsWritten(current, context)
        // Writing insights or a suggestion isn't an edit to the entry; applying cleanup is.
        try? save(context, changedEntry ? [] : [id])
        diagnostics.record(isCurrent ? "insights.completed" : "insights.stale", [
            "id": .id(entryID),
            "trigger": .string(trigger),
            "sectionsReturned": .int(result.sectionsReturned),
            "tags": .int(result.tags.count),
            "mentions": .int(result.mentions.count),
            "inputTokens": .int(usage.inputTokens ?? -1),
            "outputTokens": .int(usage.outputTokens ?? -1),
        ])
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
