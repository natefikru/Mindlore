import AVFoundation
import Foundation
import Testing
@testable import Mindlore

@MainActor
struct AIJobPolicyTests {
    private func pendingInsights() -> Entry {
        let entry = Entry(text: "hello")
        entry.insightsPending = true
        return entry
    }

    @Test func runsWhilePendingUnderTheCapWithNoPermanentFailure() {
        let entry = pendingInsights()
        #expect(AIJobPolicy.canRunAutomatically(.insights, entry))

        AIJobPolicy.recordAttempt(.insights, entry)
        AIJobPolicy.recordFailure(.insights, entry, AIJobFailure(.serverError(status: 500)))
        #expect(entry.insightsAttempts == 1)
        #expect(entry.insightsPending)
        #expect(AIJobPolicy.canRunAutomatically(.insights, entry))

        AIJobPolicy.recordAttempt(.insights, entry)
        AIJobPolicy.recordFailure(.insights, entry, AIJobFailure(.serverError(status: 500)))
        #expect(entry.insightsAttempts == 2)
        #expect(!entry.insightsPending)
        #expect(!AIJobPolicy.canRunAutomatically(.insights, entry))
    }

    @Test func permanentFailureStopsImmediately() {
        let entry = pendingInsights()
        AIJobPolicy.recordAttempt(.insights, entry)
        AIJobPolicy.recordFailure(.insights, entry, AIJobFailure(.invalidKey))

        #expect(!entry.insightsPending)
        #expect(entry.insightsFailureRaw == "ai.invalidKey")
        #expect(!AIJobPolicy.canRunAutomatically(.insights, entry))
    }

    @Test func offlineFailureDoesNotCountAnAttempt() {
        let entry = pendingInsights()
        AIJobPolicy.recordAttempt(.insights, entry)
        AIJobPolicy.recordFailure(.insights, entry, AIJobFailure(.offline(.notConnectedToInternet)))

        #expect(entry.insightsAttempts == 0)
        #expect(entry.insightsPending)
        #expect(AIJobPolicy.canRunAutomatically(.insights, entry))
    }

    @Test func textKeepsAwaitingTextAfterAPermanentFailure() {
        let entry = Entry(source: .voice, awaitingText: true, audioData: Data([1]))
        AIJobPolicy.recordAttempt(.text, entry)
        AIJobPolicy.recordFailure(.text, entry, AIJobFailure(TranscriptionError.noSpeechDetected))

        #expect(entry.awaitingText)
        #expect(entry.textFailureRaw == "speech.noSpeechDetected")
        #expect(!AIJobPolicy.canRunAutomatically(.text, entry))
    }

    @Test func textCapIsThree() {
        let entry = Entry(source: .voice, awaitingText: true, audioData: Data([1]))
        for _ in 0..<3 {
            #expect(AIJobPolicy.canRunAutomatically(.text, entry))
            AIJobPolicy.recordAttempt(.text, entry)
            AIJobPolicy.recordFailure(.text, entry, AIJobFailure(.network(.timedOut)))
        }
        #expect(!AIJobPolicy.canRunAutomatically(.text, entry))
    }

    @Test func successAndManualResetClearState() {
        let entry = pendingInsights()
        AIJobPolicy.recordAttempt(.insights, entry)
        AIJobPolicy.recordFailure(.insights, entry, AIJobFailure(.quotaExceeded))

        AIJobPolicy.manualReset(.insights, entry)
        #expect(entry.insightsPending && entry.insightsAttempts == 0 && entry.insightsFailureRaw == nil)

        AIJobPolicy.recordAttempt(.insights, entry)
        AIJobPolicy.recordSuccess(.insights, entry)
        #expect(!entry.insightsPending && entry.insightsAttempts == 0 && entry.insightsFailureRaw == nil)
    }

    @Test func storedFailuresReadBack() {
        #expect(AIJobFailure(raw: "ai.rateLimited").isRetryable)
        #expect(!AIJobFailure(raw: "ai.invalidKey").isRetryable)
        #expect(AIJobFailure(raw: "ai.offline").isOffline)
        #expect(AIJobFailure(raw: "speech.assetsUnavailable").isRetryable)
        #expect(!AIJobFailure(raw: "speech.authorizationDenied").isRetryable)
        #expect(!AIJobFailure(raw: "garbage").isRetryable)
        #expect(AIJobFailure(TranscriptionError.provider(.quotaExceeded)).raw == "ai.quotaExceeded")
        #expect(AIJobFailure(any: CocoaError(.fileReadNoPermission)).raw == "speech.analysisFailed")
        #expect(AIJobFailure(raw: "ai.invalidKey").userMessage == AIError.invalidKey.userMessage)
    }
}

