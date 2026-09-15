import AVFoundation
import Foundation
import Observation

@Observable
final class AudioRecorder {
    enum State: Equatable {
        case idle
        case recording
        case paused
        case interrupted
    }

    enum RecorderError: Error {
        case permissionDenied
        case couldNotStart
    }

    // 16-bit PCM in CAF stays readable if the app is killed mid-recording; compressed formats don't.
    static let recordingSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 24_000,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
    ]

    private(set) var state: State = .idle
    private(set) var level: Float = 0
    private(set) var elapsed: TimeInterval = 0

    @ObservationIgnored private let directory: RecordingsDirectory
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var meteringTask: Task<Void, Never>?
    @ObservationIgnored private var interruptionTask: Task<Void, Never>?

    init(directory: RecordingsDirectory = .standard) {
        self.directory = directory
    }

    var permissionDenied: Bool {
        AVAudioApplication.shared.recordPermission == .denied
    }

    func start() async throws {
        guard state == .idle else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            throw RecorderError.permissionDenied
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)

        let url = try directory.newActiveFileURL()
        let recorder = try AVAudioRecorder(url: url, settings: Self.recordingSettings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else {
            try? FileManager.default.removeItem(at: url)
            throw RecorderError.couldNotStart
        }

        self.recorder = recorder
        state = .recording
        startMetering()
        observeInterruptions()
    }

    func pause() {
        guard state == .recording else { return }
        recorder?.pause()
        state = .paused
    }

    func resume() {
        guard state == .paused || state == .interrupted, let recorder else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        if recorder.record() {
            state = .recording
        }
    }

    // Finishes the file and moves it to finished/. Ingest only after this returns.
    func stop() throws -> URL? {
        guard let recorder else { return nil }
        let url = recorder.url
        recorder.stop()
        tearDown()
        return try directory.moveToFinished(url)
    }

    func discard() {
        guard let recorder else { return }
        recorder.stop()
        let url = recorder.url
        tearDown()
        try? FileManager.default.removeItem(at: url)
    }

    static func normalizedLevel(decibels: Float) -> Float {
        let floor: Float = -50
        guard decibels.isFinite, decibels > floor else { return 0 }
        return min(1, (decibels - floor) / -floor)
    }

    private func tearDown() {
        meteringTask?.cancel()
        interruptionTask?.cancel()
        meteringTask = nil
        interruptionTask = nil
        recorder = nil
        state = .idle
        level = 0
        elapsed = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startMetering() {
        meteringTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let recorder = self.recorder else { return }
                recorder.updateMeters()
                self.level = self.state == .recording ? Self.normalizedLevel(decibels: recorder.averagePower(forChannel: 0)) : 0
                self.elapsed = recorder.currentTime
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func observeInterruptions() {
        interruptionTask = Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(named: AVAudioSession.interruptionNotification) {
                let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                guard let self, rawType == AVAudioSession.InterruptionType.began.rawValue else { continue }
                if self.state == .recording {
                    self.state = .interrupted
                }
            }
        }
    }
}
