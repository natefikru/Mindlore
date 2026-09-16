import Foundation

nonisolated struct HTTPResponse: Sendable {
    let status: Int
    let headers: [String: String]
    let data: Data

    func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

// Transport failures arrive as AIError (offline, network, cancelled). HTTP error statuses are
// returned as responses so each provider can map its own error bodies.
nonisolated protocol HTTPClient: Sendable {
    func send(_ request: URLRequest, body: Data?) async throws -> HTTPResponse
}

nonisolated final class URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    // Called with each request's tracker once the request finishes or fails; tests use it to
    // confirm the delegate callback fired.
    private let onTracked: (@Sendable (TaskTracker) -> Void)?

    init(onTracked: (@Sendable (TaskTracker) -> Void)? = nil) {
        self.onTracked = onTracked
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpCookieStorage = nil
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    @concurrent
    func send(_ request: URLRequest, body: Data?) async throws -> HTTPResponse {
        let tracker = TaskTracker()
        defer { onTracked?(tracker) }
        do {
            let (data, response) = if let body {
                try await session.upload(for: request, from: body, delegate: tracker)
            } else {
                try await session.data(for: request, delegate: tracker)
            }
            guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse }
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                if let key = key as? String, let value = value as? String { headers[key] = value }
            }
            return HTTPResponse(status: http.statusCode, headers: headers, data: data)
        } catch let error as URLError {
            throw AIError.from(error, bytesSent: tracker.bytesSent)
        } catch is CancellationError {
            throw AIError.cancelled
        }
    }
}

// Captures the task so a failure can tell whether any bytes reached the network.
nonisolated final class TaskTracker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        lock.withLock { self.task = task }
    }

    var bytesSent: Int64 {
        lock.withLock { task?.countOfBytesSent ?? 0 }
    }

    var sawTask: Bool {
        lock.withLock { task != nil }
    }
}
