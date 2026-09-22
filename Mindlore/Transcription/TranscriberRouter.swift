import Foundation

// How one voice entry gets its text.
struct TranscriptionRoute {
    struct Cloud {
        let label: String
        let makeTranscriber: (_ prompt: String?) -> any Transcriber
        let chunkTargetSeconds: Double
        let maxUploadBytes: Int
    }

    let cloud: Cloud?
    let onDevice: any Transcriber
    let onDeviceLabel: String
    // With a cloud route, whether the on-device transcriber runs when the cloud call fails.
    let fallBackToOnDevice: Bool

    static func onDevice(_ transcriber: any Transcriber, label: String = "apple") -> TranscriptionRoute {
        TranscriptionRoute(cloud: nil, onDevice: transcriber, onDeviceLabel: label, fallBackToOnDevice: false)
    }
}

// Picks cloud or on-device transcription from the current settings, per entry.
struct TranscriberRouter {
    let settings: SettingsStore
    let accounts: ProviderAccountStore
    let http: any HTTPClient
    let onDevice: any Transcriber

    func route(for entry: Entry, manualRetry: Bool) -> TranscriptionRoute {
        guard settings.aiEnabled, settings.speechEngine == .cloud, case .success(let provider) = accounts.resolve(.speech) else {
            return .onDevice(onDevice)
        }
        // Recordings from before AI was turned on stay on-device unless the user asks.
        let eligible = manualRetry || settings.aiEnabledAt.map { entry.createdAt >= $0 } ?? false
        guard eligible else { return .onDevice(onDevice) }
        let http = http
        return TranscriptionRoute(
            cloud: .init(
                label: "openai:\(provider.model)",
                makeTranscriber: { prompt in
                    OpenAICompatibleTranscriber(baseURL: provider.account.baseURL, apiKey: provider.apiKey, model: provider.model, http: http, prompt: prompt)
                },
                chunkTargetSeconds: OpenAICompatibleTranscriber.chunkTargetSeconds,
                maxUploadBytes: OpenAICompatibleTranscriber.maxUploadBytes
            ),
            onDevice: onDevice,
            onDeviceLabel: "apple",
            fallBackToOnDevice: settings.fallBackToOnDevice
        )
    }
}
