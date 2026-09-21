import Foundation

// The same request with `stream` on it, read back as server-sent events. Nothing about what is
// sent or billed changes: the tokens are the same tokens, they just stop waiting for each other.
extension OpenAICompatibleTextGenerator: StreamingTextGenerator {
    func stream(_ request: TextRequest) -> AsyncThrowingStream<TextStreamEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(request, into: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: AIError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    @concurrent
    private func run(_ request: TextRequest, into continuation: AsyncThrowingStream<TextStreamEvent, any Error>.Continuation) async throws {
        let key = quirkKey(request)
        // A server that has already said no is not asked again for the rest of the session.
        guard !quirks.refuses(.streaming, key) else {
            continuation.yield(.finished(try await generate(request)))
            return
        }
        let jsonMode = request.schema != nil && quirks.refuses(.jsonSchema, key)
        var body = try Self.body(for: request, jsonMode: jsonMode)
        body["stream"] = true
        // Without this the last chunk carries no usage, and TextResult stops meaning what it means.
        body["stream_options"] = ["include_usage": true]
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])

        switch try await http.stream(completionsRequest(), body: data) {
        case .body(let frames):
            try await consume(frames, into: continuation)
        case .response(let response):
            // Two refusals are worth one more try without the thing refused; everything else is
            // the failure it looks like, mapped by the code that maps a single-shot one.
            if request.schema != nil, !jsonMode, OpenAIErrorMapper.rejectsResponseFormat(response) {
                quirks.refuse(.jsonSchema, key)
                continuation.yield(.finished(try await generate(request)))
            } else if OpenAIErrorMapper.rejectsStreaming(response) {
                quirks.refuse(.streaming, key)
                continuation.yield(.finished(try await generate(request)))
            } else {
                throw OpenAIErrorMapper.map(response)
            }
        }
    }

    @concurrent
    private func consume(
        _ frames: AsyncThrowingStream<Data, any Error>,
        into continuation: AsyncThrowingStream<TextStreamEvent, any Error>.Continuation
    ) async throws {
        var parser = SSEParser()
        var state = StreamState()
        var isDone = false
        for try await frame in frames {
            for event in parser.consume(frame) {
                switch event {
                case .done:
                    isDone = true
                case .payload(let payload):
                    if let delta = state.apply(payload), !delta.isEmpty { continuation.yield(.delta(delta)) }
                }
            }
            if isDone { break }
        }
        if !isDone {
            for case .payload(let payload) in parser.finish() {
                if let delta = state.apply(payload), !delta.isEmpty { continuation.yield(.delta(delta)) }
            }
        }
        // The same three refusals the single-shot path checks, in the same order.
        if state.finishReason == "length" { throw AIError.outputTruncated }
        if state.wasRefused { throw AIError.badRequest(code: "refusal") }
        guard !state.text.isEmpty else { throw AIError.invalidResponse }
        continuation.yield(.finished(TextResult(
            text: state.text,
            model: state.model,
            inputTokens: state.inputTokens,
            outputTokens: state.outputTokens
        )))
    }

    // What the chunks have said so far. A chunk that doesn't decode is skipped rather than fatal:
    // a keep-alive shaped like one, or a field a server invented, must not lose the answer.
    private struct StreamState {
        private struct Chunk: Decodable {
            struct Choice: Decodable {
                struct Delta: Decodable {
                    let content: String?
                    let refusal: String?
                }
                let delta: Delta?
                let finish_reason: String?
            }
            struct Usage: Decodable {
                let prompt_tokens: Int?
                let completion_tokens: Int?
            }
            let model: String?
            let choices: [Choice]?
            let usage: Usage?
        }

        var text = ""
        var model = ""
        var inputTokens: Int?
        var outputTokens: Int?
        var finishReason: String?
        var wasRefused = false

        mutating func apply(_ payload: String) -> String? {
            guard let chunk = try? JSONDecoder().decode(Chunk.self, from: Data(payload.utf8)) else { return nil }
            if let name = chunk.model, !name.isEmpty { model = name }
            if let usage = chunk.usage {
                inputTokens = usage.prompt_tokens ?? inputTokens
                outputTokens = usage.completion_tokens ?? outputTokens
            }
            guard let choice = chunk.choices?.first else { return nil }
            if let reason = choice.finish_reason { finishReason = reason }
            if choice.delta?.refusal != nil { wasRefused = true }
            guard let content = choice.delta?.content else { return nil }
            text += content
            return content
        }
    }
}
