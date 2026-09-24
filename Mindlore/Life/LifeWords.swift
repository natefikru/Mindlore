import Foundation
import SwiftData

// Where Life's generated words live and when they are asked for. They are `ReflectSummary` rows
// under kinds of their own, the table Reflect already syncs and exports for generated text, so no
// model changes and nothing new for CloudKit's schema:
//
// - `life.area.<area>.<window>`: an area's paragraph and up to two quotes. Rewritten when the
//   area's entries change, at most once a week, since a paragraph that moves with every entry
//   reads as noise.
// - `life.portrait`: one per calendar month, kept, so an earlier one can be read again.
// - `life.feedback`: every "That's right" and "Not quite" the author gave a portrait line, with
//   their note, sent with the next portrait.
//
// Every request goes through `AIServices.askGenerator`, like Reflect's summaries, and only entries
// `InsightsCoordinator.canRunAI` accepts are sent.
@MainActor
enum LifeWords {
    static let portraitKind = "life.portrait"
    static let feedbackKind = "life.feedback"
    static let areaRewriteInterval: TimeInterval = 7 * 86_400

    static func areaKind(_ area: LifeArea, _ window: MindWindow) -> String {
        "life.area.\(area.rawValue).\(window.rawValue)"
    }

    private static var inFlight: [String: Task<ReflectSummary?, Never>] = [:]

