import AVFoundation
import Foundation
import Speech

// On-device transcription. SpeechTranscriber is unavailable on the simulator and older
// devices, so DictationTranscriber is the fallback.
struct SpeechAnalyzerTranscriber: Transcriber {
    nonisolated let diagnostics: DiagnosticsLog

    init(diagnostics: DiagnosticsLog = .shared) {
        self.diagnostics = diagnostics
    }

    @concurrent
    nonisolated func transcribe(audioFileURL: URL, locale: Locale) async throws -> String {
        try await ensureAuthorized()

        let speechTranscriberAvailable = SpeechTranscriber.isAvailable
        if speechTranscriberAvailable, let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            diagnostics.record("transcription.module", ["module": "SpeechTranscriber", "locale": .string(supported.identifier)])
            let module = SpeechTranscriber(locale: supported, preset: .transcription)
            return try await run(module: module, results: module.results, text: \.text, isFinal: \.isFinal, audioFileURL: audioFileURL)
        }
        if let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
            diagnostics.record("transcription.module", [
                "module": "DictationTranscriber",
                "locale": .string(supported.identifier),
                "speechTranscriberAvailable": .bool(speechTranscriberAvailable),
            ])
            let module = DictationTranscriber(locale: supported, preset: .longDictation)
            return try await run(module: module, results: module.results, text: \.text, isFinal: \.isFinal, audioFileURL: audioFileURL)
        }
        diagnostics.record("transcription.module", ["module": "none", "requestedLocale": .string(locale.identifier), "speechTranscriberAvailable": .bool(speechTranscriberAvailable)])
        throw TranscriptionError.unsupportedLocale
    }

    nonisolated private func run<Results: AsyncSequence & Sendable>(
        module: any SpeechModule,
        results: Results,
        text: @escaping @Sendable (Results.Element) -> AttributedString,
        isFinal: @escaping @Sendable (Results.Element) -> Bool,
        audioFileURL: URL
    ) async throws -> String {
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                diagnostics.record("transcription.assets", ["status": "downloading"])
                try await request.downloadAndInstall()
                diagnostics.record("transcription.assets", ["status": "installed"])
            } else {
                diagnostics.record("transcription.assets", ["status": "alreadyInstalled"])
            }
        } catch {
            throw TranscriptionError.assetsUnavailable(String(describing: error))
        }

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: audioFileURL)
        } catch {
            throw TranscriptionError.analysisFailed(String(describing: error))
        }

        let analyzer = SpeechAnalyzer(modules: [module])
        // Start collecting before analysis begins so no early results are missed.
        let collector = Task {
            var transcript = AttributedString()
            for try await result in results where isFinal(result) {
                transcript += text(result)
            }
            return String(transcript.characters)
        }
        do {
            try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)
            return try await collector.value.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            collector.cancel()
            await analyzer.cancelAndFinishNow()
            throw TranscriptionError.analysisFailed(String(describing: error))
        }
    }

    nonisolated private func ensureAuthorized() async throws {
        var status = SFSpeechRecognizer.authorizationStatus()
        let initialStatus = status
        defer { diagnostics.record("transcription.authorization", ["initial": .int(initialStatus.rawValue), "final": .int(status.rawValue)]) }
        if status == .notDetermined {
            status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
        }
        guard status == .authorized else { throw TranscriptionError.authorizationDenied }
    }
}
