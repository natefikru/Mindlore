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

    private let state = Mutex<(responses: [Result<HTTPResponse, AIError>], sent: [Sent])>(([], []))

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
