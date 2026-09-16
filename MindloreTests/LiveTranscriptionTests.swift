import AVFoundation
import Foundation
import Testing
@testable import Mindlore

// Tier 1 itself only runs on a device, so what's testable here is everything around it: when the
// app decides to run it, the buffer conversion that silently produces no text when it's wrong,
// and the file sink that must keep working whatever transcription does.

@MainActor
struct LiveTranscriptionAvailabilityTests {
    private func availability(
        transcriber: Bool = true,
        locale: Locale? = Locale(identifier: "en_US"),
        asset: Bool = true
    ) -> LiveTranscriptionAvailability {
        LiveTranscriptionAvailability(
            transcriberAvailable: { transcriber },
            supportedLocale: { _ in locale },
            assetInstalled: { _ in asset }
        )
    }

    @Test func liveRunsWhenEverythingIsInPlace() async {
        let outcome = await availability().outcome(engine: .onDeviceLive, locale: .current)
        #expect(outcome == .available)
    }

    @Test func pickingBatchOnDeviceNeverStartsALiveSession() async {
        // Someone on a capable phone who chose onDevice asked not to watch text move as they speak.
        let outcome = await availability().outcome(engine: .onDevice, locale: .current)
        #expect(outcome == .unavailable(.notChosen))
    }

    @Test func pickingOpenAINeverStartsALiveSession() async {
        let outcome = await availability().outcome(engine: .cloud, locale: .current)
        #expect(outcome == .unavailable(.notChosen))
    }

    @Test func unavailableTranscriberFallsBackBeforeCheckingAnythingElse() async {
        let outcome = await availability(transcriber: false).outcome(engine: .onDeviceLive, locale: .current)
        #expect(outcome == .unavailable(.transcriberUnavailable))
    }

    @Test func unsupportedLocaleFallsBack() async {
        let outcome = await availability(locale: nil).outcome(engine: .onDeviceLive, locale: .current)
        #expect(outcome == .unavailable(.localeUnsupported))
    }

    // A first-run download must never be something a recording waits on.
    @Test func missingAssetFallsBackForThisRecording() async {
        let outcome = await availability(asset: false).outcome(engine: .onDeviceLive, locale: .current)
        #expect(outcome == .unavailable(.assetNotInstalled))
    }

    @Test func resolvedLocaleIsNilWithoutATranscriber() async {
        #expect(await availability(transcriber: false).resolvedLocale(.current) == nil)
        #expect(await availability().resolvedLocale(.current) == Locale(identifier: "en_US"))
    }
}

