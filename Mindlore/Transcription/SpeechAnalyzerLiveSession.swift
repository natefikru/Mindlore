import AVFoundation
import Foundation
import Observation
import Speech

// Tier 1. SpeechAnalyzer fed from the recorder's tap, producing text while the user talks.
@MainActor
@Observable
final class SpeechAnalyzerLiveSession: LiveTranscriptionSession {
    private(set) var volatileText = ""
    private(set) var finalizedText = ""
    private(set) var isHealthy = true

    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private let diagnostics: DiagnosticsLog
    @ObservationIgnored private var analyzer: SpeechAnalyzer?
    @ObservationIgnored private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    @ObservationIgnored private var collector: Task<Void, Never>?
    @ObservationIgnored private var converter: BufferConverter?
    @ObservationIgnored private var analyzerFormat: AVAudioFormat?
    @ObservationIgnored private var fedFrames: AVAudioFramePosition = 0

    init(locale: Locale, diagnostics: DiagnosticsLog = .shared) {
        self.locale = locale
        self.diagnostics = diagnostics
    }

    func start() async throws {
        let module = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        // Live never downloads. Availability already proved the asset is installed; if that
        // changed underneath us, the session fails and the file path takes the recording.
        guard try await AssetInventory.assetInstallationRequest(supporting: [module]) == nil else {
            throw TranscriptionError.assetsUnavailable("notInstalled")
        }

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw TranscriptionError.analysisFailed("noCompatibleFormat")
        }
        analyzerFormat = format

        let results = module.results
        collector = Task { [weak self] in
            do {
                for try await result in results {
                    guard let self else { return }
                    let text = String(result.text.characters)
                    if result.isFinal {
                        self.finalizedText += text
                        self.volatileText = ""
                    } else {
                        self.volatileText = text
                    }
                }
            } catch {
                // Results stopped early, so what we have covers less than the recording.
                self?.markUnhealthy("results.\(String(describing: type(of: error)))")
            }
        }

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        inputBuilder = continuation
        let analyzer = SpeechAnalyzer(modules: [module])
        self.analyzer = analyzer
        try await analyzer.start(inputSequence: stream)
        diagnostics.record("live.started", ["locale": .string(locale.identifier), "sampleRate": .double(format.sampleRate)])
    }

    // Called from the recorder's tap for every buffer that was written to disk.
    func feed(_ buffer: AVAudioPCMBuffer) {
        guard isHealthy, let inputBuilder, let analyzerFormat else { return }
        do {
            let converter = converter ?? BufferConverter(to: analyzerFormat)
            self.converter = converter
            // The tap's format is the hardware's, almost never the analyzer's. Feeding it unconverted
            // transcribes nothing and reports no error, so a conversion failure has to be loud.
            let converted = try converter.convert(buffer)
            fedFrames += AVAudioFramePosition(buffer.frameLength)
            inputBuilder.yield(AnalyzerInput(buffer: converted))
        } catch {
            markUnhealthy("convert")
        }
    }

    func markUnhealthy(_ reason: String) {
        guard isHealthy else { return }
        isHealthy = false
        diagnostics.record("live.dropped", ["reason": .string(reason), "framesFed": .int(Int(fedFrames))])
    }

    func finish() async -> String? {
        if isHealthy, let inputBuilder, let converter {
            do {
                for buffer in try converter.flush() { inputBuilder.yield(AnalyzerInput(buffer: buffer)) }
            } catch {
                markUnhealthy("flush")
            }
        }
        inputBuilder?.finish()
        inputBuilder = nil
        if let analyzer {
            do {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            } catch {
                markUnhealthy("finalize")
                await analyzer.cancelAndFinishNow()
            }
        }
        analyzer = nil
        _ = await collector?.result
        collector = nil
        volatileText = ""

        let text = finalizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let usable = isHealthy && !text.isEmpty
        diagnostics.record("live.finished", [
            "healthy": .bool(isHealthy),
            "characters": .int(text.count),
            "framesFed": .int(Int(fedFrames)),
            "used": .bool(usable),
        ])
        return usable ? text : nil
    }
}

// Converts tap buffers into the format a consumer requires. Holds one AVAudioConverter per input
// format, because building one per buffer is both slow and loses resampler state across buffers.
final class BufferConverter {
    enum ConversionError: Error {
        case couldNotCreateConverter
        case couldNotAllocateBuffer
        case failed(String)
    }

    private let outputFormat: AVAudioFormat
    private var converter: AVAudioConverter?

    init(to outputFormat: AVAudioFormat) {
        self.outputFormat = outputFormat
    }

    func convert(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        if inputFormat == outputFormat { return buffer }

        if converter?.inputFormat != inputFormat {
            guard let made = AVAudioConverter(from: inputFormat, to: outputFormat) else {
                throw ConversionError.couldNotCreateConverter
            }
            made.primeMethod = .none  // sample-accurate start, so no leading silence is invented
            converter = made
        }
        guard let converter else { throw ConversionError.couldNotCreateConverter }

        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw ConversionError.couldNotAllocateBuffer
        }

        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        if status == .error { throw ConversionError.failed(conversionError?.domain ?? "unknown") }
        return output
    }

    // The resampler keeps back part of every buffer it's given, and only lets it go once told the
    // input has ended. Without this, the end of every recording (up to a tenth of a second, often
    // the last word) never comes out. Call once, after the last `convert`.
    func flush() throws -> [AVAudioPCMBuffer] {
        guard let converter else { return [] }
        defer { converter.reset() }
        var drained: [AVAudioPCMBuffer] = []
        while true {
            guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 4_096) else {
                throw ConversionError.couldNotAllocateBuffer
            }
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
                inputStatus.pointee = .endOfStream
                return nil
            }
            if status == .error { throw ConversionError.failed(conversionError?.domain ?? "unknown") }
            if output.frameLength > 0 { drained.append(output) }
            // haveData means the output filled and more may be waiting; anything else means done.
            guard status == .haveData, output.frameLength > 0 else { return drained }
        }
    }
}