struct AudioChunkerTests {
    @Test func shortAudioIsNotSplit() {
        #expect(AudioChunker.boundaries(levels: Array(repeating: 1, count: 100), duration: 5, targetSeconds: 10, searchSeconds: 2).isEmpty)
    }

    @Test func cutsLandInTheQuietestWindowNearEachTarget() {
        // 30 s of sound with silence at 9.0-9.5 s and 21.0-21.5 s.
        let windows = 600
        var levels = Array(repeating: Float(0.5), count: windows)
        for index in 180..<190 { levels[index] = 0.01 }
        for index in 420..<430 { levels[index] = 0.02 }

        let cuts = AudioChunker.boundaries(levels: levels, duration: 30, targetSeconds: 10, searchSeconds: 2)

        #expect(cuts.count == 2)
        #expect((9.0...9.5).contains(cuts[0]))
        #expect((21.0...21.5).contains(cuts[1]))
    }

    @Test func withNoQuietSpotItStillCutsNearTheTarget() {
        let cuts = AudioChunker.boundaries(levels: Array(repeating: 0.5, count: 400), duration: 20, targetSeconds: 8, searchSeconds: 1)
        #expect(cuts.count == 2)
        #expect(cuts.allSatisfy { $0 > 0 && $0 < 20 })
        #expect(abs(cuts[0] - 8) <= 1.05)
    }

    private func writeToneSilenceTone(to url: URL) throws {
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 24_000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatInt16, interleaved: true)
        let frames = AVAudioFrameCount(7 * 24_000)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames)!
        buffer.frameLength = frames
        for index in 0..<Int(frames) {
            let seconds = Double(index) / 24_000
            let silent = seconds >= 3 && seconds < 4
            buffer.int16ChannelData![0][index] = silent ? 0 : Int16(sin(Double(index) / 8) * 8_000)
        }
        try file.write(from: buffer)
    }

    @Test func splitsARealFileInItsSilenceAndKeepsTheWholeDuration() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let caf = directory.appendingPathComponent("source.caf")
        try writeToneSilenceTone(to: caf)
        let m4a = directory.appendingPathComponent("source.m4a")
        try AudioConverter.convertToAAC(caf).data.write(to: m4a)

        let chunks = try await AudioChunker.split(m4a, targetSeconds: 4, searchSeconds: 1, outputDirectory: directory)

        #expect(chunks.count == 2)
        #expect((3.0...4.0).contains(chunks[0].duration))
        #expect(abs(chunks.map(\.duration).reduce(0, +) - 7) < 0.2)
        for chunk in chunks {
            let file = try AVAudioFile(forReading: chunk.url)
            #expect(Double(file.length) / file.fileFormat.sampleRate > 2.5)
        }
    }
}

@MainActor
struct AbandonedRequestTests {
    @Test func aCancelledRequestDoesNotSpendAnAttemptOrEndTheJob() {
        let entry = Entry(text: "text")
        entry.insightsPending = true
        AIJobPolicy.recordAttempt(.insights, entry)
        AIJobPolicy.recordFailure(.insights, entry, AIJobFailure(.cancelled))

        // Backgrounding mid-request must not cost the entry its one automatic run.
        #expect(entry.insightsAttempts == 0)
        #expect(entry.insightsPending)
        #expect(AIJobPolicy.canRunAutomatically(.insights, entry))
    }

    @Test func offlineAndCancelledAreTheAbandonedCases() {
        #expect(AIError.offline(.notConnectedToInternet).wasAbandoned)
        #expect(AIError.cancelled.wasAbandoned)
        #expect(AIError.cancelled.isRetryable)
        #expect(!AIError.network(.timedOut).wasAbandoned)
        #expect(!AIError.invalidKey.wasAbandoned)
        #expect(AIJobFailure(.cancelled).wasAbandoned)
    }
}
