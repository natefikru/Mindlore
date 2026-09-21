import Foundation

// One paragraph about a period, asked for when the user opens it and forgotten when they leave:
// not persisted, not retried, no AIJobPolicy (that governs three per-entry jobs with counted
// attempts; this is neither per-entry nor worth counting failures on, since reopening the period
// asks again). The prompt carries only the aggregated facts already on the chart screen — mood
// distribution, area counts, top tags, loose-end opens/closes, entry count — never entry text
// (tasks/reflect-spec.md owner decision 3). No advice, same rule as Ask and loose ends.
@MainActor
enum ReflectNarrator {
    static func narrate(
        period: ReflectAggregator.Period,
        kind: ReflectPeriodKind,
        title: String,
        provider: AskProvider,
        voice: PromptVoice,
        areaName: (LifeArea) -> String,
        diagnostics: DiagnosticsLog = .shared
    ) async -> String? {
        guard period.entryCount > 0 else { return nil }
        let request = request(period: period, kind: kind, title: title, provider: provider, voice: voice, areaName: areaName)
        let started = Date.now
        do {
            let result = try await provider.generator.generate(request)
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            record(kind: kind, period: period, started: started, success: true, diagnostics: diagnostics)
            return text.isEmpty ? nil : text
        } catch {
            record(kind: kind, period: period, started: started, success: false, error: error, diagnostics: diagnostics)
            return nil
        }
    }

    private static func request(
        period: ReflectAggregator.Period,
        kind: ReflectPeriodKind,
        title: String,
        provider: AskProvider,
        voice: PromptVoice,
        areaName: (LifeArea) -> String
    ) -> TextRequest {
        func rendered<Key: RawRepresentable>(_ counts: [Key: Int], name: (Key) -> String) -> String where Key.RawValue == String {
            counts
                .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.rawValue < $1.key.rawValue }
                .map { "\(name($0.key)): \($0.value)" }
                .joined(separator: ", ")
        }

        var facts = "Period: \(title)\nTotal entries: \(period.entryCount)"
        let moods = rendered(period.moodCounts) { $0.name }
        if !moods.isEmpty { facts += "\nMood counts: \(moods)" }
        let areas = rendered(period.areaCounts, name: areaName)
        if !areas.isEmpty { facts += "\nLife area counts: \(areas)" }
        if !period.topTags.isEmpty {
            facts += "\nTop tags: \(period.topTags.map(\.tag).joined(separator: ", "))"
        }
        if period.looseEndsOpened > 0 { facts += "\nLoose ends opened: \(period.looseEndsOpened)" }
        if period.looseEndsClosed > 0 { facts += "\nLoose ends closed: \(period.looseEndsClosed)" }

        let system = """
        You write one short paragraph, two to three sentences, summarizing a journal's own \
        statistics for its author. \(voice.instruction)
        State only what the numbers below show. Never advise, judge, or speculate beyond them. \
        Never invent a detail, a name, or an event the numbers don't carry.
        """
        return TextRequest(model: provider.model, system: system, user: facts, maxOutputTokens: 200)
    }

    private static func record(
        kind: ReflectPeriodKind,
        period: ReflectAggregator.Period,
        started: Date,
        success: Bool,
        error: (any Error)? = nil,
        diagnostics: DiagnosticsLog
    ) {
        var fields: [String: DiagnosticValue] = [
            "kind": .string(kind.rawValue),
            "entryCount": .int(period.entryCount),
            "milliseconds": .double(Date.now.timeIntervalSince(started) * 1000),
            "success": .bool(success),
        ]
        if let error { fields["error"] = .errorCode(error) }
        diagnostics.record("reflect.narrated", fields)
    }
}
