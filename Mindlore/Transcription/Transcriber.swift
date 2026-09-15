import Foundation

protocol Transcriber {
    func transcribe(audioFileURL: URL, locale: Locale) async throws -> String
}

nonisolated enum TranscriptionError: Error, Equatable {
    case authorizationDenied
    case unsupportedLocale
    case assetsUnavailable(String)
    case analysisFailed(String)

    // Retrying won't help; the user needs to type or change a system setting.
    var isPermanent: Bool {
        switch self {
        case .authorizationDenied, .unsupportedLocale: true
        case .assetsUnavailable, .analysisFailed: false
        }
    }

    var userMessage: String {
        switch self {
        case .authorizationDenied:
            "Speech recognition is turned off for Mindlore in Settings. You can type your entry instead."
        case .unsupportedLocale:
            "This device can't turn speech in your language into text yet. You can type your entry instead."
        case .assetsUnavailable:
            "The speech model couldn't be downloaded. Check your connection and try again."
        case .analysisFailed:
            "Mindlore couldn't get text from this recording."
        }
    }
}
