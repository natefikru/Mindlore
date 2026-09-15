import Foundation

protocol Transcriber {
    func transcribe(audioFileURL: URL, locale: Locale) async throws -> String
}

nonisolated enum TranscriptionError: Error, Equatable {
    case authorizationDenied
    case unsupportedLocale
    case noSpeechDetected
    case assetsUnavailable(String)
    case analysisFailed(String)
    case provider(AIError)

    // Retrying won't help; the user needs to type, change a setting, or fix their account.
    var isPermanent: Bool {
        switch self {
        case .authorizationDenied, .unsupportedLocale, .noSpeechDetected: true
        case .assetsUnavailable, .analysisFailed: false
        case .provider(let error): !error.isRetryable
        }
    }

    var caseName: String {
        switch self {
        case .authorizationDenied: "authorizationDenied"
        case .unsupportedLocale: "unsupportedLocale"
        case .noSpeechDetected: "noSpeechDetected"
        case .assetsUnavailable: "assetsUnavailable"
        case .analysisFailed: "analysisFailed"
        case .provider(let error): "provider.\(error.caseName)"
        }
    }

    init?(caseName: String) {
        switch caseName {
        case "authorizationDenied": self = .authorizationDenied
        case "unsupportedLocale": self = .unsupportedLocale
        case "noSpeechDetected": self = .noSpeechDetected
        case "assetsUnavailable": self = .assetsUnavailable("")
        case "analysisFailed": self = .analysisFailed("")
        default:
            guard caseName.hasPrefix("provider."), let error = AIError(caseName: String(caseName.dropFirst(9))) else { return nil }
            self = .provider(error)
        }
    }

    var userMessage: String {
        switch self {
        case .authorizationDenied:
            "Speech recognition is turned off for Mindlore in Settings. You can type your entry instead."
        case .unsupportedLocale:
            "This device can't turn speech in your language into text yet. You can type your entry instead."
        case .noSpeechDetected:
            "No speech was found in this recording. You can type your entry instead."
        case .assetsUnavailable:
            "The speech model couldn't be downloaded. Check your connection and try again."
        case .analysisFailed:
            "Mindlore couldn't get text from this recording."
        case .provider(let error):
            error.userMessage
        }
    }
}