    static func rows(_ kind: String, in context: ModelContext) -> [ReflectSummary] {
        let descriptor = FetchDescriptor<ReflectSummary>(predicate: #Predicate { $0.periodKindRaw == kind })
        return ((try? context.fetch(descriptor)) ?? []).filter { !$0.isDeleted }.sorted { $0.generatedAt > $1.generatedAt }
    }

    // MARK: - Eligible entries

    static func entries(ids: [UUID], in context: ModelContext) -> [LifePrompts.Entry] {
        let wanted = Set(ids)
        guard !wanted.isEmpty else { return [] }
        return ((try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { !$0.isDraft }))) ?? [])
            .filter { wanted.contains($0.id) && !$0.isDeleted && InsightsCoordinator.canRunAI(on: $0) }
            .map { LifePrompts.Entry(id: $0.id, date: $0.entryDate, title: $0.title, text: $0.text, isCreative: $0.isCreative, isNote: $0.isNote) }
    }

    nonisolated static func fingerprint(_ entries: [LifePrompts.Entry]) -> String {
        TextHash.of(entries.sorted { $0.id.uuidString < $1.id.uuidString }.map { "\($0.id.uuidString)\u{1F}\($0.title)\u{1F}\($0.text)" }.joined(separator: "\u{1E}"))
    }

    // MARK: - An area

    struct AreaWordsView: Equatable {
        let paragraph: String
        let quotes: [LifePrompts.Quote]
        let generatedAt: Date
    }

    static func areaWords(_ area: LifeArea, _ window: MindWindow, in context: ModelContext) -> AreaWordsView? {
        guard let row = rows(areaKind(area, window), in: context).first else { return nil }
        return view(of: row)
    }

    private static func view(of row: ReflectSummary) -> AreaWordsView? {
        let items = row.items
        guard let paragraph = items.first(where: { $0.title == "paragraph" })?.body, !paragraph.isEmpty else { return nil }
        // Held to today's length rule, so a quote cached before it doesn't show.
        let quotes = items.filter { $0.title == "quote" && $0.body.split(separator: " ").count <= LifePrompts.maxQuoteWords }.compactMap { item in
            item.entryIDs?.first.map { LifePrompts.Quote(entryID: $0, text: item.body) }
        }
        return AreaWordsView(paragraph: paragraph, quotes: quotes, generatedAt: row.generatedAt)
    }

    // Whether a cached paragraph stands: written from the same entries, or less than a week old.
    nonisolated static func areaIsCurrent(generatedAt: Date, fingerprint: String?, current: String, now: Date) -> Bool {
        fingerprint == current || now.timeIntervalSince(generatedAt) < areaRewriteInterval
    }

    @discardableResult
    static func writeAreaIfNeeded(
        _ area: LifeArea,
        window: MindWindow,
        name: String,
        entryIDs: [UUID],
        resolve: @escaping () -> Result<AskProvider, AIJobFailure>,
        now: Date = .now,
        in context: ModelContext,
        diagnostics: DiagnosticsLog = .shared
    ) async -> AreaWordsView? {
        let kind = areaKind(area, window)
        let entries = entries(ids: entryIDs, in: context)
        let existing = rows(kind, in: context).first
        let print = fingerprint(entries)
        if let existing, areaIsCurrent(generatedAt: existing.generatedAt, fingerprint: existing.sourceFingerprint, current: print, now: now) {
            return view(of: existing)
        }
        guard entries.count >= 3 else { return existing.flatMap(view(of:)) }
        if let running = inFlight[kind] { return await running.value.flatMap(view(of:)) }
        let task = Task<ReflectSummary?, Never> {
            // OpenAI only, like the portrait: on the phone's model the paragraph came back in the
            // author's own first person and its quotes ran to paragraphs.
            guard case .success(let provider) = resolve(), provider.kind == .openAI else { return nil }
            let onDevice = false
            let planned = LifePrompts.areaRequest(area: name, windowPhrase: LifeCopy.windowPhrase(window), entries: entries, model: provider.model, onDevice: onDevice)
            let started = Date.now
            do {
                let result = try await provider.generator.generate(planned.request)
                guard let words = LifePrompts.parseArea(result.text, handles: planned.handles, onDevice: onDevice) else {
                    record("life.areaWords", success: false, started: started, fields: ["unreadable": .bool(true)], diagnostics: diagnostics)
                    return nil
                }
                record("life.areaWords", success: true, started: started, fields: ["quotes": .int(words.quotes.count), "entries": .int(planned.handles.count), "provider": .string(provider.kind.rawValue)], diagnostics: diagnostics)
                var items = [ReflectQueueItem(id: "paragraph", source: .generated, title: "paragraph", body: words.paragraph, prompt: "")]
                items += words.quotes.enumerated().map { index, quote in
                    ReflectQueueItem(id: "quote:\(index)", source: .generated, title: "quote", body: quote.text, prompt: "", entryIDs: [quote.entryID])
                }
                return replace(kind: kind, periodStart: .distantPast, items: items, fingerprint: print, in: context)
            } catch {
                record("life.areaWords", success: false, started: started, fields: ["error": .errorCode(error)], diagnostics: diagnostics)
                return nil
            }
        }
        inFlight[kind] = task
        defer { inFlight[kind] = nil }
        return (await task.value ?? existing).flatMap(view(of:))
    }

    // MARK: - The portrait

    struct PortraitView: Equatable, Identifiable {
        let id: UUID
        let month: Date
        let generatedAt: Date
        let lines: [LifePrompts.Line]
        let concern: Bool
    }

    static func portraits(in context: ModelContext) -> [PortraitView] {
        rows(portraitKind, in: context).map { row in
            let lines = row.items.compactMap { item -> LifePrompts.Line? in
                guard let section = LifePrompts.Section(rawValue: item.title) else { return nil }
                return LifePrompts.Line(section: section, text: item.body, entryIDs: item.entryIDs ?? [])
            }
            let concern = row.items.contains { $0.title == "concern" }
            return PortraitView(id: row.id, month: row.periodStart, generatedAt: row.generatedAt, lines: lines, concern: concern)
        }
        .sorted { $0.month != $1.month ? $0.month > $1.month : $0.generatedAt > $1.generatedAt }
    }

    static func portraitForThisMonth(now: Date = .now, calendar: Calendar = .current, in context: ModelContext) -> PortraitView? {
        let month = calendar.dateInterval(of: .month, for: now)?.start ?? now
        return portraits(in: context).first { $0.month == month }
    }

    enum PortraitOutcome: Equatable {
        case written(PortraitView)
        // The portrait reads a year through OpenAI: the on-device model's room is a few thousand
        // characters, a few days of journal.
        case needsCloud
        case unavailable
        case failed
    }

    static func writePortrait(
        reading: LifeSignals.Reading,
        priorities: [LifeSignals.Priority],
        name: (LifeArea) -> String,
        resolve: () -> Result<AskProvider, AIJobFailure>,
        now: Date = .now,
        calendar: Calendar = .current,
        in context: ModelContext,
        diagnostics: DiagnosticsLog = .shared
    ) async -> PortraitOutcome {
        guard case .success(let provider) = resolve() else { return .unavailable }
        guard provider.kind == .openAI else { return .needsCloud }
        let yearStart = now.addingTimeInterval(-365 * 86_400)
        let ids = ((try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { !$0.isDraft && $0.entryDate > yearStart }))) ?? []).map(\.id)
        let entries = entries(ids: ids, in: context)
        guard !entries.isEmpty else { return .failed }
        let months = rows("month", in: context)
            .filter { $0.periodStart > yearStart }
            .sorted { $0.periodStart < $1.periodStart }
            .compactMap { row -> String? in
                guard let body = row.items.first?.body, !body.isEmpty else { return nil }
                return "\(row.periodStart.formatted(.dateTime.month(.wide).year())): \(body)"
            }
        let planned = LifePrompts.portraitRequest(
            facts: LifePrompts.facts(reading, priorities: priorities, name: name),
            monthSummaries: months,
            entries: entries,
            feedback: feedback(in: context),
            model: provider.model
        )
        let started = Date.now
        do {
            let result = try await provider.generator.generate(planned.request)
            guard let portrait = LifePrompts.parsePortrait(result.text, handles: planned.handles) else {
                record("life.portrait", success: false, started: started, fields: ["unreadable": .bool(true)], diagnostics: diagnostics)
                return .failed
            }
            record("life.portrait", success: true, started: started, fields: ["lines": .int(portrait.lines.count), "concern": .bool(portrait.concern), "entries": .int(planned.handles.count)], diagnostics: diagnostics)
            var items = portrait.lines.enumerated().map { index, line in
                ReflectQueueItem(id: "\(line.section.rawValue):\(index)", source: .generated, title: line.section.rawValue, body: line.text, prompt: "", entryIDs: line.entryIDs)
            }
            if portrait.concern {
                items.append(ReflectQueueItem(id: "concern", source: .generated, title: "concern", body: "", prompt: ""))
            }
            let month = calendar.dateInterval(of: .month, for: now)?.start ?? now
            // A month keeps one portrait: writing it again replaces this month's.
            for row in rows(portraitKind, in: context) where row.periodStart == month { context.delete(row) }
            let created = ReflectSummary(kind: .month, periodStart: month, generatedAt: now, items: items)
            created.periodKindRaw = portraitKind
            context.insert(created)
            try? context.saveStampingEntries()
            return portraits(in: context).first { $0.id == created.id }.map(PortraitOutcome.written) ?? .failed
        } catch {
            record("life.portrait", success: false, started: started, fields: ["error": .errorCode(error)], diagnostics: diagnostics)
            return .failed
        }
    }

    // MARK: - Feedback

    static func feedback(in context: ModelContext) -> [LifePrompts.Feedback] {
        rows(feedbackKind, in: context).flatMap(\.items).map { item in
            LifePrompts.Feedback(line: item.title, right: item.prompt == "right", note: item.body)
        }
    }

    static func verdict(on line: String, in context: ModelContext) -> Bool? {
        rows(feedbackKind, in: context).flatMap(\.items).last { $0.title == line }.map { $0.prompt == "right" }
    }

    // One row holds every verdict; a new verdict on the same line replaces the old.
    static func give(_ right: Bool, on line: String, note: String = "", in context: ModelContext, diagnostics: DiagnosticsLog = .shared) {
        let existing = rows(feedbackKind, in: context)
        var items = existing.flatMap(\.items).filter { $0.title != line }
        items.append(ReflectQueueItem(id: UUID().uuidString, source: .generated, title: line, body: note.trimmingCharacters(in: .whitespacesAndNewlines), prompt: right ? "right" : "notQuite"))
        existing.forEach(context.delete)
        let row = ReflectSummary(kind: .month, periodStart: .distantPast, generatedAt: .now, items: items)
        row.periodKindRaw = feedbackKind
        context.insert(row)
        try? context.saveStampingEntries()
        diagnostics.record("life.feedback", ["right": .bool(right), "withNote": .bool(!note.isEmpty)])
    }

    // MARK: - Helpers

    private static func replace(kind: String, periodStart: Date, items: [ReflectQueueItem], fingerprint: String?, in context: ModelContext) -> ReflectSummary {
        rows(kind, in: context).forEach(context.delete)
        let row = ReflectSummary(kind: .month, periodStart: periodStart, generatedAt: .now, items: items, sourceFingerprint: fingerprint)
        row.periodKindRaw = kind
        context.insert(row)
        try? context.saveStampingEntries()
        return row
    }

    private static func record(_ event: String, success: Bool, started: Date, fields: [String: DiagnosticValue], diagnostics: DiagnosticsLog) {
        var all = fields
        all["success"] = .bool(success)
        all["milliseconds"] = .int(Int(Date.now.timeIntervalSince(started) * 1000))
        diagnostics.record(event, all)
    }
}
