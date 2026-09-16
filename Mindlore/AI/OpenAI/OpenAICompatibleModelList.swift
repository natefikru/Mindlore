import Foundation

// GET /models: a cheap key check that also fills the model pickers.
nonisolated struct OpenAICompatibleModelList: Sendable {
    static let requestTimeout: TimeInterval = 30

    let baseURL: URL
    let apiKey: String
    let http: any HTTPClient

    @concurrent
    func fetch() async throws -> [String] {
        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.httpMethod = "GET"
        request.timeoutInterval = Self.requestTimeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let response = try await http.send(request, body: nil)
        guard (200..<300).contains(response.status) else { throw OpenAIErrorMapper.map(response) }
        struct List: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }
        guard let list = try? JSONDecoder().decode(List.self, from: response.data) else { throw AIError.invalidResponse }
        return list.data.map(\.id).sorted()
    }
}
