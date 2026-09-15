import Foundation

// Stands in for OpenAI when the app is launched with -uiTestingFakeAI, so UI tests can drive the
// AI screens without the network. Only the test key is accepted.
nonisolated struct UITestingHTTPClient: HTTPClient {
    static let launchArgument = "-uiTestingFakeAI"
    static let validKey = "sk-uitest-valid"

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
        } else {
            json = #"{"model":"stub","choices":[{"message":{"content":"Stub Title"},"finish_reason":"stop"}]}"#
        }
        return HTTPResponse(status: 200, headers: [:], data: Data(json.utf8))
    }
}