struct BufferConverterTests {
    private func tone(sampleRate: Double, frames: AVAudioFrameCount, channels: AVAudioChannelCount = 1) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<Int(channels) {
            for frame in 0..<Int(frames) {
                buffer.floatChannelData![channel][frame] = Float(sin(Double(frame) / 8) * 0.5)
            }
        }
        return buffer
    }

    // The gotcha this whole type exists for: the mic's format is not the one either consumer wants,
    // and feeding a mismatched buffer transcribes nothing without raising an error.
    @Test func resamplesFromTheHardwareRateToTheRecordingRate() throws {
        let converter = BufferConverter(to: RecordingWriter.processingFormat)
        let converted = try converter.convert(tone(sampleRate: 48_000, frames: 4_800))

        #expect(converted.format.sampleRate == 24_000)
        #expect(converted.format.channelCount == 1)
        // The resampler holds part of each buffer back, so one call gives out less than half.
        // What it held comes out of flush().
        let drained = try converter.flush().reduce(0) { $0 + Int($1.frameLength) }
        #expect(converted.frameLength < 2_400)
        #expect(abs(Int(converted.frameLength) + drained - 2_400) <= 32)
    }

    // Without the drain, the audio the resampler is still holding when the user taps Done never
    // reaches the file: up to a tenth of a second, often the last word.
    @Test func flushReturnsEverythingTheResamplerHeldBack() throws {
        let converter = BufferConverter(to: RecordingWriter.processingFormat)
        var total = 0
        for _ in 0..<6 {
            total += Int(try converter.convert(tone(sampleRate: 48_000, frames: 4_800)).frameLength)
        }
        let heldBack = 14_400 - total
        #expect(heldBack > 0)

        total += try converter.flush().reduce(0) { $0 + Int($1.frameLength) }
        #expect(abs(total - 14_400) <= 32)
    }

    @Test func flushingAnUnusedConverterGivesNothing() throws {
        #expect(try BufferConverter(to: RecordingWriter.processingFormat).flush().isEmpty)
    }

    @Test func downmixesStereoInput() throws {
        let converter = BufferConverter(to: RecordingWriter.processingFormat)
        let converted = try converter.convert(tone(sampleRate: 48_000, frames: 4_800, channels: 2))

        #expect(converted.format.channelCount == 1)
        #expect(converted.frameLength > 0)
    }

    @Test func amatchingFormatIsPassedStraightThrough() throws {
        let converter = BufferConverter(to: RecordingWriter.processingFormat)
        let buffer = tone(sampleRate: 24_000, frames: 1_200)
        #expect(try converter.convert(buffer) === buffer)
    }

    // One converter is reused across buffers so the resampler keeps its state; a new one per
    // buffer clicks at every boundary and throws away what each one was holding.
    @Test func repeatedConversionsKeepProducingAudio() throws {
        let converter = BufferConverter(to: RecordingWriter.processingFormat)
        for _ in 0..<10 {
            let converted = try converter.convert(tone(sampleRate: 48_000, frames: 4_800))
            #expect(converted.frameLength >= 2_000)
        }
    }
}

@MainActor
struct RecordingWriterTests {
    private func makeWriter() throws -> (RecordingWriter, AsyncStream<AVAudioPCMBuffer>, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecordingWriterTests-\(UUID().uuidString)")
            .appendingPathExtension("caf")
        let (stream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream(bufferingPolicy: .unbounded)
        return (try RecordingWriter(url: url, continuation: continuation), stream, url)
    }

    private func tone(sampleRate: Double = 48_000, frames: AVAudioFrameCount = 4_800, amplitude: Float = 0.5) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for frame in 0..<Int(frames) {
            buffer.floatChannelData![0][frame] = Float(sin(Double(frame) / 8)) * amplitude
        }
        return buffer
    }

    // The file is the thing that must never be lost, so it gets checked by reading it back.
    @Test func writesTheSameFormatTheIngestorExpects() throws {
        let (writer, _, url) = try makeWriter()
        defer { try? FileManager.default.removeItem(at: url) }

        for _ in 0..<5 { writer.append(tone()) }
        writer.finish()

        let file = try AVAudioFile(forReading: url)
        #expect(file.fileFormat.sampleRate == 24_000)
        #expect(file.fileFormat.channelCount == 1)
        // Five 100ms buffers at 48 kHz become half a second at 24 kHz, all of it, including what the
        // resampler was still holding when the recording ended.
        #expect(abs(file.length - 12_000) <= 32)
        #expect(abs(writer.seconds - 0.5) < 0.002)
        #expect(writer.writeFailure == nil)
    }

    // The transcriber must hear exactly what the file holds, the drained tail included, or the
    // last word is in the recording but not in the text.
    @Test func passesEveryWrittenFrameOnForTranscription() async throws {
        let (writer, stream, url) = try makeWriter()
        defer { try? FileManager.default.removeItem(at: url) }

        for _ in 0..<3 { writer.append(tone()) }
        writer.finish()

        var frames: AVAudioFramePosition = 0
        for await buffer in stream {
            // Buffers reach the transcriber already converted, at the recording's own rate.
            #expect(buffer.format.sampleRate == 24_000)
            frames += AVAudioFramePosition(buffer.frameLength)
        }
        #expect(frames == (try AVAudioFile(forReading: url)).length)
    }

