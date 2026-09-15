import Foundation
import Synchronization

// Chat Completions, the shape shared by OpenAI and most other providers. Structured output uses a
// strict JSON schema; a server that rejects that gets one retry in JSON mode for this session.
nonisolated struct OpenAICompatibleTextGenerator: TextGenerator {
    static let requestTimeout: TimeInterval = 300

    let baseURL: URL
    let apiKey: String
    let http: any HTTPClient
    let jsonModeMemory: JSONModeMemory

    init(baseURL: URL, apiKey: String, http: any HTTPClient, jsonModeMemory: JSONModeMemory = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.http = http
        self.jsonModeMemory = jsonModeMemory
    }

    func generate(_ request: TextRequest) async throws -> TextResult {
        let key = "\(baseURL.absoluteString)|\(request.model)"
        let useJSONMode = request.schema != nil && jsonModeMemory.contains(key)
        let response = try await send(request, jsonMode: useJSONMode)
        if request.schema != nil, !useJSONMode, OpenAIErrorMapper.rejectsResponseFormat(response) {
            jsonModeMemory.insert(key)
            return try decode(try await send(request, jsonMode: true))
        }
        return try decode(response)
    }

    private func send(_ request: TextRequest, jsonMode: Bool) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = Self.requestTimeout
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = try JSONSerialization.data(withJSONObject: Self.body(for: request, jsonMode: jsonMode), options: [.sortedKeys])
        return try await http.send(urlRequest, body: body)
    }

    static func body(for request: TextRequest, jsonMode: Bool) throws -> [String: Any] {
        var system = request.system
        if jsonMode, let schema = request.schema {
            let schemaText = String(decoding: try schema.jsonData(), as: UTF8.self)
            system += "\n\nRespond with only a JSON object that matches this JSON schema:\n\(schemaText)"
        }

        let userContent: Any
        if request.images.isEmpty {
            userContent = request.user
        } else {
            var parts: [[String: Any]] = [["type": "text", "text": request.user]]
            for image in request.images {
                parts.append([
                    "type": "image_url",
                    "image_url": ["url": "data:image/jpeg;base64,\(image.jpegData.base64EncodedString())", "detail": image.detail.rawValue],
                ])
            }
            userContent = parts
        }

        var body: [String: Any] = [
            "model": request.model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": userContent],
            ],
        ]
        if let maxOutputTokens = request.maxOutputTokens {
            body["max_completion_tokens"] = maxOutputTokens
        }
        if let schema = request.schema {
            body["response_format"] = jsonMode
                ? ["type": "json_object"]
                : ["type": "json_schema", "json_schema": ["name": request.schemaName, "strict": true, "schema": schema.jsonObject]]
        }
        return body
    }

    private func decode(_ response: HTTPResponse) throws -> TextResult {
        guard (200..<300).contains(response.status) else { throw OpenAIErrorMapper.map(response) }
        struct Completion: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String?
                    let refusal: String?
                }
                let message: Message
                let finish_reason: String?
            }
            struct Usage: Decodable {
                let prompt_tokens: Int?
                let completion_tokens: Int?
            }
            let model: String?
            let choices: [Choice]
            let usage: Usage?
        }
        guard let completion = try? JSONDecoder().decode(Completion.self, from: response.data),
              let choice = completion.choices.first else { throw AIError.invalidResponse }
        if choice.finish_reason == "length" { throw AIError.outputTruncated }
        if choice.message.refusal != nil { throw AIError.badRequest(code: "refusal") }
        guard let content = choice.message.content else { throw AIError.invalidResponse }
        return TextResult(text: content, model: completion.model ?? "", inputTokens: completion.usage?.prompt_tokens, outputTokens: completion.usage?.completion_tokens)
    }
}

// Servers that rejected a strict schema, remembered for the rest of the session.
nonisolated final class JSONModeMemory: Sendable {
    static let shared = JSONModeMemory()
    private let keys = Mutex<Set<String>>([])

    func contains(_ key: String) -> Bool {
        keys.withLock { $0.contains(key) }
    }

    func insert(_ key: String) {
        _ = keys.withLock { $0.insert(key) }
    }
}
