import AVFoundation
import Foundation

// Writes captured audio to disk and passes the same buffers on to whoever wants to transcribe them.
//
// The order inside `append` is the whole point: the file write happens first and never depends on
// the stream, so a transcription failure cannot cost the user a recording. Everything here runs on
// the audio tap's thread, which is serial; `level` and `frames` are read from the main actor, so
// they go through the lock.
final class RecordingWriter: @unchecked Sendable {
    // The recorder's own format: 24 kHz mono, matching what lands in the file.
    static let processingFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false)!

    let url: URL

    private let file: AVAudioFile
    private let converter = BufferConverter(to: RecordingWriter.processingFormat)
    private let continuation: AsyncStream<AVAudioPCMBuffer>.Continuation
    private let lock = NSLock()
    private var frames: AVAudioFramePosition = 0
    private var decibels: Float = -160
    private var failure: String?
    private var paused = false
    private var streaming = true

    init(url: URL, continuation: AsyncStream<AVAudioPCMBuffer>.Continuation) throws {
        self.url = url
        self.continuation = continuation
        self.file = try AVAudioFile(
            forWriting: url,
            settings: AudioRecorder.recordingSettings,
            commonFormat: Self.processingFormat.commonFormat,
            interleaved: Self.processingFormat.isInterleaved
        )
    }

    var seconds: TimeInterval {
        lock.withLock { Double(frames) / Self.processingFormat.sampleRate }
    }

    var level: Float {
        lock.withLock { AudioRecorder.normalizedLevel(decibels: decibels) }
    }

    // Set if a write ever failed. The recording is still worth keeping, but its text isn't
    // trustworthy, so the caller stops believing any live transcript.
    var writeFailure: String? {
        lock.withLock { failure }
    }

    func setPaused(_ paused: Bool) {
        lock.withLock { self.paused = paused }
    }

    // Stops handing buffers on for transcription. Without this, a recording nobody is transcribing
    // would queue every buffer for its whole length: about 6 MB a minute with no reader.
    func stopStreaming() {
        guard lock.withLock({ let was = streaming; streaming = false; return was }) else { return }
        continuation.finish()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard !lock.withLock({ paused }) else { return }

        let converted: AVAudioPCMBuffer
        do {
            let result = try converter.convert(buffer)
            // A matching format returns the tap's own buffer, which is only valid for this call.
            converted = result === buffer ? (result.copy() ?? result) : result
        } catch {
            lock.withLock { failure = failure ?? "convert" }
            return
        }

        write(converted)
    }

    // Closes the file. Nothing may be appended afterwards.
    func finish() {
        do {
            for buffer in try converter.flush() { write(buffer) }
        } catch {
            lock.withLock { failure = failure ?? "flush" }
        }
        stopStreaming()
        file.close()
    }

    private func write(_ converted: AVAudioPCMBuffer) {
        do {
            try file.write(from: converted)
        } catch {
            lock.withLock { failure = failure ?? "write" }
            return
        }

        let power = Self.averagePower(of: converted)
        lock.withLock {
            frames += AVAudioFramePosition(converted.frameLength)
            decibels = power
        }
        if lock.withLock({ streaming }) { continuation.yield(converted) }
    }

    static func averagePower(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return -160 }
        var sum: Float = 0
        for frame in 0..<Int(buffer.frameLength) {
            let sample = channel[frame]
            sum += sample * sample
        }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        guard rms > 0 else { return -160 }
        return 20 * log10(rms)
    }
}

extension AVAudioPCMBuffer {
    // A tap hands back a buffer it reuses, so anything kept past the callback needs its own copy.
    func copy() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength),
              let source = floatChannelData, let destination = copy.floatChannelData else { return nil }
        copy.frameLength = frameLength
        for channel in 0..<Int(format.channelCount) {
            destination[channel].update(from: source[channel], count: Int(frameLength))
        }
        return copy
    }
}
