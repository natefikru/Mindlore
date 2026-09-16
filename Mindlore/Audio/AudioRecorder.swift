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

    // Every buffer written to disk, in order, for a live transcriber. Available once start()
    // returns. A caller that isn't going to transcribe must say so with stopBuffering().
    private(set) var buffers: AsyncStream<AVAudioPCMBuffer>?

    @ObservationIgnored private let directory: RecordingsDirectory
    @ObservationIgnored private let diagnostics: DiagnosticsLog
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var writer: RecordingWriter?
    @ObservationIgnored private var meteringTask: Task<Void, Never>?
    @ObservationIgnored private var interruptionTask: Task<Void, Never>?

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
        let input = engine.inputNode
        let tapFormat = input.outputFormat(forBus: 0)
        // A zero sample rate means the input isn't really available yet; a tap on it captures silence.
        guard tapFormat.sampleRate > 0, tapFormat.channelCount > 0 else {
            diagnostics.record("recorder.startFailed", ["reason": "noInputFormat"])
            throw RecorderError.couldNotStart
        }

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

        input.installTap(onBus: 0, bufferSize: 4_096, format: tapFormat) { buffer, _ in
            writer.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            writer.finish()
            try? FileManager.default.removeItem(at: url)
            diagnostics.record("recorder.startFailed", ["reason": "engine", "error": .errorCode(error)])
            throw RecorderError.couldNotStart
        }

        self.engine = engine
        self.writer = writer
        buffers = stream
        audioGap = nil
        state = .recording
        diagnostics.record("recorder.started", [
            "file": .string(url.lastPathComponent),
            "route": .string(session.currentRoute.inputs.first?.portType.rawValue ?? "none"),
            "tapSampleRate": .double(tapFormat.sampleRate),
        ])
        startMetering()
        observeInterruptions()
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

    func resume() {
        guard state == .paused || state == .interrupted, let engine, let writer else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                diagnostics.record("recorder.resumeFailed", ["error": .errorCode(error)])
                return
            }
        }
        let wasInterrupted = state == .interrupted
        writer.setPaused(false)
        state = .recording
        diagnostics.record("recorder.resumed", ["from": .string(wasInterrupted ? "interrupted" : "paused")])
    }

    // Finishes the file and moves it to finished/. Ingest only after this returns.
    func stop() throws -> URL? {
        guard let writer else { return nil }
        let url = writer.url
        let seconds = writer.seconds
        tearDown()
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
        meteringTask = nil
        interruptionTask = nil
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        // Closes the file by releasing the writer's AVAudioFile, after the tap can no longer fire.
        writer?.finish()
        writer = nil
        buffers = nil
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
                if let failure = writer.writeFailure, self.audioGap == nil {
                    self.audioGap = failure
                    self.diagnostics.record("recorder.audioGap", ["reason": .string(failure)])
                }
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
                    // The engine is stopped by the system; whatever was being said during the call is gone.
                    self.writer?.setPaused(true)
                    self.audioGap = self.audioGap ?? "interrupted"
                    self.diagnostics.record("recorder.interrupted", ["seconds": .double(self.elapsed)])
                }
            }
        }
    }
}
