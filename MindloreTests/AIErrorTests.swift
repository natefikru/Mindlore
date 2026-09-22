import Foundation
import Testing
@testable import Mindlore

struct AIErrorTests {
    @Test func noConnectionWithNothingSentIsOffline() {
        #expect(AIError.from(URLError(.notConnectedToInternet), bytesSent: 0) == .offline(.notConnectedToInternet))
        #expect(AIError.from(URLError(.cannotFindHost), bytesSent: 0) == .offline(.cannotFindHost))
    }

    @Test func connectionLostAfterBytesWentOutIsNetwork() {
        // The provider may have received and billed the request.
        #expect(AIError.from(URLError(.notConnectedToInternet), bytesSent: 4_096) == .network(.notConnectedToInternet))
        #expect(AIError.from(URLError(.timedOut), bytesSent: 0) == .network(.timedOut))
        #expect(AIError.from(URLError(.networkConnectionLost), bytesSent: 0) == .network(.networkConnectionLost))
    }

    @Test func cancellationIsItsOwnCase() {
        #expect(AIError.from(URLError(.cancelled), bytesSent: 0) == .cancelled)
    }

    @Test func retryableCases() {
        #expect(AIError.rateLimited(retryAfter: nil).isRetryable)
        #expect(AIError.serverError(status: 502).isRetryable)
        #expect(AIError.offline(.notConnectedToInternet).isRetryable)
        #expect(AIError.network(.timedOut).isRetryable)
        for permanent: AIError in [.invalidKey, .permissionDenied, .quotaExceeded, .outputTruncated, .invalidResponse, .contextTooLong, .badRequest(code: nil), .missingKey] {
            #expect(!permanent.isRetryable, "\(permanent.caseName)")
        }
    }

    @Test func caseNamesRoundTrip() {
        let all: [AIError] = [.missingKey, .keyUnavailable, .invalidKey, .permissionDenied, .rateLimited(retryAfter: 3), .quotaExceeded, .requestTooLarge, .contextTooLong, .badRequest(code: "x"), .serverError(status: 503), .offline(.cannotFindHost), .network(.timedOut), .outputTruncated, .invalidResponse, .cancelled]
        for error in all {
            #expect(AIError(caseName: error.caseName)?.caseName == error.caseName)
        }
        #expect(AIError(caseName: "nonsense") == nil)
    }

    @Test func statusesMapToErrors() {
        func map(_ result: Result<HTTPResponse, AIError>) -> AIError { OpenAIErrorMapper.map(try! result.get()) }
        #expect(map(FakeHTTPClient.error(401, code: "invalid_api_key")) == .invalidKey)
        #expect(map(FakeHTTPClient.error(403)) == .permissionDenied)
        #expect(map(FakeHTTPClient.error(413)) == .requestTooLarge)
        #expect(map(FakeHTTPClient.error(429, code: "insufficient_quota", type: "insufficient_quota")) == .quotaExceeded)
        #expect(map(FakeHTTPClient.json(429, ["error": ["code": "rate_limit_exceeded"]], headers: ["Retry-After": "20"])) == .rateLimited(retryAfter: 20))
        #expect(map(FakeHTTPClient.error(400, code: "context_length_exceeded")) == .contextTooLong)
        #expect(map(FakeHTTPClient.error(400, code: "invalid_value")) == .badRequest(code: "invalid_value"))
        #expect(map(FakeHTTPClient.error(404, code: "model_not_found")) == .badRequest(code: "model_not_found"))
        #expect(map(FakeHTTPClient.error(503)) == .serverError(status: 503))
        #expect(map(.success(HTTPResponse(status: 400, headers: [:], data: Data("not json".utf8)))) == .badRequest(code: "http_400"))
    }
}
