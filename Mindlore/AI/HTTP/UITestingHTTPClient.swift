import Foundation
import ImageIO

// Stands in for OpenAI when the app is launched with -uiTestingFakeAI, so UI tests can drive the
// AI screens without the network. Only the test key is accepted.
nonisolated struct UITestingHTTPClient: HTTPClient {
    static let launchArgument = "-uiTestingFakeAI"
    static let validKey = "sk-uitest-valid"
    static let readyArgument = "-uiTestingAIReady"

    func send(_ request: URLRequest, body: Data?) async throws -> HTTPResponse {
        guard request.value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.validKey)" else {
            return HTTPResponse(status: 401, headers: [:], data: Data(#"{"error":{"code":"invalid_api_key"}}"#.utf8))
        }
        let path = request.url?.path ?? ""
        let json: String
        if path.hasSuffix("/models") {
            json = #"{"data":[{"id":"gpt-5.6-luna"},{"id":"gpt-transcribe"}]}"#
        } else if path.hasSuffix("/audio/transcriptions") {
            json = #"{"text":"Transcribed by the UI test stub."}"#
        } else if let body, let text = String(data: body, encoding: .utf8), text.contains("journal_page") {
            // Page transcription: like a real model reading the generated fixture page, answer with the
            // page's own number, recovered from the image width FakePages gave it.
            let number = Self.fixturePageNumber(inRequestBody: text).map(String.init) ?? "?"
            let page = #"{"text":"Fixture page \#(number)","writtenDate":\#(number == "1" ? "\"2025-03-03\"" : "null")}"#
            let completion: [String: Any] = ["model": "stub", "choices": [["message": ["content": page], "finish_reason": "stop"]]]
            json = String(decoding: (try? JSONSerialization.data(withJSONObject: completion)) ?? Data(), as: UTF8.self)
        } else if let body, let text = String(data: body, encoding: .utf8), text.contains("journal_insights") {
            let insights = #"{"summary":"A walk by the river with Sarah.","primaryMood":"calm","secondaryMoods":["grateful"],"themes":["a walk"],"tags":["river"],"mentions":[{"name":"Sarah","kind":"person"},{"name":"Tom","kind":"person"}],"openThreads":["Call the landlord"],"cleanedText":null,"writtenDate":null}"#
            let completion: [String: Any] = ["model": "stub", "choices": [["message": ["content": insights], "finish_reason": "stop"]]]
            json = String(decoding: (try? JSONSerialization.data(withJSONObject: completion)) ?? Data(), as: UTF8.self)
        } else if let body, let text = String(data: body, encoding: .utf8), text.contains(EntityBioDrafter.schemaName) {
            let name = Self.bioName(inRequestBody: text) ?? "Someone"
            let bio = String(decoding: (try? JSONSerialization.data(withJSONObject: ["bio": "\(name) is a friend the writer walks by the river with."])) ?? Data(), as: UTF8.self)
            let completion: [String: Any] = ["model": "stub", "choices": [["message": ["content": bio], "finish_reason": "stop"]]]
            json = String(decoding: (try? JSONSerialization.data(withJSONObject: completion)) ?? Data(), as: UTF8.self)
        } else {
            json = #"{"model":"stub","choices":[{"message":{"content":"Stub Title"},"finish_reason":"stop"}]}"#
        }
        return HTTPResponse(status: 200, headers: [:], data: Data(json.utf8))
    }

    // The bio request's user message starts with "Name: ...".
    static func bioName(inRequestBody body: String) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]],
              let content = messages.first(where: { $0["role"] as? String == "user" })?["content"],
              let user = (content as? String) ?? ((content as? [[String: Any]])?.first?["text"] as? String),
              let line = user.split(separator: "\n").first, line.hasPrefix("Name: ") else { return nil }
        return String(line.dropFirst("Name: ".count))
    }

    // FakePages widths are start + offset * 10, so the last two digits encode the page's position.
    static func fixturePageNumber(inRequestBody body: String) -> Int? {
        guard let json = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]],
              let parts = messages.last?["content"] as? [[String: Any]],
              let url = parts.compactMap({ ($0["image_url"] as? [String: Any])?["url"] as? String }).first,
              let comma = url.firstIndex(of: ",") else { return nil }
        guard let data = Data(base64Encoded: String(url[url.index(after: comma)...])),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int else { return nil }
        return width % 100 / 10 + 1
    }
}
