import Foundation
import Testing
@testable import Mindlore

@MainActor
struct OpenAIStreamingTests {
    private let baseURL = URL(string: "https://api.example.test/v1")!
    private let schema = JSONSchema.object([.init("text", .string())])

    private func generator(_ http: FakeHTTPClient, quirks: ProviderQuirks = ProviderQuirks()) -> OpenAICompatibleTextGenerator {
        OpenAICompatibleTextGenerator(baseURL: baseURL, apiKey: "sk-test", http: http, quirks: quirks)
    }

    private func events(_ generator: OpenAICompatibleTextGenerator, _ request: TextRequest) async throws -> [TextStreamEvent] {
        var events: [TextStreamEvent] = []
        for try await event in generator.stream(request) { events.append(event) }
        return events
    }

    private var request: TextRequest {
        TextRequest(model: "gpt-test", system: "sys", user: "hello")
    }

    @Test func deltasArriveInOrderAndTheResultIsTheWholeAnswer() async throws {
        let http = FakeHTTPClient()
        http.enqueue(stream: .frames(FakeHTTPClient.sse(deltas: ["Hel", "lo ", "there"])))

        let events = try await events(generator(http), request)

        #expect(events == [
            .delta("Hel"),
            .delta("lo "),
            .delta("there"),
            .finished(TextResult(text: "Hello there", model: "gpt-test", inputTokens: 11, outputTokens: 7)),
        ])
    }

    @Test func theRequestCarriesTheStreamFlagsAndNothingElseChanges() async throws {
        let http = FakeHTTPClient()
        http.enqueue(stream: .frames(FakeHTTPClient.sse(deltas: ["ok"])))

        _ = try await events(generator(http), TextRequest(model: "gpt-test", system: "sys", user: "hello", schema: schema, schemaName: "thing"))

        let body = try #require(http.sent.first?.jsonBody)
        #expect(body["stream"] as? Bool == true)
        #expect((body["stream_options"] as? [String: Any])?["include_usage"] as? Bool == true)
        #expect((body["response_format"] as? [String: Any])?["type"] as? String == "json_schema")
        #expect(http.sent.first?.request.url?.absoluteString == "https://api.example.test/v1/chat/completions")
    }

    @Test func framesSplitAnywhereGiveTheSameAnswer() async throws {
        let whole = FakeHTTPClient.sse(deltas: ["one ", "two ", "three"]).reduce(into: Data()) { $0 += $1 }
        // Every frame boundary moved: one byte at a time.
        let http = FakeHTTPClient()
        http.enqueue(stream: .frames(whole.map { Data([$0]) }))

        let events = try await events(generator(http), request)

        #expect(events.last == .finished(TextResult(text: "one two three", model: "gpt-test", inputTokens: 11, outputTokens: 7)))
    }

    @Test func aStreamThatDiesMidAnswerThrowsWhatTheTransportSaid() async throws {
        let http = FakeHTTPClient()
        http.enqueue(stream: .framesThenFailure(
            Array(FakeHTTPClient.sse(deltas: ["half"]).prefix(1)),
            .network(.networkConnectionLost)
        ))

        var events: [TextStreamEvent] = []
        await #expect(throws: AIError.network(.networkConnectionLost)) {
            for try await event in generator(http).stream(request) { events.append(event) }
        }
        // What arrived still arrived; whether to keep it is the caller's decision, not this one's.
        #expect(events == [.delta("half")])
    }

    @Test func anErrorStatusIsMappedLikeTheSingleShotPath() async {
        let http = FakeHTTPClient()
        http.enqueue(stream: .response(HTTPResponse(status: 401, headers: [:], data: Data(#"{"error":{"code":"invalid_api_key"}}"#.utf8))))

        await #expect(throws: AIError.invalidKey) {
            _ = try await events(generator(http), request)
        }
    }

    @Test func aTruncatedAnswerIsAnErrorRatherThanAShortOne() async {
        let http = FakeHTTPClient()
        http.enqueue(stream: .frames([
            FakeHTTPClient.frame(["model": "gpt-test", "choices": [["delta": ["content": "half"]]]]),
            FakeHTTPClient.frame(["choices": [["delta": [:], "finish_reason": "length"]]]),
            Data("data: [DONE]\n\n".utf8),
        ]))

        await #expect(throws: AIError.outputTruncated) {
            _ = try await events(generator(http), request)
        }
    }

    @Test func aRefusalIsAnError() async {
        let http = FakeHTTPClient()
        http.enqueue(stream: .frames([
            FakeHTTPClient.frame(["choices": [["delta": ["refusal": "no"], "finish_reason": "stop"]]]),
            Data("data: [DONE]\n\n".utf8),
        ]))

        await #expect(throws: AIError.badRequest(code: "refusal")) {
            _ = try await events(generator(http), request)
        }
    }

    @Test func aStreamThatSaysNothingAtAllIsNotAnEmptyAnswer() async {
        let http = FakeHTTPClient()
        http.enqueue(stream: .frames([Data("data: [DONE]\n\n".utf8)]))

        await #expect(throws: AIError.invalidResponse) {
            _ = try await events(generator(http), request)
        }
    }

    @Test func keepAlivesAndUnreadableChunksDoNotLoseTheAnswer() async throws {
        let http = FakeHTTPClient()
        http.enqueue(stream: .frames([
            Data(": keep-alive\n\n".utf8),
            Data("data: not json at all\n\n".utf8),
            FakeHTTPClient.frame(["model": "gpt-test", "choices": [["delta": ["content": "ok"]]]]),
            Data("data: [DONE]\n\n".utf8),
        ]))

        let events = try await events(generator(http), request)

        #expect(events == [.delta("ok"), .finished(TextResult(text: "ok", model: "gpt-test", inputTokens: nil, outputTokens: nil))])
    }

    @Test func aServerThatRejectsStreamingIsAskedOnceAndThenNeverAgain() async throws {
        let http = FakeHTTPClient(
            FakeHTTPClient.completion("first"),
            FakeHTTPClient.completion("second")
        )
        http.enqueue(stream: .response(HTTPResponse(status: 400, headers: [:], data: Data(#"{"error":{"param":"stream"}}"#.utf8))))
        let quirks = ProviderQuirks()
        let client = generator(http, quirks: quirks)

        let first = try await events(client, request)
        let second = try await events(client, request)

        #expect(first == [.finished(TextResult(text: "first", model: "gpt-test", inputTokens: 11, outputTokens: 7))])
        #expect(second == [.finished(TextResult(text: "second", model: "gpt-test", inputTokens: 11, outputTokens: 7))])
        // Three requests: the rejected stream, its retry, and a second question that never tried.
        #expect(http.sent.count == 3)
        #expect(http.sent.map { $0.jsonBody["stream"] as? Bool } == [true, nil, nil])
    }

    @Test func aServerThatRejectsTheSchemaFallsBackTheSameWayTheSingleShotPathDoes() async throws {
        let http = FakeHTTPClient(FakeHTTPClient.completion(#"{"text":"ok"}"#))
        http.enqueue(stream: .response(HTTPResponse(status: 400, headers: [:], data: Data(#"{"error":{"param":"response_format"}}"#.utf8))))
        let quirks = ProviderQuirks()

        let events = try await events(generator(http, quirks: quirks), TextRequest(model: "gpt-test", system: "s", user: "u", schema: schema))

        #expect(events == [.finished(TextResult(text: #"{"text":"ok"}"#, model: "gpt-test", inputTokens: 11, outputTokens: 7))])
        #expect(quirks.refuses(.jsonSchema, "https://api.example.test/v1|gpt-test"))
        // Streaming was not what it objected to, so it is still on the table.
        #expect(!quirks.refuses(.streaming, "https://api.example.test/v1|gpt-test"))
        #expect((http.sent.last?.jsonBody["response_format"] as? [String: Any])?["type"] as? String == "json_object")
    }

    @Test func otherBadRequestsAreNotRetried() async {
        let http = FakeHTTPClient()
        http.enqueue(stream: .response(HTTPResponse(status: 400, headers: [:], data: Data(#"{"error":{"code":"context_length_exceeded"}}"#.utf8))))

        await #expect(throws: AIError.contextTooLong) {
            _ = try await events(generator(http), request)
        }
        #expect(http.sent.count == 1)
    }
}
