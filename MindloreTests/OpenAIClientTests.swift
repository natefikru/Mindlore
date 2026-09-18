import AVFoundation
import Foundation
import Testing
@testable import Mindlore

@MainActor
struct OpenAIClientTests {
    private let baseURL = URL(string: "https://api.example.test/v1")!
    private let schema = JSONSchema.object([.init("text", .string())])

    private func generator(_ http: FakeHTTPClient) -> OpenAICompatibleTextGenerator {
        OpenAICompatibleTextGenerator(baseURL: baseURL, apiKey: "sk-test", http: http, jsonModeMemory: JSONModeMemory())
    }

    @Test func structuredRequestShape() async throws {
        let http = FakeHTTPClient(FakeHTTPClient.completion(#"{"text":"ok"}"#))
        let result = try await generator(http).generate(TextRequest(model: "gpt-test", system: "sys", user: "hello", schema: schema, schemaName: "thing", maxOutputTokens: 500))

        let sent = try #require(http.sent.first)
        #expect(sent.request.url?.absoluteString == "https://api.example.test/v1/chat/completions")
        #expect(sent.request.httpMethod == "POST")
        #expect(sent.request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(sent.request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(sent.request.timeoutInterval == 300)
        let body = sent.jsonBody
        #expect(body["model"] as? String == "gpt-test")
        #expect(body["max_completion_tokens"] as? Int == 500)
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.map { $0["role"] as? String } == ["system", "user"])
        #expect(messages[1]["content"] as? String == "hello")
        let format = try #require(body["response_format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        let jsonSchema = try #require(format["json_schema"] as? [String: Any])
        #expect(jsonSchema["name"] as? String == "thing")
        #expect(jsonSchema["strict"] as? Bool == true)

        #expect(result == TextResult(text: #"{"text":"ok"}"#, model: "gpt-test", inputTokens: 11, outputTokens: 7))
    }

    @Test func historyIsSentBetweenTheSystemAndUserMessages() async throws {
        let http = FakeHTTPClient(FakeHTTPClient.completion("ok"))
        let history = [
            TextMessage(role: .user, content: "first question"),
            TextMessage(role: .assistant, content: "first answer"),
            TextMessage(role: .user, content: "second question"),
            TextMessage(role: .assistant, content: "second answer"),
        ]
        _ = try await generator(http).generate(TextRequest(model: "m", system: "sys", user: "now", messages: history))

        let messages = try #require(http.sent.first?.jsonBody["messages"] as? [[String: Any]])
        #expect(messages.map { $0["role"] as? String } == ["system", "user", "assistant", "user", "assistant", "user"])
        #expect(messages.map { $0["content"] as? String } == ["sys", "first question", "first answer", "second question", "second answer", "now"])
    }

    // A single-shot job must encode exactly as it did before messages existed.
    @Test func aRequestWithoutHistoryEncodesUnchanged() throws {
        let body = try OpenAICompatibleTextGenerator.body(for: TextRequest(model: "m", system: "sys", user: "hello"), jsonMode: false)
        let json = String(decoding: try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]), as: UTF8.self)
        #expect(json == #"{"messages":[{"content":"sys","role":"system"},{"content":"hello","role":"user"}],"model":"m"}"#)
    }

    @Test func imagesAreSentAsDataURLContentParts() async throws {
        let http = FakeHTTPClient(FakeHTTPClient.completion("done"))
        _ = try await generator(http).generate(TextRequest(model: "m", system: "s", user: "page", images: [TextImage(jpegData: Data([1, 2, 3]), detail: .high)]))

        let messages = try #require(http.sent.first?.jsonBody["messages"] as? [[String: Any]])
        let parts = try #require(messages[1]["content"] as? [[String: Any]])
        #expect(parts[0]["type"] as? String == "text")
        #expect(parts[0]["text"] as? String == "page")
        let image = try #require(parts[1]["image_url"] as? [String: Any])
        #expect(image["url"] as? String == "data:image/jpeg;base64,AQID")
        #expect(image["detail"] as? String == "high")
        #expect(http.sent.first?.jsonBody["response_format"] == nil)
    }

    @Test func rejectedSchemaRetriesOnceInJSONModeAndIsRemembered() async throws {
        let memory = JSONModeMemory()
        let http = FakeHTTPClient(
            FakeHTTPClient.error(400, code: "invalid_request_error", param: "response_format"),
            FakeHTTPClient.completion(#"{"text":"ok"}"#),
            FakeHTTPClient.completion(#"{"text":"again"}"#)
        )
        let client = OpenAICompatibleTextGenerator(baseURL: baseURL, apiKey: "k", http: http, jsonModeMemory: memory)
        let request = TextRequest(model: "local", system: "sys", user: "u", schema: schema)

        _ = try await client.generate(request)
        _ = try await client.generate(request)

        let formats = http.sent.map { ($0.jsonBody["response_format"] as? [String: Any])?["type"] as? String }
        #expect(formats == ["json_schema", "json_object", "json_object"])
        let retrySystem = (http.sent[1].jsonBody["messages"] as? [[String: Any]])?.first?["content"] as? String
        #expect(retrySystem?.contains("JSON") == true)
    }

    @Test func otherBadRequestsAreNotRetried() async {
        let http = FakeHTTPClient(FakeHTTPClient.error(400, code: "context_length_exceeded"))
        await #expect(throws: AIError.contextTooLong) {
            try await generator(http).generate(TextRequest(model: "m", system: "s", user: "u", schema: schema))
        }
        #expect(http.sent.count == 1)
    }

    @Test func truncatedAndRefusedResponsesAreErrors() async {
        let truncated = FakeHTTPClient(FakeHTTPClient.completion("{\"text\":", finishReason: "length"))
        await #expect(throws: AIError.outputTruncated) {
            try await generator(truncated).generate(TextRequest(model: "m", system: "s", user: "u"))
        }
        let refused = FakeHTTPClient(FakeHTTPClient.json(200, ["choices": [["message": ["content": NSNull(), "refusal": "no"], "finish_reason": "stop"]]]))
        await #expect(throws: AIError.badRequest(code: "refusal")) {
            try await generator(refused).generate(TextRequest(model: "m", system: "s", user: "u"))
        }
    }

    @Test func transportErrorsPassThrough() async {
        let http = FakeHTTPClient(.failure(.offline(.notConnectedToInternet)))
        await #expect(throws: AIError.offline(.notConnectedToInternet)) {
            try await generator(http).generate(TextRequest(model: "m", system: "s", user: "u"))
        }
    }

    @Test func modelListSortsIDsAndMapsErrors() async throws {
        let http = FakeHTTPClient(FakeHTTPClient.json(200, ["object": "list", "data": [["id": "whisper-1"], ["id": "gpt-5.6-luna"]]]), FakeHTTPClient.error(401))
        let list = OpenAICompatibleModelList(baseURL: baseURL, apiKey: "sk-test", http: http)

        #expect(try await list.fetch() == ["gpt-5.6-luna", "whisper-1"])
        #expect(http.sent.first?.request.url?.absoluteString == "https://api.example.test/v1/models")
        #expect(http.sent.first?.request.httpMethod == "GET")
        #expect(http.sent.first?.request.timeoutInterval == 30)
        await #expect(throws: AIError.invalidKey) { try await list.fetch() }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func transcriptionUploadsMultipartM4A() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let caf = directory.appendingPathComponent("rec.caf")
        _ = try AudioFixtures.writePCM(to: caf, seconds: 0.5)
        let m4a = directory.appendingPathComponent("rec.m4a")
        try AudioConverter.convertToAAC(caf).data.write(to: m4a)

        let http = FakeHTTPClient(FakeHTTPClient.json(200, ["text": "  Hello there.  "]))
        let transcriber = OpenAICompatibleTranscriber(baseURL: baseURL, apiKey: "sk-test", model: "gpt-transcribe", http: http, prompt: "earlier words")
        let text = try await transcriber.transcribe(audioFileURL: m4a, locale: Locale(identifier: "en_US"))

        #expect(text == "Hello there.")
        let sent = try #require(http.sent.first)
        #expect(sent.request.url?.absoluteString == "https://api.example.test/v1/audio/transcriptions")
        #expect(sent.request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        let body = String(decoding: try #require(sent.body), as: UTF8.self)
        #expect(body.contains("name=\"model\"\r\n\r\ngpt-transcribe\r\n"))
        #expect(body.contains("name=\"language\"\r\n\r\nen\r\n"))
        #expect(body.contains("name=\"response_format\"\r\n\r\njson\r\n"))
        #expect(body.contains("name=\"prompt\"\r\n\r\nearlier words\r\n"))
        #expect(body.contains("filename=\"audio.m4a\""))
        #expect(sent.body.map(OpenAICompatibleTranscriber.isM4AUpload) == true)
    }

    @Test func cafAudioIsConvertedBeforeUpload() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let caf = directory.appendingPathComponent("rec.caf")
        _ = try AudioFixtures.writePCM(to: caf, seconds: 0.5)
        let http = FakeHTTPClient(FakeHTTPClient.json(200, ["text": "converted"]))

        _ = try await OpenAICompatibleTranscriber(baseURL: baseURL, apiKey: "k", model: "m", http: http).transcribe(audioFileURL: caf, locale: Locale(identifier: "en_US"))

        let body = try #require(http.sent.first?.body)
        #expect(OpenAICompatibleTranscriber.isM4AUpload(body))
    }

    @Test func emptyTranscriptionIsNoSpeechAndErrorsMap() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let caf = directory.appendingPathComponent("rec.caf")
        _ = try AudioFixtures.writePCM(to: caf, seconds: 0.2)
        let http = FakeHTTPClient(FakeHTTPClient.json(200, ["text": "   "]), FakeHTTPClient.error(401))
        let transcriber = OpenAICompatibleTranscriber(baseURL: baseURL, apiKey: "k", model: "m", http: http)

        await #expect(throws: TranscriptionError.noSpeechDetected) {
            try await transcriber.transcribe(audioFileURL: caf, locale: .current)
        }
        await #expect(throws: AIError.invalidKey) {
            try await transcriber.transcribe(audioFileURL: caf, locale: .current)
        }
    }
}
