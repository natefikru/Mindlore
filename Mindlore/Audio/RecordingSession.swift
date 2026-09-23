import Foundation
import Observation
import SwiftData

// The one recording in progress, owned by RootView so it keeps running while the user moves between
// tabs. The full recorder and the tab bar's accessory are both views of it.
@Observable
final class RecordingSession {
    enum Status: Equatable {
        case idle
        // The recorder is up and waiting for the user to tap its button. Nothing is captured yet.
        case ready
        case starting
        case active
        case permissionDenied
        case startFailed
    }

    static let levelCount = 48

    private(set) var status: Status = .idle
    private(set) var recorder: (any AudioRecording)?
    private(set) var liveSession: (any LiveTranscriptionSession)?
    // The waveform's history, oldest first.
    private(set) var levels = Array(repeating: Float(0), count: levelCount)
    private(set) var isFinishing = false
    // Whether the full recorder is showing. Closing it while recording only minimizes.
    private(set) var isExpanded = false
    // One open loose end the recorder mentions, picked when the recording begins.
    private(set) var prompt: String?

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let ingestor: RecordingIngestor
    @ObservationIgnored private let makeRecorder: () -> any AudioRecording
    @ObservationIgnored private let makeLiveSession: (Locale) -> any LiveTranscriptionSession
    @ObservationIgnored private let availability: LiveTranscriptionAvailability
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private let speechEngine: () -> SpeechEngine
    // Whether opening the recorder starts capturing at once, or waits for a tap on its button.
    @ObservationIgnored private let recordOnOpen: () -> Bool
    @ObservationIgnored private let afterIngest: () async -> Void
    @ObservationIgnored private let onFinished: (Entry) -> Void
    @ObservationIgnored private let takePrompt: () -> String?
    // Asked before the first recording starts, so the microphone and speech prompts arrive
    // together, at the moment the reason is obvious. Speech used to be asked only once the first
    // recording's text was generated, popping up over the Keep card, and live text never asked.
    @ObservationIgnored private let askPermissions: () async -> Void
    @ObservationIgnored private let diagnostics: DiagnosticsLog
    // Bumped whenever a recording ends, so work still awaiting from an earlier one drops its result
    // instead of writing into the next.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private(set) var startTask: Task<Void, Never>?
    @ObservationIgnored private var feedTask: Task<Void, Never>?
    @ObservationIgnored private var monitorTask: Task<Void, Never>?

    init(
        context: ModelContext,
        ingestor: RecordingIngestor,
        makeRecorder: @escaping () -> any AudioRecording,
        makeLiveSession: @escaping (Locale) -> any LiveTranscriptionSession,
        availability: LiveTranscriptionAvailability = .standard,
        locale: Locale = .current,
        speechEngine: @escaping () -> SpeechEngine,
        recordOnOpen: @escaping () -> Bool = { true },
        afterIngest: @escaping () async -> Void,
        onFinished: @escaping (Entry) -> Void,
        takePrompt: @escaping () -> String? = { nil },
        askPermissions: @escaping () async -> Void = {},
        diagnostics: DiagnosticsLog = .shared
    ) {
        self.context = context
        self.ingestor = ingestor
        self.makeRecorder = makeRecorder
        self.makeLiveSession = makeLiveSession
        self.availability = availability
        self.locale = locale
        self.speechEngine = speechEngine
        self.recordOnOpen = recordOnOpen
        self.afterIngest = afterIngest
        self.onFinished = onFinished
        self.takePrompt = takePrompt
        self.askPermissions = askPermissions
        self.diagnostics = diagnostics
    }

    var isRecording: Bool { status == .active }
    // The tab bar's accessory shows a recording, not a recorder that is only waiting.
    var showsAccessory: Bool { status != .idle && status != .ready }

    // Opens the recorder. With `startsNow` (Siri's Start Recording, or the setting) capture begins
    // at once; otherwise the recorder waits, ready, for a tap on its button.
    func begin(startsNow: Bool? = nil) {
        guard status == .idle, !isFinishing else { return }
        generation += 1
        levels = Array(repeating: 0, count: Self.levelCount)
        isExpanded = true
        prompt = takePrompt()
        if startsNow ?? recordOnOpen() {
            startCapture()
        } else {
            status = .ready
            diagnostics.record("recording.ready")
        }
    }

    // The recorder's own button, on a recorder that opened ready.
    func startRecording() {
        guard status == .ready, !isFinishing else { return }
        startCapture()
    }

    private func startCapture() {
        let recorder = makeRecorder()
        self.recorder = recorder
        status = .starting
        let generation = generation
        startTask = Task { [weak self] in await self?.start(recorder, generation: generation) }
    }

    func minimize() {
        guard isExpanded else { return }
        isExpanded = false
        diagnostics.record("recording.minimized")
    }

    func expand() {
        guard !isExpanded, status != .idle else { return }
        isExpanded = true
        diagnostics.record("recording.expanded")
    }

    // The full recorder's close button: a recording keeps going, anything else ends.
    func close() {
        if status == .active { minimize() } else { discard() }
    }

