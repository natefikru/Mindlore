import Foundation
import Synchronization

nonisolated struct HTTPResponse: Sendable {
    let status: Int
    let headers: [String: String]
    let data: Data

    func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

// What a streaming request turned out to be, decided from the status line before a single body
// byte is handed on. An error status is not a stream: its body is collected and comes back as an
// ordinary response, so the provider maps it with exactly the code that maps a single-shot one.
nonisolated enum HTTPStream: Sendable {
    case body(AsyncThrowingStream<Data, any Error>)
    case response(HTTPResponse)
}

// Transport failures arrive as AIError (offline, network, cancelled). HTTP error statuses are
// returned as responses so each provider can map its own error bodies.
nonisolated protocol HTTPClient: Sendable {
    func send(_ request: URLRequest, body: Data?) async throws -> HTTPResponse
    func stream(_ request: URLRequest, body: Data?) async throws -> HTTPStream
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

    // No frame for this long and the stream is dead. Without it a server that accepts the request
    // and then stalls holds a half-written answer on screen until the 300s request timeout.
    static let idleTimeout: Duration = .seconds(30)
    private static let idleCheckInterval: Duration = .seconds(1)
    // An error body is bounded: past this there is nothing left worth reading a code out of.
    private static let maximumErrorBytes = 64 * 1024

    @concurrent
    func stream(_ request: URLRequest, body: Data?) async throws -> HTTPStream {
        let tracker = TaskTracker()
        var request = request
        request.httpBody = body
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: tracker)
            guard let http = response as? HTTPURLResponse else {
                onTracked?(tracker)
                throw AIError.invalidResponse
            }
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                if let key = key as? String, let value = value as? String { headers[key] = value }
            }
            guard (200..<300).contains(http.statusCode) else {
                var data = Data()
                for try await byte in bytes {
                    data.append(byte)
                    if data.count >= Self.maximumErrorBytes { break }
                }
                onTracked?(tracker)
                return .response(HTTPResponse(status: http.statusCode, headers: headers, data: data))
            }
            return .body(Self.frames(of: bytes, tracker: tracker, onTracked: onTracked))
        } catch let error as URLError {
            onTracked?(tracker)
            throw AIError.from(error, bytesSent: tracker.bytesSent)
        } catch is CancellationError {
            onTracked?(tracker)
            throw AIError.cancelled
        }
    }

    private struct StreamProgress {
        var lastFrame = ContinuousClock.now
        var isFinished = false
    }

    // Server-sent events are line-delimited, so a line is the chunk: the buffer never grows past
    // one, and the parser downstream still assumes nothing about where a read happens to split.
    private static func frames(
        of bytes: URLSession.AsyncBytes,
        tracker: TaskTracker,
        onTracked: (@Sendable (TaskTracker) -> Void)?
    ) -> AsyncThrowingStream<Data, any Error> {
        AsyncThrowingStream { continuation in
            let progress = Mutex(StreamProgress())
            let pump = Task {
                do {
                    var buffer: [UInt8] = []
                    for try await byte in bytes {
                        buffer.append(byte)
                        guard byte == 0x0A else { continue }
                        progress.withLock { $0.lastFrame = .now }
                        continuation.yield(Data(buffer))
                        buffer.removeAll(keepingCapacity: true)
                    }
                    if !buffer.isEmpty { continuation.yield(Data(buffer)) }
                    progress.withLock { $0.isFinished = true }
                    continuation.finish()
                } catch let error as URLError {
                    progress.withLock { $0.isFinished = true }
                    continuation.finish(throwing: AIError.from(error, bytesSent: tracker.bytesSent))
                } catch is CancellationError {
                    progress.withLock { $0.isFinished = true }
                    continuation.finish(throwing: AIError.cancelled)
                } catch {
                    progress.withLock { $0.isFinished = true }
                    continuation.finish(throwing: AIError.invalidResponse)
                }
                onTracked?(tracker)
            }
            // Finishing the stream terminates it, which cancels the pump through onTermination
            // below, so the watchdog never has to reach for the other task.
            let watchdog = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: idleCheckInterval)
                    guard !Task.isCancelled else { return }
                    let stalled = progress.withLock { progress -> Bool in
                        !progress.isFinished && progress.lastFrame.duration(to: .now) > idleTimeout
                    }
                    if stalled {
                        continuation.finish(throwing: AIError.network(.timedOut))
                        return
                    }
                }
            }
            continuation.onTermination = { _ in
                pump.cancel()
                watchdog.cancel()
            }
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
