import AVFoundation
import Speech

// The two prompts a first recording needs, asked together and only while unanswered. Speech is
// skipped when recordings are transcribed in the cloud, which doesn't use Apple's recognizer.
enum RecordingPermissions {
    static func askIfNeeded(speechEngine: SpeechEngine) async {
        if AVAudioApplication.shared.recordPermission == .undetermined {
            // A refusal is handled where it matters: the recorder's own start reports it.
            _ = await AVAudioApplication.requestRecordPermission()
        }
        guard speechEngine != .cloud, SFSpeechRecognizer.authorizationStatus() == .notDetermined else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            SFSpeechRecognizer.requestAuthorization { _ in continuation.resume() }
        }
    }
}