    func togglePause() {
        guard status == .active, let recorder else { return }
        if recorder.state == .recording {
            recorder.pause()
        } else {
            Task { await recorder.resume() }
        }
    }

    func finish() async {
        guard status == .active, !isFinishing, let recorder else { return }
        isFinishing = true
        generation += 1
        startTask?.cancel()
        monitorTask?.cancel()
        // A failed stop or save leaves the file on disk; it becomes an entry on the next launch.
        let url = try? recorder.stop()
        // stop() ends the buffer stream. Wait for the feed to drain it before finishing the
        // session, or the last seconds of speech never reach the transcriber.
        await feedTask?.value
        let liveText = await liveSession?.finish()
        let entry: Entry? = if let url { await ingestor.ingest(url, context: context, liveText: liveText) } else { nil }
        reset()
        if let entry { onFinished(entry) }
        await afterIngest()
    }

    func discard() {
        guard status != .idle, !isFinishing else { return }
        generation += 1
        startTask?.cancel()
        monitorTask?.cancel()
        feedTask?.cancel()
        // A recorder still waiting on the permission prompt has nothing to discard yet; start()
        // sees the new generation when it returns and discards then.
        recorder?.discard()
        reset()
    }

    // One step of the monitor: the waveform's next sample, and a gap the transcriber never heard.
    func sample() {
        guard let recorder else { return }
        // A paused waveform holds still rather than scrolling silence.
        if recorder.state == .recording {
            levels.removeFirst()
            levels.append(recorder.level)
        }
        // Audio the transcriber never saw means its text covers less than the recording.
        if let gap = recorder.audioGap {
            liveSession?.markUnhealthy(gap)
        }
    }

    private func isCurrent(_ generation: Int) -> Bool {
        generation == self.generation
    }

    private func reset() {
        startTask = nil
        feedTask = nil
        monitorTask = nil
        recorder = nil
        liveSession = nil
        status = .idle
        isExpanded = false
        isFinishing = false
        prompt = nil
    }

    // Picks the loose end to mention and records that it was asked about, so the same one
    // doesn't come back for a few days. Showing it changes nothing else; the next insights run
    // decides whether the recording settled it.
    static func takePrompt(in context: ModelContext, now: Date = .now, diagnostics: DiagnosticsLog = .shared) -> String? {
        guard let looseEnd = LooseEndPrompter.next(in: context, now: now) else { return nil }
        LooseEndPrompter.markPrompted(looseEnd, now: now)
        diagnostics.record("looseEnds.prompted", ["id": .id(looseEnd.id)])
        return looseEnd.text
    }

    private func start(_ recorder: any AudioRecording, generation: Int) async {
        await askPermissions()
        do {
            try await recorder.start()
        } catch AudioRecorder.RecorderError.permissionDenied {
            guard isCurrent(generation) else { return }
            self.recorder = nil
            status = .permissionDenied
            return
        } catch is CancellationError {
            // The permission prompt outlived a discard; nothing was started.
            return
        } catch {
            guard isCurrent(generation) else { return }
            self.recorder = nil
            status = .startFailed
            return
        }
        guard isCurrent(generation) else {
            recorder.discard()
            return
        }
        status = .active
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isCurrent(generation) else { return }
                self.sample()
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        await startLiveTranscription(recorder, generation: generation)
    }

    // Failing to start is not an error the user sees: the recording is already running and the
    // finished file gets text from the batch path instead.
    private func startLiveTranscription(_ recorder: any AudioRecording, generation: Int) async {
        let engine = speechEngine()
        let outcome = await availability.outcome(engine: engine, locale: locale)
        diagnostics.record("live.availability", [
            "engine": .string(engine.rawValue),
            "available": .bool(outcome.isAvailable),
            "reason": .string(outcome.reason?.rawValue ?? "none"),
        ])
        guard isCurrent(generation), let buffers = recorder.buffers else { return }

        if case .unavailable(.assetNotInstalled) = outcome, let resolved = await availability.resolvedLocale(locale) {
            // Downloads for next time. Nothing here waits on it.
            Task.detached { await LiveTranscriptionAvailability.installAssets(for: resolved) }
        }
        let resolved = outcome.isAvailable ? await availability.resolvedLocale(locale) : nil
        guard isCurrent(generation) else { return }
        guard let resolved else {
            recorder.stopBuffering()
            return
        }

        let session = makeLiveSession(resolved)
        do {
            try await session.start()
        } catch {
            if isCurrent(generation) { recorder.stopBuffering() }
            return
        }
        guard isCurrent(generation) else {
            // The recording ended while the transcriber was starting; it has nothing to finish for.
            _ = await session.finish()
            return
        }
        liveSession = session
        if recorder.audioGap != nil { session.markUnhealthy("startedLate") }

        feedTask = Task {
            for await buffer in buffers {
                // Once the transcript can't be trusted it gets thrown away, so stop paying for it.
                guard session.isHealthy else {
                    recorder.stopBuffering()
                    return
                }
                session.feed(buffer)
            }
        }
    }
}
