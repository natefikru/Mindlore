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

// Tells a failure whether any bytes reached the network. `countOfBytesSent` alone cannot: it only
// moves when a progress report is delivered, and an upload that finishes or dies first leaves it
// at 0 for good (141 of 300 successful 20 KB uploads, 75 of 100 closed mid-upload, measured on the
// simulator 2026-09-19, still 0 100 ms later). The task's metrics had landed before the call
// returned in all 400, and count the header bytes too, so they are the floor and the live counter
// only covers a task whose metrics never came.
nonisolated final class TaskTracker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?
    private var metricsBytesSent: Int64 = 0

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        lock.withLock { self.task = task }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        let sent = metrics.transactionMetrics.reduce(Int64(0)) {
            $0 + $1.countOfRequestHeaderBytesSent + $1.countOfRequestBodyBytesSent
        }
        lock.withLock { metricsBytesSent = sent }
    }

    var bytesSent: Int64 {
        lock.withLock { max(metricsBytesSent, task?.countOfBytesSent ?? 0) }
    }

    var sawTask: Bool {
        lock.withLock { task != nil }
    }
}
