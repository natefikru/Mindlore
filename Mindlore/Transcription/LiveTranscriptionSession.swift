import AVFoundation
import Foundation

// A transcriber fed audio as it is captured, rather than a finished file.
//
// Volatile and finalized text are separate on purpose: volatile is a guess that gets rewritten on
// every result, finalized is committed and only ever grows. Appending one to the other duplicates
// words, so the view joins them for display and only finalized text is ever kept.
@MainActor
protocol LiveTranscriptionSession: AnyObject {
    var volatileText: String { get }
    var finalizedText: String { get }
    // False once any audio failed to reach the transcriber. An unhealthy session's text covers
    // less than the recording, so the caller throws it away and transcribes the file instead.
    var isHealthy: Bool { get }

    func start() async throws
    func feed(_ buffer: AVAudioPCMBuffer)
    // Marks the session unusable without ending it, for an interruption the user may resume through.
    func markUnhealthy(_ reason: String)
    // Returns the finalized text, or nil if the session can't be trusted or heard nothing.
    func finish() async -> String?
}

extension LiveTranscriptionSession {
    // What the recording screen shows: committed text with the current guess trailing it.
    var displayText: String {
        guard !volatileText.isEmpty else { return finalizedText }
        guard !finalizedText.isEmpty else { return volatileText }
        return finalizedText + " " + volatileText
    }
}
