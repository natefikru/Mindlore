import AVFoundation
import Foundation
import Speech

// On-device transcription. SpeechTranscriber is unavailable on the simulator and older
// devices, so DictationTranscriber is the fallback.
struct SpeechAnalyzerTranscriber: Transcriber {
    @concurrent
    nonisolated func transcribe(audioFileURL: URL, locale: Locale) async throws -> String {
        try await Self.ensureAuthorized()

        if SpeechTranscriber.isAvailable, let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            let module = SpeechTranscriber(locale: supported, preset: .transcription)
            return try await Self.run(module: module, results: module.results, text: \.text, isFinal: \.isFinal, audioFileURL: audioFileURL)
        }
        if let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
            let module = DictationTranscriber(locale: supported, preset: .longDictation)
            return try await Self.run(module: module, results: module.results, text: \.text, isFinal: \.isFinal, audioFileURL: audioFileURL)
        }
        throw TranscriptionError.unsupportedLocale
    }

    nonisolated private static func run<Results: AsyncSequence & Sendable>(
        module: any SpeechModule,
        results: Results,
        text: @escaping @Sendable (Results.Element) -> AttributedString,
        isFinal: @escaping @Sendable (Results.Element) -> Bool,
        audioFileURL: URL
    ) async throws -> String {
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                try await request.downloadAndInstall()
            }
        } catch {
            throw TranscriptionError.assetsUnavailable(String(describing: error))
        }

        do {
            let audioFile = try AVAudioFile(forReading: audioFileURL)
            let analyzer = SpeechAnalyzer(modules: [module])
            // Start collecting before analysis begins so no early results are missed.
            let collector = Task {
                var transcript = AttributedString()
                for try await result in results where isFinal(result) {
                    transcript += text(result)
                }
                return String(transcript.characters)
            }
            try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)
            return try await collector.value.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as TranscriptionError {
            throw error
        } catch {
            throw TranscriptionError.analysisFailed(String(describing: error))
        }
    }

    nonisolated private static func ensureAuthorized() async throws {
        var status = SFSpeechRecognizer.authorizationStatus()
        if status == .notDetermined {
            status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
        }
        guard status == .authorized else { throw TranscriptionError.authorizationDenied }
    }
}
