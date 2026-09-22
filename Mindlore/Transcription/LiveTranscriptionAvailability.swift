import Foundation
import Speech

// Whether a recording can show text as the user talks. The parts that only answer on a real
// device are injected, so the rule itself is testable on the simulator.
nonisolated struct LiveTranscriptionAvailability: Sendable {
    enum Outcome: Equatable, Sendable {
        case available
        // Live can't run now; the recording takes the batch on-device path instead.
        case unavailable(Reason)

        var isAvailable: Bool { self == .available }

        var reason: Reason? {
            if case .unavailable(let reason) = self { reason } else { nil }
        }
    }

    enum Reason: String, Equatable, Sendable {
        case notChosen          // the user picked onDevice or cloud
        case transcriberUnavailable   // SpeechTranscriber missing (simulator, older hardware)
        case localeUnsupported
        case assetNotInstalled  // downloading now, live works from the next recording on
        case notAuthorized      // speech recognition not allowed (yet); the recording still gets text afterwards
    }

    // SpeechTranscriber.isAvailable, injected so tests don't depend on the host.
    let transcriberAvailable: @Sendable () -> Bool
    // The locale SpeechTranscriber will accept for this one, or nil.
    let supportedLocale: @Sendable (Locale) async -> Locale?
    // Whether the model asset is already on disk. A download must never block a recording.
    let assetInstalled: @Sendable (Locale) async -> Bool
    // Whether speech recognition is allowed. Starting the analyzer without it ended the app on the
    // phone (2026-09-22): a first recording began before the prompt had ever been answered, and the
    // process was gone a tenth of a second after live.started, with no crash report.
    var speechAuthorized: @Sendable () -> Bool = { true }

    func outcome(engine: SpeechEngine, locale: Locale) async -> Outcome {
        guard engine.wantsLiveSession else { return .unavailable(.notChosen) }
        guard speechAuthorized() else { return .unavailable(.notAuthorized) }
        guard transcriberAvailable() else { return .unavailable(.transcriberUnavailable) }
        guard let supported = await supportedLocale(locale) else { return .unavailable(.localeUnsupported) }
        guard await assetInstalled(supported) else { return .unavailable(.assetNotInstalled) }
        return .available
    }

    // The locale live would run in, or nil if it can't run at all. Callers need this to build
    // the session, and it costs the same lookups as `outcome`.
    func resolvedLocale(_ locale: Locale) async -> Locale? {
        guard speechAuthorized(), transcriberAvailable() else { return nil }
        return await supportedLocale(locale)
    }

    static let standard = LiveTranscriptionAvailability(
        transcriberAvailable: { SpeechTranscriber.isAvailable },
        supportedLocale: { await SpeechTranscriber.supportedLocale(equivalentTo: $0) },
        assetInstalled: { locale in
            let module = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
            do {
                // A nil request means every asset this module needs is already installed.
                return try await AssetInventory.assetInstallationRequest(supporting: [module]) == nil
            } catch {
                // Can't tell, so assume not. The recording still gets text from the batch path.
                return false
            }
        },
        speechAuthorized: { SFSpeechRecognizer.authorizationStatus() == .authorized }
    )

    // Kicked off when the asset is missing, so the next recording can run live. Never awaited by
    // anything the user is waiting on.
    static func installAssets(for locale: Locale, diagnostics: DiagnosticsLog = .shared) async {
        let module = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        do {
            guard let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) else { return }
            diagnostics.record("live.assets", ["status": "downloading"])
            try await request.downloadAndInstall()
            diagnostics.record("live.assets", ["status": "installed"])
        } catch {
            diagnostics.record("live.assets", ["status": "failed", "error": .errorCode(error)])
        }
    }
}
