import Foundation

// One structured request per period: a short summary of what the period actually held, from
// either fidelity tier. Mirrors ReflectNarrator's request-building shape, but the result is cached
// instead of asked for again on every open. Called only by ReflectSummaryStore's
// generate-and-cache operation, never on open. Started as a list of up to three separate "worth
// asking" observations; cut down to one paragraph (owner, 2026-09-21) because that's what a week
// looked back on actually is, not a checklist.
@MainActor
enum ReflectQueueGenerator {
    struct Payload: Decodable {
        let summary: String
        let prompt: String
    }

    // nil means the request failed and nothing should be cached. An empty list means the model
    // read the period and had nothing to say, which is cached as "all caught up" rather than
    // retried every time the period is viewed.
    static func generate(
        kind: ReflectSummaryKind,
        title: String,
        prompt: String,
        provider: AskProvider,
        voice: PromptVoice,
        diagnostics: DiagnosticsLog = .shared
    ) async -> [ReflectQueueItem]? {
        let request = request(kind: kind, title: title, prompt: prompt, provider: provider, voice: voice)
        let started = Date.now
        do {
            let result = try await provider.generator.generate(request)
            let items = parsed(result.text, kind: kind)
            record(kind: kind, itemCount: items.count, started: started, success: true, diagnostics: diagnostics)
            return items
        } catch {
            record(kind: kind, itemCount: 0, started: started, success: false, error: error, diagnostics: diagnostics)
            return nil
        }
    }

    private static func request(
        kind: ReflectSummaryKind,
        title: String,
        prompt: String,
        provider: AskProvider,
        voice: PromptVoice
    ) -> TextRequest {
        let grain = kind == .week ? "week" : "month"
        let system = """
        You read one \(grain) of a personal journal and write a short summary of it: two to five \
        plain sentences, what actually happened. \(voice.instruction)

        Cover the range of it, not just the loudest entry. If the \(grain) touched more than one \
        part of life (a deadline at work, a friend's visit, a bad night's sleep), say so, rather \
        than picking the single most dramatic entry and letting the rest go unmentioned. If \
        several entries share a thread instead (the same worry came up more than once, the mood \
        shifted partway through), that pattern is usually more worth naming than any one entry is.

        Ground every sentence in something the text actually says: a name, a place, a specific \
        thing that happened. Never a mood report on its own ("it was a stressful week") without \
        what made it that.

        Never open with a generic recap, and never reuse the same opener across different \
        summaries: "I spent much of...", "It was a week of...", "Overall...", "A mix of..." are \
        all reflexes to avoid, not a style to fall back on. Start from whatever's actually most \
        specific instead.

        Never invent a detail, a name, or an event the text below doesn't carry. No advice, no \
        diagnosis, no verdict on a life: you are summarizing, not judging. If there is nothing to \
        summarize, leave summary empty rather than reaching for something thin.

        Also write a prompt: a short question that grows directly out of the summary you just \
        wrote, naming the same person, thread, or event, written as something the author would \
        ask themself to keep writing about it. Never a generic prompt the summary doesn't earn.
        """
        let schema = JSONSchema.object([
            .init("summary", .string(description: "Two to five plain sentences summarizing the period, or empty if there is nothing to say.")),
            .init("prompt", .string(description: "A short question, growing out of the summary, that would seed a new journal entry.")),
        ])
        return TextRequest(
            model: provider.model,
            system: system,
            user: "Period: \(title)\n\n\(prompt)",
            schema: schema,
            schemaName: "reflect_summary",
            maxOutputTokens: 400
        )
    }

    private static func parsed(_ text: String, kind: ReflectSummaryKind) -> [ReflectQueueItem] {
        guard let payload = try? StructuredOutputParser.decode(Payload.self, from: text) else { return [] }
        let summary = payload.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = payload.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty, !prompt.isEmpty else { return [] }
        let title = kind == .week ? "This week" : "This month"
        return [ReflectQueueItem(id: "generated:0", source: .generated, title: title, body: summary, prompt: prompt)]
    }

    private static func record(
        kind: ReflectSummaryKind,
        itemCount: Int,
        started: Date,
        success: Bool,
        error: (any Error)? = nil,
        diagnostics: DiagnosticsLog
    ) {
        var fields: [String: DiagnosticValue] = [
            "kind": .string(kind.rawValue),
            "itemCount": .int(itemCount),
            "milliseconds": .double(Date.now.timeIntervalSince(started) * 1000),
            "success": .bool(success),
        ]
        if let error { fields["error"] = .errorCode(error) }
        diagnostics.record("reflect.queueGenerated", fields)
    }
}
