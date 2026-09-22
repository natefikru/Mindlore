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

    // The on-device model has about 4,096 tokens for everything: instructions, the period, and
    // the answer. Ask measured its room at about 3,300 characters of journal; Reflect's shorter
    // on-device instructions leave a little more. The caller fits the period's text to this.
    static let onDevicePromptLimit = 3_600

    static func promptLimit(for provider: AskProvider) -> Int? {
        provider.kind == .onDevice ? onDevicePromptLimit : nil
    }

    // nil means the request failed, or came back as something that can't be read, and nothing
    // should be cached, so the period is asked again next time. An empty list means the model
    // read the period and had nothing to say, which is cached as an empty summary rather than
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
            guard let items = parsed(result.text, kind: kind, provider: provider.kind) else {
                record(kind: kind, itemCount: 0, started: started, success: false, unreadable: true, diagnostics: diagnostics)
                return nil
            }
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
        if provider.kind == .onDevice {
            // Foundation Models ignores a schema and answers in prose, so it's asked for a shape
            // prose can hold: the paragraph, then the question on its own line. Kept short,
            // because every character here is one the period can't use.
            let system = """
            You read one \(grain) of a personal journal and summarize it in two to four plain \
            sentences: what actually happened, naming the people, places, and events the text \
            names. Cover more than the loudest entry. \(voice.instruction) Never invent anything \
            the text doesn't say. No advice, no judgement.

            Then, on its own last line, write "Question:" followed by one short question, about \
            the same people or events, that the author could write about next.
            """
            return TextRequest(
                model: provider.model,
                system: system,
                user: "Period: \(title)\n\n\(prompt)",
                maxOutputTokens: 400
            )
        }
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

        An entry marked as a creative piece is a poem, a song, or a story the author wrote. Mention \
        it as their writing ("you wrote a song about leaving"), never as something that happened.

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

    // nil when the answer can't be read at all. OpenAI's is JSON held to the schema; the
    // on-device model's is the paragraph and a "Question:" line it was asked for.
    private static func parsed(_ text: String, kind: ReflectSummaryKind, provider: AskProviderKind) -> [ReflectQueueItem]? {
        let summary: String
        let prompt: String
        if let payload = try? StructuredOutputParser.decode(Payload.self, from: text) {
            summary = payload.summary
            prompt = payload.prompt
        } else if provider == .onDevice, let plain = plainText(text) {
            (summary, prompt) = plain
        } else {
            return nil
        }
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSummary.isEmpty, !trimmedPrompt.isEmpty else { return [] }
        let title = kind == .week ? "This week" : "This month"
        return [ReflectQueueItem(id: "generated:0", source: .generated, title: title, body: trimmedSummary, prompt: trimmedPrompt)]
    }

    // Everything after the last "Question:" is the prompt and everything before it the summary,
    // whether the model put it on its own line as asked or ran it on the end of the paragraph, with
    // markdown bold and a "Summary:" label dropped. An empty answer is nothing to say; prose with
    // no question is unreadable, since a card without its question is half a card.
    static func plainText(_ text: String) -> (summary: String, prompt: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return ("", "") }
        guard let marker = trimmed.range(of: "question:", options: [.caseInsensitive, .backwards]) else { return nil }
        let clean = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "*"))
        let prompt = trimmed[marker.upperBound...].trimmingCharacters(in: clean)
        var summary = trimmed[..<marker.lowerBound].trimmingCharacters(in: clean)
        if let label = summary.range(of: "summary:", options: [.caseInsensitive, .anchored]) {
            summary = summary[label.upperBound...].trimmingCharacters(in: clean)
        }
        return (summary, prompt)
    }

    private static func record(
        kind: ReflectSummaryKind,
        itemCount: Int,
        started: Date,
        success: Bool,
        error: (any Error)? = nil,
        unreadable: Bool = false,
        diagnostics: DiagnosticsLog
    ) {
        var fields: [String: DiagnosticValue] = [
            "kind": .string(kind.rawValue),
            "itemCount": .int(itemCount),
            "milliseconds": .double(Date.now.timeIntervalSince(started) * 1000),
            "success": .bool(success),
        ]
        if let error { fields["error"] = .errorCode(error) }
        if unreadable { fields["unreadable"] = .bool(true) }
        diagnostics.record("reflect.queueGenerated", fields)
    }
}