    @Test func pausedAudioReachesNeitherTheFileNorTheTranscriber() async throws {
        let (writer, stream, url) = try makeWriter()
        defer { try? FileManager.default.removeItem(at: url) }

        writer.append(tone())
        writer.setPaused(true)
        for _ in 0..<5 { writer.append(tone()) }
        writer.setPaused(false)
        writer.append(tone())
        writer.finish()

        var frames: AVAudioFramePosition = 0
        for await buffer in stream { frames += AVAudioFramePosition(buffer.frameLength) }
        // Two buffers' worth, the paused five never made it anywhere.
        #expect(abs(writer.seconds - 0.2) < 0.002)
        #expect(frames == (try AVAudioFile(forReading: url)).length)
    }

    // Nobody reads the stream on a recording that isn't being transcribed live, and an unbounded
    // queue of 24 kHz buffers costs about 6 MB a minute for the whole recording.
    @Test func droppingTheTranscriberKeepsWritingTheFile() async throws {
        let (writer, stream, url) = try makeWriter()
        defer { try? FileManager.default.removeItem(at: url) }

        writer.append(tone())
        writer.stopStreaming()
        for _ in 0..<5 { writer.append(tone()) }
        writer.finish()

        var received = 0
        for await _ in stream { received += 1 }
        #expect(received == 1)

        // The recording itself is untouched: six buffers, not one.
        let file = try AVAudioFile(forReading: url)
        #expect(abs(file.length - 14_400) <= 32)
        #expect(writer.writeFailure == nil)
    }

    @Test func levelTracksHowLoudTheAudioIs() throws {
        let (writer, _, url) = try makeWriter()
        defer { try? FileManager.default.removeItem(at: url) }

        writer.append(tone(amplitude: 0.5))
        let loud = writer.level
        // The resampler holds part of each buffer back, so the first quiet buffer out still
        // carries the tail of the loud one. A few more push it through.
        for _ in 0..<3 { writer.append(tone(amplitude: 0.0005)) }
        let quiet = writer.level
        writer.finish()

        #expect(loud > 0)
        #expect(quiet == 0)
    }

    @Test func silenceReadsAsTheFloorRatherThanNegativeInfinity() {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false)!
        let silent = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512)!
        silent.frameLength = 512
        #expect(RecordingWriter.averagePower(of: silent) == -160)
        #expect(AudioRecorder.normalizedLevel(decibels: -160) == 0)
    }

    // A tap hands back a buffer it reuses, so anything held past the callback needs a copy.
    @Test func copyingABufferKeepsItsSamples() throws {
        let original = tone(sampleRate: 24_000, frames: 256)
        let copy = try #require(original.copy())

        #expect(copy !== original)
        #expect(copy.frameLength == original.frameLength)
        for frame in 0..<Int(copy.frameLength) {
            #expect(copy.floatChannelData![0][frame] == original.floatChannelData![0][frame])
        }
    }
}

@MainActor
struct LiveSessionTextTests {
    // Volatile text is a guess that gets rewritten; finalized text only grows. Appending one to
    // the other in the wrong order duplicates whole phrases on screen.
    @Test func displayTextJoinsCommittedTextWithTheCurrentGuess() {
        let session = FakeLiveSession()

        session.finalizedText = "I went to the shop"
        session.volatileText = "and bought"
        #expect(session.displayText == "I went to the shop and bought")

        session.volatileText = ""
        #expect(session.displayText == "I went to the shop")

        session.finalizedText = ""
        session.volatileText = "starting"
        #expect(session.displayText == "starting")
    }
}

@MainActor
final class FakeLiveSession: LiveTranscriptionSession {
    var volatileText = ""
    var finalizedText = ""
    var isHealthy = true
    var unhealthyReason: String?
    private(set) var fedBuffers = 0

    func start() async throws {}
    func feed(_ buffer: AVAudioPCMBuffer) { fedBuffers += 1 }

    func markUnhealthy(_ reason: String) {
        guard isHealthy else { return }
        isHealthy = false
        unhealthyReason = reason
    }

    func finish() async -> String? {
        let text = finalizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return isHealthy && !text.isEmpty ? text : nil
    }
}
