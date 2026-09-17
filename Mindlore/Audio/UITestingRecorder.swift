import AVFoundation
import Foundation
import Observation

// Stands in for the microphone when UI tests launch with -uiTestingFakeRecorder: starting writes a
// second of silence to active/, and stopping moves it to finished/ like the real recorder.
@Observable
final class UITestingRecorder: AudioRecording {
    static let launchArgument = "-uiTestingFakeRecorder"

    static var isEnabled: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains(StoreLocation.uiTestingArgument) && arguments.contains(launchArgument)
    }

    private(set) var state: AudioRecorder.State = .idle
    private(set) var level: Float = 0
    private(set) var elapsed: TimeInterval = 0
    let audioGap: String? = nil
    let isResuming = false
    let resumeFailed = false
    let buffers: AsyncStream<AVAudioPCMBuffer>? = nil

    @ObservationIgnored private let directory: RecordingsDirectory
    @ObservationIgnored private var url: URL?

    init(directory: RecordingsDirectory = .standard) {
        self.directory = directory
    }

    func start() async throws {
        guard state == .idle else { return }
        let url = try directory.newActiveFileURL()
        let file = try AVAudioFile(forWriting: url, settings: AudioRecorder.recordingSettings, commonFormat: .pcmFormatInt16, interleaved: true)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 24_000)!
        buffer.frameLength = 24_000
        try file.write(from: buffer)
        file.close()
        self.url = url
        elapsed = 1
        level = 0.5
        state = .recording
    }

    func stopBuffering() {}

    func pause() {
        guard state == .recording else { return }
        state = .paused
    }

    func resume() async {
        guard state == .paused else { return }
        state = .recording
    }

    func stop() throws -> URL? {
        guard let url else { return nil }
        reset()
        return try directory.moveToFinished(url)
    }

    func discard() {
        guard let url else { return }
        reset()
        try? FileManager.default.removeItem(at: url)
    }

    private func reset() {
        url = nil
        state = .idle
        level = 0
        elapsed = 0
    }
}
