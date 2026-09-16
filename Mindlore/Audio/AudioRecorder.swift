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
    // Set if audio was lost: a failed write, or an interruption that broke the capture. The
    // recording is still kept; what it means is that no live transcript covers all of it.
    private(set) var audioGap: String?
    // True while a resume is waiting for the system to hand the microphone back.
    private(set) var isResuming = false
    // The last resume gave up without getting the microphone back. Cleared by the next success.
    private(set) var resumeFailed = false

    // iOS reports an interruption over a few seconds before it lets the app take the microphone
    // again. On an iPhone 17 Pro, activation after Siri succeeded 5.2 s after the end notice, twice,
    // and failed before that. A tap right at the notice needs the full 5.2 s, so the window leaves
    // room over it rather than asking the user to tap again.
    static let resumeRetryWindow: Duration = .seconds(8)
    static let resumeRetryInterval: Duration = .milliseconds(250)

    // Every buffer written to disk, in order, for a live transcriber. Available once start()
    // returns. A caller that isn't going to transcribe must say so with stopBuffering().
    private(set) var buffers: AsyncStream<AVAudioPCMBuffer>?

    @ObservationIgnored private let directory: RecordingsDirectory
    @ObservationIgnored private let diagnostics: DiagnosticsLog
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var writer: RecordingWriter?
    @ObservationIgnored private var meteringTask: Task<Void, Never>?
    @ObservationIgnored private var interruptionTask: Task<Void, Never>?
    @ObservationIgnored private var configurationTask: Task<Void, Never>?

    init(directory: RecordingsDirectory = .standard, diagnostics: DiagnosticsLog = .shared) {
        self.directory = directory
        self.diagnostics = diagnostics
    }

    var permissionDenied: Bool {
        AVAudioApplication.shared.recordPermission == .denied
    }

    func start() async throws {
        guard state == .idle else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            diagnostics.record("recorder.permissionDenied")
            throw RecorderError.permissionDenied
        }
        // The permission prompt can outlive the screen that asked; don't start recording for a view that's gone.
        try Task.checkCancellation()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)

        let url = try directory.newActiveFileURL()
        let engine = AVAudioEngine()

        let (stream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream(bufferingPolicy: .unbounded)
        let writer: RecordingWriter
        do {
            writer = try RecordingWriter(url: url, continuation: continuation)
        } catch {
            continuation.finish()
            try? FileManager.default.removeItem(at: url)
            diagnostics.record("recorder.startFailed", ["reason": "fileNotWritable", "error": .errorCode(error)])
            throw RecorderError.couldNotStart
        }

        let tapFormat: AVAudioFormat
        do {
            tapFormat = try Self.installTap(on: engine, writer: writer)
            engine.prepare()
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            writer.finish()
            try? FileManager.default.removeItem(at: url)
            diagnostics.record("recorder.startFailed", ["reason": "engine", "error": .errorCode(error)])
            throw RecorderError.couldNotStart
        }

        self.engine = engine
        self.writer = writer
        buffers = stream
        audioGap = nil
        resumeFailed = false
        state = .recording
        diagnostics.record("recorder.started", [
            "file": .string(url.lastPathComponent),
            "route": .string(session.currentRoute.inputs.first?.portType.rawValue ?? "none"),
            "tapSampleRate": .double(tapFormat.sampleRate),
        ])
        startMetering()
        observeInterruptions()
        observeConfigurationChanges(of: engine)
    }

    // Called when nothing is going to read `buffers`, so they aren't queued for the whole recording.
    func stopBuffering() {
        writer?.stopStreaming()
    }

    func pause() {
        guard state == .recording else { return }
        writer?.setPaused(true)
        state = .paused
        diagnostics.record("recorder.paused", ["seconds": .double(elapsed)])
    }

    func resume() async {
        guard !isResuming, state == .paused || state == .interrupted, let engine, let writer else { return }
        let wasInterrupted = state == .interrupted
        // After an interruption the system stopped the engine, and the input may now have a different
        // format (Siri and calls can change it), so the tap is rebuilt rather than restarted as it was.
        if wasInterrupted || !engine.isRunning {
            isResuming = true
            defer { isResuming = false }
            let startedState = state
            let deadline = ContinuousClock.now + Self.resumeRetryWindow
            var attempts = 0
            var failure: RestartFailure?
            repeat {
                attempts += 1
                failure = restartEngine()
                guard failure != nil else { break }
                try? await Task.sleep(for: Self.resumeRetryInterval)
                // Done or Cancel during the wait ends the recording; there is nothing left to resume.
                guard self.engine === engine, state == startedState else { return }
            } while ContinuousClock.now < deadline
            if let failure {
                resumeFailed = true
                diagnostics.record("recorder.resumeFailed", failure.fields(attempts: attempts))
                return
            }
            diagnostics.record("recorder.engineRestarted", ["attempts": .int(attempts)])
        }
        resumeFailed = false
        writer.setPaused(false)
        state = .recording
        diagnostics.record("recorder.resumed", ["from": .string(wasInterrupted ? "interrupted" : "paused")])
    }

    // Finishes the file and moves it to finished/. Ingest only after this returns.
    func stop() throws -> URL? {
        guard let writer else { return nil }
        let url = writer.url
        // tearDown flushes the resampler into the file, so the length is read after it.
        tearDown()
        let seconds = writer.seconds
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
        diagnostics.record("recorder.stopped", ["file": .string(url.lastPathComponent), "seconds": .double(seconds), "bytes": .int(size)])
        return try directory.moveToFinished(url)
    }

    func discard() {
        guard let writer else { return }
        let url = writer.url
        tearDown()
        try? FileManager.default.removeItem(at: url)
        diagnostics.record("recorder.discarded", ["file": .string(url.lastPathComponent)])
    }

    static func normalizedLevel(decibels: Float) -> Float {
        let floor: Float = -50
        guard decibels.isFinite, decibels > floor else { return 0 }
        return min(1, (decibels - floor) / -floor)
    }

    private func tearDown() {
        meteringTask?.cancel()
        interruptionTask?.cancel()
        configurationTask?.cancel()
        meteringTask = nil
        interruptionTask = nil
        configurationTask = nil
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        // Closes the file by releasing the writer's AVAudioFile, after the tap can no longer fire.
        writer?.finish()
        writer = nil
        buffers = nil
        resumeFailed = false
        state = .idle
        level = 0
        elapsed = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startMetering() {
        meteringTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let writer = self.writer else { return }
                self.level = self.state == .recording ? writer.level : 0
                self.elapsed = writer.seconds
                if let failure = writer.writeFailure {
                    self.markGap(failure)
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func observeInterruptions() {
        interruptionTask = Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(named: AVAudioSession.interruptionNotification) {
                guard let self else { return }
                let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                switch rawType.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) {
                case .began where self.state == .recording:
                    self.state = .interrupted
                    // The engine is stopped by the system; whatever was being said during the call is gone.
                    self.writer?.setPaused(true)
                    self.markGap("interrupted")
                    self.diagnostics.record("recorder.interrupted", ["seconds": .double(self.elapsed)])
                case .ended:
                    // Recording still waits for the user's tap; this only shows when the microphone came back.
                    let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                    self.diagnostics.record("recorder.interruptionEnded", [
                        "shouldResume": .bool(AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume)),
                        "state": .string(String(describing: self.state)),
                    ])
                default:
                    continue
                }
            }
        }
    }

    // AVAudioEngine stops itself when the audio route changes (headphones, AirPods, a car), where
    // AVAudioRecorder carried on. Without this the timer would freeze and nothing would be captured
    // while the screen still said Recording.
    private func observeConfigurationChanges(of engine: AVAudioEngine) {
        configurationTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .AVAudioEngineConfigurationChange, object: engine) {
                guard let self else { return }
                let route = AVAudioSession.sharedInstance().currentRoute.inputs.first?.portType.rawValue ?? "none"
                self.diagnostics.record("recorder.routeChanged", ["route": .string(route), "state": .string(String(describing: self.state))])
                // Paused and interrupted recordings rebuild the tap when the user resumes.
                guard self.state == .recording else { continue }
                // Audio was lost while the engine was stopped, however briefly.
                self.markGap("routeChanged")
                if let failure = self.restartEngine() {
                    self.diagnostics.record("recorder.routeRestartFailed", failure.fields(attempts: 1))
                    // Hand it to the user, who sees the same prompt as after a call.
                    self.writer?.setPaused(true)
                    self.state = .interrupted
                } else {
                    self.diagnostics.record("recorder.engineRestarted", ["attempts": 1])
                }
            }
        }
    }

    private struct RestartFailure {
        let stage: String
        let error: any Error

        func fields(attempts: Int) -> [String: DiagnosticValue] {
            ["stage": .string(stage), "error": .errorCode(error), "attempts": .int(attempts)]
        }
    }

    // Reactivates the session and rebuilds the tap for whatever the input's format is now.
    // Returns nil on success. Callers log, so a retry loop reports once rather than per attempt.
    private func restartEngine() -> RestartFailure? {
        guard let engine, let writer else { return RestartFailure(stage: "gone", error: RecorderError.couldNotStart) }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            return RestartFailure(stage: "session", error: error)
        }
        do {
            engine.stop()
            _ = try Self.installTap(on: engine, writer: writer)
            engine.prepare()
            try engine.start()
            return nil
        } catch {
            return RestartFailure(stage: "engine", error: error)
        }
    }

    // The writer converts whatever format arrives, so the tap always takes the input's current one.
    private static func installTap(on engine: AVAudioEngine, writer: RecordingWriter) throws -> AVAudioFormat {
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let format = input.outputFormat(forBus: 0)
        // A zero sample rate means the input isn't really available yet; a tap on it captures silence.
        guard format.sampleRate > 0, format.channelCount > 0 else { throw RecorderError.couldNotStart }
        input.installTap(onBus: 0, bufferSize: 4_096, format: format) { buffer, _ in
            writer.append(buffer)
        }
        return format
    }

    private func markGap(_ reason: String) {
        guard audioGap == nil else { return }
        audioGap = reason
        diagnostics.record("recorder.audioGap", ["reason": .string(reason)])
    }
}
