import Foundation

// Every failure on an AI path becomes one of these before it is logged, stored, or shown.
// Cases carry codes only: provider error bodies and decoding errors can quote entry text.
nonisolated enum AIError: Error, Equatable, Sendable {
    case missingKey
    case invalidKey
    case permissionDenied
    case rateLimited(retryAfter: TimeInterval?)
    case quotaExceeded
    case requestTooLarge
    case contextTooLong
    case badRequest(code: String?)
    case serverError(status: Int)
    // Nothing reached the server, so nothing was billed.
    case offline(URLError.Code)
    // The connection failed after bytes went out; the provider may have billed the request.
    case network(URLError.Code)
    case outputTruncated
    case invalidResponse
    case cancelled

    var isRetryable: Bool {
        switch self {
        case .rateLimited, .serverError, .offline, .network: true
        default: false
        }
    }

    var isOffline: Bool {
        if case .offline = self { true } else { false }
    }

    // Stored on entries and logged. Stable strings; never includes provider text.
    var caseName: String {
        switch self {
        case .missingKey: "missingKey"
        case .invalidKey: "invalidKey"
        case .permissionDenied: "permissionDenied"
        case .rateLimited: "rateLimited"
        case .quotaExceeded: "quotaExceeded"
        case .requestTooLarge: "requestTooLarge"
        case .contextTooLong: "contextTooLong"
        case .badRequest: "badRequest"
        case .serverError: "serverError"
        case .offline: "offline"
        case .network: "network"
        case .outputTruncated: "outputTruncated"
        case .invalidResponse: "invalidResponse"
        case .cancelled: "cancelled"
        }
    }

    init?(caseName: String) {
        switch caseName {
        case "missingKey": self = .missingKey
        case "invalidKey": self = .invalidKey
        case "permissionDenied": self = .permissionDenied
        case "rateLimited": self = .rateLimited(retryAfter: nil)
        case "quotaExceeded": self = .quotaExceeded
        case "requestTooLarge": self = .requestTooLarge
        case "contextTooLong": self = .contextTooLong
        case "badRequest": self = .badRequest(code: nil)
        case "serverError": self = .serverError(status: 500)
        case "offline": self = .offline(.notConnectedToInternet)
        case "network": self = .network(.networkConnectionLost)
        case "outputTruncated": self = .outputTruncated
        case "invalidResponse": self = .invalidResponse
        case "cancelled": self = .cancelled
        default: return nil
        }
    }

    var userMessage: String {
        switch self {
        case .missingKey: "Add your OpenAI API key in Settings to use AI."
        case .invalidKey: "OpenAI didn't accept your API key. Check it in Settings."
        case .permissionDenied: "Your OpenAI key doesn't have access to this model."
        case .rateLimited: "OpenAI is limiting requests right now. Mindlore will try again later."
        case .quotaExceeded: "Your OpenAI account is out of credit or over its usage limit."
        case .requestTooLarge: "This was too large to send to OpenAI."
        case .contextTooLong: "This entry is too long for the selected model."
        case .badRequest: "OpenAI couldn't process this request."
        case .serverError: "OpenAI had a problem. Mindlore will try again later."
        case .offline: "You're offline. Mindlore will try again when you're connected."
        case .network: "The connection to OpenAI was interrupted. Mindlore will try again later."
        case .outputTruncated: "The response was cut off before it finished."
        case .invalidResponse: "OpenAI sent a response Mindlore couldn't read."
        case .cancelled: "The request was cancelled."
        }
    }

    // A URL error becomes `offline` only if the code means no connection and no bytes were sent.
    static func from(_ error: URLError, bytesSent: Int64) -> AIError {
        let neverConnected: Set<URLError.Code> = [
            .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost,
            .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed,
        ]
        if error.code == .cancelled { return .cancelled }
        if neverConnected.contains(error.code) && bytesSent == 0 { return .offline(error.code) }
        return .network(error.code)
    }
}
