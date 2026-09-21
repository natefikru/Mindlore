import Foundation
import Network
import Synchronization
import Testing
@testable import Mindlore

// A tiny HTTP server on 127.0.0.1 so the real URLSession path can be exercised without the internet.
nonisolated final class LocalHTTPServer: @unchecked Sendable {
    enum Behavior: Sendable {
        case respond(status: Int, body: String)
        // Reads some of the request, then closes the connection.
        case closeAfterReading
        // Reads the request and never answers.
        case neverRespond
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "LocalHTTPServer")
    private let received = Mutex<Int>(0)
    private let connections = Mutex<[NWConnection]>([])

    var port: UInt16 { listener.port?.rawValue ?? 0 }
    var url: URL { URL(string: "http://127.0.0.1:\(port)")! }
    var bytesReceived: Int { received.withLock { $0 } }

    init(_ behavior: Behavior) async throws {
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [unowned self] connection in
            self.connections.withLock { $0.append(connection) }
            connection.start(queue: self.queue)
            self.read(connection, behavior: behavior)
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumed = Mutex(false)
            listener.stateUpdateHandler = { state in
                if case .ready = state, !resumed.withLock({ let was = $0; $0 = true; return was }) {
                    continuation.resume()
                }
            }
            listener.start(queue: queue)
        }
    }

    private func read(_ connection: NWConnection, behavior: Behavior) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64_000) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let data { self.received.withLock { $0 += data.count } }
            switch behavior {
            case .respond(let status, let body):
                let response = "HTTP/1.1 \(status) OK\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            case .closeAfterReading:
                connection.cancel()
            case .neverRespond:
                if error == nil && !complete { self.read(connection, behavior: behavior) }
            }
        }
    }

    func stop() {
        listener.cancel()
        connections.withLock { $0.forEach { $0.cancel() } }
    }
}

// Real URLSession against a local server. Proves the offline rule on actual transport errors.
@Suite(.serialized)
struct URLSessionHTTPClientTests {
    private func request(_ url: URL, timeout: TimeInterval = 10) -> URLRequest {
        var request = URLRequest(url: url.appendingPathComponent("v1/models"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        return request
    }

    @Test func successfulResponseAndTheTrackerSeesTheBytesSent() async throws {
        let server = try await LocalHTTPServer(.respond(status: 200, body: #"{"data":[]}"#))
        defer { server.stop() }
        let trackers = Mutex<[TaskTracker]>([])
        let client = URLSessionHTTPClient(onTracked: { tracker in trackers.withLock { $0.append(tracker) } })

        let response = try await client.send(request(server.url), body: Data(repeating: 65, count: 20_000))

        #expect(response.status == 200)
        #expect(String(decoding: response.data, as: UTF8.self) == #"{"data":[]}"#)
        let tracker = try #require(trackers.withLock { $0.first })
        #expect(tracker.sawTask)
        #expect(tracker.bytesSent >= 20_000)
    }

    @Test func httpErrorStatusesAreReturnedNotThrown() async throws {
        let server = try await LocalHTTPServer(.respond(status: 401, body: #"{"error":{"code":"invalid_api_key"}}"#))
        defer { server.stop() }

        let response = try await URLSessionHTTPClient().send(request(server.url), body: nil)

        #expect(response.status == 401)
        #expect(OpenAIErrorMapper.map(response) == .invalidKey)
    }

    @Test func refusedConnectionIsOffline() async throws {
        // Start and stop a server to get a port that is definitely closed.
        let server = try await LocalHTTPServer(.neverRespond)
        let url = server.url
        server.stop()
        try await Task.sleep(for: .milliseconds(200))

        await #expect(throws: AIError.offline(.cannotConnectToHost)) {
            try await URLSessionHTTPClient().send(request(url), body: Data(repeating: 1, count: 10))
        }
    }

    @Test func connectionClosedMidUploadIsNotOffline() async throws {
        let server = try await LocalHTTPServer(.closeAfterReading)
        defer { server.stop() }

        let trackers = Mutex<[TaskTracker]>([])
        let client = URLSessionHTTPClient(onTracked: { tracker in trackers.withLock { $0.append(tracker) } })

        do {
            _ = try await client.send(request(server.url), body: Data(repeating: 2, count: 2_000_000))
            Issue.record("Expected the upload to fail")
        } catch let error as AIError {
            #expect(!error.isOffline, "got \(error)")
            #expect(error.isRetryable)
        }
        // The server read part of the request before closing, so the tracker must not say 0: that
        // is the reading that would let a never-connected code pass for offline.
        let tracker = try #require(trackers.withLock { $0.first })
        #expect(tracker.bytesSent > 0)
    }

    @Test func serverThatNeverAnswersTimesOut() async throws {
        let server = try await LocalHTTPServer(.neverRespond)
        defer { server.stop() }

        await #expect(throws: AIError.network(.timedOut)) {
            try await URLSessionHTTPClient().send(request(server.url, timeout: 1), body: Data(repeating: 3, count: 100))
        }
    }
}
