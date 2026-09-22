import Foundation

// One structured request per period: what's worth asking about further, from either fidelity
// tier. Mirrors ReflectNarrator's request-building shape, but returns a short list of items
// instead of a paragraph. Called only by ReflectSummaryStore's generate-and-cache operation, never
// on open.
@MainActor
enum ReflectQueueGenerator {
    struct Payload: Decodable {
        struct Item: Decodable {
            let body: String
            let prompt: String
        }
        let items: [Item]
    }

    static let maxItems = 3

    // nil means the request failed and nothing should be cached. An empty array means the model
    // read the period and found nothing worth asking about, which is cached as "all caught up."
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
            let items = parsed(result.text)
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
        You read one \(grain) of a personal journal and notice up to \(maxItems) things worth \
        asking about further: a thread worth continuing, a pattern worth naming, something left \
        unfinished. \(voice.instruction)
        Never invent a detail, a name, or an event the text below doesn't carry. No advice, no \
        diagnosis, no verdict on a life: you are noticing, not judging. If nothing stands out, \
        return an empty list rather than reaching for something thin.
        Each item needs a body (one short sentence: what you noticed) and a prompt (a short \
        question that would open a new journal entry continuing this thought, written as \
        something the author would ask themself).
        """
        let schema = JSONSchema.object([
            .init("items", .array(.object([
                .init("body", .string(description: "One short sentence: what you noticed.")),
                .init("prompt", .string(description: "A short question that would seed a new journal entry.")),
            ]))),
        ])
        return TextRequest(
            model: provider.model,
            system: system,
            user: "Period: \(title)\n\n\(prompt)",
            schema: schema,
            schemaName: "reflect_queue",
            maxOutputTokens: 400
        )
    }

    private static func parsed(_ text: String) -> [ReflectQueueItem] {
        guard let payload = try? StructuredOutputParser.decode(Payload.self, from: text) else { return [] }
        var items: [ReflectQueueItem] = []
        for (index, item) in payload.items.enumerated() {
            let body = item.body.trimmingCharacters(in: .whitespacesAndNewlines)
            let prompt = item.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty, !prompt.isEmpty else { continue }
            items.append(ReflectQueueItem(id: "generated:\(index)", source: .generated, title: "Worth asking", body: body, prompt: prompt))
            if items.count >= maxItems { break }
        }
        return items
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
