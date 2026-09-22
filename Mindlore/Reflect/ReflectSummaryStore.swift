import Foundation
import SwiftData

// Generate, cache, read back. Both the launch sweep and a lazy view-triggered generation call
// generateIfNeeded; when to ask again is decided here, not by two callers agreeing separately
// (tasks/reflect-queue-spec.md). A month is written once. A week is written as soon as it has
// entries, even while it is still running, and rewritten whenever its entries change, until a
// summary has been written after the week ended: that one is final (owner, 2026-09-22). A failed
// generation writes nothing, keeps whatever was there, and is retried next launch or next view.
//
// `resolve` is injected the same way InsightsCoordinator takes its generator: production callers
// pass `{ AIServices.askGenerator(settings: settings, accounts: accounts) }`, and a test passes a
// closure returning a fake provider directly, with no network or Keychain involved.
@MainActor
enum ReflectSummaryStore {
    // Guards the launch sweep and a lazily-triggered row against racing to generate the same
    // period: both check the cache before either writes, so a completed week that's both the
    // sweep's target and already on screen at launch could otherwise fire two real requests for
    // itself. A caller that finds a period already generating awaits that result instead of
    // starting a second one.
    private static var inFlight: [String: Task<ReflectSummary?, Never>] = [:]

    // The newest row for a period. There is deliberately no uniqueness constraint (the CloudKit
    // rule every model here follows), so a caller that somehow finds two rows for the same period
    // reads the newest by generatedAt; generateIfNeeded deletes the rows it replaces, which is what keeps a second
    // one from being written in the first place.
    static func summary(kind: ReflectSummaryKind, periodStart: Date, in context: ModelContext) -> ReflectSummary? {
        let kindRaw = kind.rawValue
        let descriptor = FetchDescriptor<ReflectSummary>(
            predicate: #Predicate { $0.periodKindRaw == kindRaw && $0.periodStart == periodStart }
        )
        return ((try? context.fetch(descriptor)) ?? []).max { $0.generatedAt < $1.generatedAt }
    }

    // What a week's summary is written from, reduced to a hash: the eligible entries' ids, titles,
    // and text. Stamps and AI saves don't move it, so only a real change to the week asks again.
    nonisolated static func fingerprint(_ entries: [ReflectFidelity.WeekEntry]) -> String {
        TextHash.of(entries.map { "\($0.id.uuidString)\u{1F}\($0.title)\u{1F}\($0.text)" }.joined(separator: "\u{1E}"))
    }

    // Whether a cached summary still stands. A week's stands if nothing it was written from has
    // changed, or if it was written after the week was over, which is when a week is done.
    nonisolated static func isCurrent(_ summary: ReflectSummary, interval: DateInterval, fingerprint: String?) -> Bool {
        guard summary.kind == .week, let fingerprint else { return true }
        return summary.generatedAt >= interval.end || summary.sourceFingerprint == fingerprint
    }

    @discardableResult
    static func generateIfNeeded(
        kind: ReflectSummaryKind,
        interval: DateInterval,
        resolve: @escaping () -> Result<AskProvider, AIJobFailure>,
        voice: PromptVoice,
        calendar: Calendar = .current,
        in context: ModelContext
    ) async -> ReflectSummary? {
        let existing = summary(kind: kind, periodStart: interval.start, in: context)
        let fingerprint = kind == .week ? Self.fingerprint(ReflectSource.weekEntries(in: interval, context: context)) : nil
        if let existing, isCurrent(existing, interval: interval, fingerprint: fingerprint) { return existing }

        let key = "\(kind.rawValue):\(interval.start.timeIntervalSince1970)"
        if let running = inFlight[key] {
            return await running.value
        }
        let task = Task<ReflectSummary?, Never> {
            await generate(kind: kind, interval: interval, resolve: resolve, voice: voice, calendar: calendar, in: context)
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        // A rewrite that fails leaves the older summary standing rather than an empty week.
        return await task.value ?? existing
    }

    private static func generate(
        kind: ReflectSummaryKind,
        interval: DateInterval,
        resolve: () -> Result<AskProvider, AIJobFailure>,
        voice: PromptVoice,
        calendar: Calendar,
        in context: ModelContext
    ) async -> ReflectSummary? {
        let items: [ReflectQueueItem]?
        var fingerprint: String?
        switch kind {
        case .week:
            let entries = ReflectSource.weekEntries(in: interval, context: context)
            fingerprint = Self.fingerprint(entries)
            if entries.isEmpty {
                items = []
            } else {
                guard case .success(let provider) = resolve() else { return nil }
                items = await ReflectQueueGenerator.generate(
                    kind: .week,
                    title: ReflectFidelity.title(kind: .week, interval: interval, calendar: calendar),
                    prompt: ReflectFidelity.weekPrompt(entries, characterLimit: ReflectQueueGenerator.promptLimit(for: provider)),
                    provider: provider,
                    voice: voice
                )
            }
        case .month:
            let entryCount = ReflectSource.monthPrompt(interval: interval, calendar: calendar, context: context).entryCount
            if entryCount == 0 {
                items = []
            } else {
                guard case .success(let provider) = resolve() else { return nil }
                let limit = ReflectQueueGenerator.promptLimit(for: provider)
                let prompt = ReflectSource.monthPrompt(interval: interval, characterLimit: limit, calendar: calendar, context: context).prompt
                items = await ReflectQueueGenerator.generate(
                    kind: .month,
                    title: ReflectFidelity.title(kind: .month, interval: interval, calendar: calendar),
                    prompt: prompt,
                    provider: provider,
                    voice: voice
                )
            }
        }

        guard let items else { return nil }
        // The rows it replaces go, so a week rewritten all through its seven days leaves one row.
        let kindRaw = kind.rawValue
        let start = interval.start
        let older = (try? context.fetch(FetchDescriptor<ReflectSummary>(predicate: #Predicate { $0.periodKindRaw == kindRaw && $0.periodStart == start }))) ?? []
        older.forEach(context.delete)
        let created = ReflectSummary(kind: kind, periodStart: interval.start, generatedAt: .now, items: items, sourceFingerprint: fingerprint)
        context.insert(created)
        try? context.saveStampingEntries()
        return created
    }

    // The launch sweep's own scope: only the week and the month that most recently closed.
    // Nothing older is swept here (a launch isn't the place to backfill a year of history); the
    // lazy path in the feed covers everything else.
    static func sweepMostRecentlyCompleted(
        resolve: @escaping () -> Result<AskProvider, AIJobFailure>,
        voice: PromptVoice,
        now: Date = .now,
        calendar: Calendar = .current,
        in context: ModelContext
    ) async {
        if let week = mostRecentlyCompleted(.weekOfYear, now: now, calendar: calendar) {
            await generateIfNeeded(kind: .week, interval: week, resolve: resolve, voice: voice, calendar: calendar, in: context)
        }
        if let month = mostRecentlyCompleted(.month, now: now, calendar: calendar) {
            await generateIfNeeded(kind: .month, interval: month, resolve: resolve, voice: voice, calendar: calendar, in: context)
        }
    }

    private static func mostRecentlyCompleted(_ component: Calendar.Component, now: Date, calendar: Calendar) -> DateInterval? {
        guard let anchor = calendar.date(byAdding: component, value: -1, to: now) else { return nil }
        return calendar.dateInterval(of: component, for: anchor)
    }
}
