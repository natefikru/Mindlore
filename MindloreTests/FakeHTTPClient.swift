import Foundation
import Synchronization
@testable import Mindlore

nonisolated final class FakeHTTPClient: HTTPClient {
    struct Sent: Sendable {
        let request: URLRequest
        let body: Data?

        var jsonBody: [String: Any] {
            (body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
        }

        var bodyText: String {
            body.map { String(decoding: $0, as: UTF8.self) } ?? ""
        }
    }

    // What a scripted stream does. `frames` are handed over exactly as split, so a test can put a
    // frame boundary anywhere it likes, including the middle of an escape.
    enum StreamScript: Sendable {
        case frames([Data])
        // An error status, which is a response rather than a stream.
        case response(HTTPResponse)
        // Nothing ever arrives.
        case failure(AIError)
        // Frames, then the connection dies.
        case framesThenFailure([Data], AIError)
    }

    private let state = Mutex<(responses: [Result<HTTPResponse, AIError>], streams: [StreamScript], sent: [Sent])>(([], [], []))

    init(_ responses: Result<HTTPResponse, AIError>...) {
        state.withLock { $0.responses = responses }
    }

    var sent: [Sent] {
        state.withLock { $0.sent }
    }

    func enqueue(_ response: Result<HTTPResponse, AIError>) {
        state.withLock { $0.responses.append(response) }
    }

    func send(_ request: URLRequest, body: Data?) async throws -> HTTPResponse {
        let next = state.withLock { state -> Result<HTTPResponse, AIError>? in
            state.sent.append(Sent(request: request, body: body))
            return state.responses.isEmpty ? nil : state.responses.removeFirst()
        }
        guard let next else { throw AIError.invalidResponse }
        return try next.get()
    }

    func enqueue(stream: StreamScript) {
        state.withLock { $0.streams.append(stream) }
    }

    func stream(_ request: URLRequest, body: Data?) async throws -> HTTPStream {
        let next = state.withLock { state -> StreamScript? in
            state.sent.append(Sent(request: request, body: body))
            return state.streams.isEmpty ? nil : state.streams.removeFirst()
        }
        switch next {
        case .frames(let frames):
            return .body(AsyncThrowingStream { continuation in
                for frame in frames { continuation.yield(frame) }
                continuation.finish()
            })
        case .framesThenFailure(let frames, let error):
            return .body(AsyncThrowingStream { continuation in
                for frame in frames { continuation.yield(frame) }
                continuation.finish(throwing: error)
            })
        case .response(let response):
            return .response(response)
        case .failure(let error):
            throw error
        case nil:
            throw AIError.invalidResponse
        }
    }

    // One SSE frame per delta, then the finish frame and [DONE], the way OpenAI sends them.
    static func sse(deltas: [String], model: String = "gpt-test", inputTokens: Int? = 11, outputTokens: Int? = 7) -> [Data] {
        var frames = deltas.map { delta in
            frame(["model": model, "choices": [["delta": ["content": delta], "index": 0]]])
        }
        frames.append(frame(["model": model, "choices": [["delta": [:], "index": 0, "finish_reason": "stop"]]]))
        if let inputTokens, let outputTokens {
            frames.append(frame(["model": model, "choices": [], "usage": ["prompt_tokens": inputTokens, "completion_tokens": outputTokens]]))
        }
        frames.append(Data("data: [DONE]\n\n".utf8))
        return frames
    }

    static func frame(_ object: [String: Any]) -> Data {
        let json = String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        return Data("data: \(json)\n\n".utf8)
    }

    static func json(_ status: Int = 200, _ object: Any, headers: [String: String] = [:]) -> Result<HTTPResponse, AIError> {
        .success(HTTPResponse(status: status, headers: headers, data: try! JSONSerialization.data(withJSONObject: object)))
    }

    static func completion(_ content: String, finishReason: String = "stop", model: String = "gpt-test") -> Result<HTTPResponse, AIError> {
        json(200, [
            "model": model,
            "choices": [["message": ["content": content], "finish_reason": finishReason]],
            "usage": ["prompt_tokens": 11, "completion_tokens": 7],
        ])
    }

    static func error(_ status: Int, code: String? = nil, type: String? = nil, param: String? = nil, message: String = "") -> Result<HTTPResponse, AIError> {
        var body: [String: Any] = ["message": message]
        body["code"] = code
        body["type"] = type
        body["param"] = param
        return json(status, ["error": body])
    }
}
