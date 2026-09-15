import Foundation
import Observation
import SwiftData

// Generates insights for entries flagged by the automatic pass or Run AI, one entry at a time.
@Observable
final class InsightsCoordinator {
    struct Generator {
        let generator: any TextGenerator
        let model: String
        let label: String
    }

    private(set) var running: Set<UUID> = []

    @ObservationIgnored private let resolve: () -> Result<Generator, AIJobFailure>
    @ObservationIgnored private let sections: () -> InsightSections
    @ObservationIgnored private let autoApplyCleanedText: () -> Bool
    @ObservationIgnored private let presence: EditorPresence
    @ObservationIgnored private let save: (ModelContext, Set<PersistentIdentifier>) throws -> Void
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
        presence: EditorPresence,
        save: @escaping (ModelContext, Set<PersistentIdentifier>) throws -> Void = { try $0.saveStampingEntries(except: $1) },
        diagnostics: DiagnosticsLog = .shared,
        calendar: Calendar = .current
    ) {
        self.resolve = resolve
        self.sections = sections
        self.autoApplyCleanedText = autoApplyCleanedText
        self.presence = presence
        self.save = save
        self.diagnostics = diagnostics
        self.calendar = calendar
    }

    // Run AI needs text that is final: not still being transcribed and not waiting for page review.
    static func canRunAI(on entry: Entry) -> Bool {
        !entry.awaitingText && !entry.textReviewPending && !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                guard !presence.isOpen(entry.id), manual || !failedThisSession.contains(entry.id) else { continue }
                guard manual || AIJobPolicy.canRunAutomatically(.insights, entry) else { continue }
                await generate(entry.persistentModelID, context: context)
            }
        } while needsAnotherPass
    }

    // Creates, retries, or replaces insights for one entry, whatever its history.
    func runAI(for entry: Entry, context: ModelContext) async {
        guard !isRunning(entry), Self.canRunAI(on: entry) else { return }
        AIJobPolicy.manualReset(.insights, entry)
        failedThisSession.remove(entry.id)
        manualRuns.insert(entry.id)
        try? save(context, [entry.persistentModelID])
        diagnostics.record("insights.requested", ["id": .id(entry.id), "trigger": "runAI"])
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
        let plan = InsightsPromptBuilder.plan(text: analyzedText, source: source, sections: sections, existingTags: Self.topTags(in: context), model: generator.model)

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
        ])

        let result: InsightsResult
        let usage: TextResult
        do {
            usage = try await generator.generator.generate(plan.request)
            result = try InsightsPromptBuilder.parse(usage.text, plan: plan, calendar: calendar)
        } catch {
            let failure = AIJobFailure(any: error)
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
        insights.appliedTextHash = nil
        insights.summary = result.summary
        insights.primaryMoodRaw = result.primaryMood?.rawValue
        insights.secondaryMoodsRaw = result.secondaryMoods.map(\.rawValue)
        insights.themes = result.themes
        insights.tags = result.tags
        insights.mentions = result.mentions
        insights.openThreads = result.openThreads
        insights.cleanedText = result.cleanedText
        insights.cleanedTextSkippedReasonRaw = plan.cleanedTextSkippedReason
        insights.customResults = result.custom
        AIJobPolicy.recordSuccess(.insights, current)

        // Suggestions and cleanup only act on the exact text that was analyzed.
        let isCurrent = TextHash.of(current.text) == analyzedHash
        var changedEntry = false
        if isCurrent {
            // A suggestion only offers a date; it isn't an edit until the user accepts it.
            if let writtenDate = result.writtenDate, current.storeSuggestedEntryDate(writtenDate, calendar: calendar) {
                diagnostics.record("entryDate.suggested", ["id": .id(entryID), "source": "insights"])
            }
            if let cleaned = result.cleanedText, autoApplyCleanedText(), !presence.isOpen(entryID) {
                if current.applyCleanedText(cleaned) {
                    changedEntry = true
                    diagnostics.record("cleanup.applied", ["id": .id(entryID), "trigger": "automatic"])
                }
            }
        }
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
