import AVFoundation
import Foundation
import SwiftData
import Testing
@testable import Mindlore

@MainActor
@Observable
final class FakeRecorder: AudioRecording {
    enum StartBehavior {
        case succeed
        case deny
        case fail
        case block
    }

    private(set) var state: AudioRecorder.State = .idle
    var level: Float = 0
    var elapsed: TimeInterval = 0
    var audioGap: String?
    var isResuming = false
    var resumeFailed = false
    private(set) var buffers: AsyncStream<AVAudioPCMBuffer>?

    @ObservationIgnored var startBehavior: StartBehavior = .succeed
    @ObservationIgnored private(set) var stopCount = 0
    @ObservationIgnored private(set) var discardCount = 0
    @ObservationIgnored private(set) var discardedARunningRecording = false
    @ObservationIgnored private var blocked: CheckedContinuation<Void, Never>?
    @ObservationIgnored private var blockWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    @ObservationIgnored private let directory: RecordingsDirectory
    @ObservationIgnored private let id = UUID()

    init(directory: RecordingsDirectory) {
        self.directory = directory
    }

    var fileID: UUID { id }

    func start() async throws {
        switch startBehavior {
        case .deny: throw AudioRecorder.RecorderError.permissionDenied
        case .fail: throw AudioRecorder.RecorderError.couldNotStart
        case .block:
            await withCheckedContinuation { continuation in
                blocked = continuation
                blockWaiters.forEach { $0.resume() }
                blockWaiters = []
            }
        case .succeed: break
        }
        let (stream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream()
        buffers = stream
        self.continuation = continuation
        state = .recording
    }

    // Returns once start() is parked, so unblock() has something to resume.
    func waitUntilBlocked() async {
        guard blocked == nil else { return }
        await withCheckedContinuation { blockWaiters.append($0) }
    }

    func unblock() {
        blocked?.resume()
        blocked = nil
    }

    func stopBuffering() {
        continuation?.finish()
    }

    func pause() { state = .paused }
    func resume() async { state = .recording }

    func stop() throws -> URL? {
        guard state != .idle else { return nil }
        stopCount += 1
        state = .idle
        continuation?.finish()
        let url = directory.finished.appendingPathComponent(id.uuidString).appendingPathExtension("caf")
        _ = try AudioFixtures.writePCM(to: url, seconds: 0.3)
        return url
    }

    func discard() {
        discardCount += 1
        if state != .idle { discardedARunningRecording = true }
        state = .idle
        continuation?.finish()
    }
}

@MainActor
final class RecordingSessionHarness {
    let ingest: IngestHarness
    var recorders: [FakeRecorder] = []
    var liveSessions: [FakeLiveSession] = []
    var finished: [Entry] = []
    var afterIngestCount = 0
    var startBehavior: FakeRecorder.StartBehavior = .succeed
    var liveText = ""
    var makeLive: (() -> any LiveTranscriptionSession)?
    private(set) var session: RecordingSession!

    init(engine: SpeechEngine = .onDeviceLive, diagnostics: DiagnosticsLog = .disabled) throws {
        ingest = try IngestHarness()
        let availability = LiveTranscriptionAvailability(
            transcriberAvailable: { true },
            supportedLocale: { $0 },
            assetInstalled: { _ in true }
        )
        session = RecordingSession(
            context: ingest.context,
            ingestor: RecordingIngestor(diagnostics: diagnostics),
            makeRecorder: { [unowned self] in
                let recorder = FakeRecorder(directory: self.ingest.directory)
                recorder.startBehavior = self.startBehavior
                self.recorders.append(recorder)
                return recorder
            },
            makeLiveSession: { [unowned self] _ in
                if let makeLive = self.makeLive { return makeLive() }
                let live = FakeLiveSession()
                live.finalizedText = self.liveText
                self.liveSessions.append(live)
                return live
            },
            availability: availability,
            locale: Locale(identifier: "en_US"),
            speechEngine: { engine },
            afterIngest: { [unowned self] in self.afterIngestCount += 1 },
            onFinished: { [unowned self] in self.finished.append($0) },
            diagnostics: diagnostics
        )
    }

    func beginAndWait() async {
        session.begin()
        await session.startTask?.value
    }
}

@MainActor
struct RecordingSessionTests {
    @Test func beginStartsTheRecorderAndExpands() async throws {
        let harness = try RecordingSessionHarness()
        await harness.beginAndWait()

        #expect(harness.session.status == .active)
        #expect(harness.session.isExpanded)
        #expect(harness.recorders.count == 1)
        #expect(harness.recorders[0].state == .recording)
        #expect(harness.session.liveSession != nil)

        harness.session.begin()
        #expect(harness.recorders.count == 1)
    }

    @Test func minimizingKeepsRecording() async throws {
        let file = DiagnosticsFile()
        let harness = try RecordingSessionHarness(diagnostics: DiagnosticsLog(fileURL: file.url))
        await harness.beginAndWait()

        harness.session.close()
        #expect(!harness.session.isExpanded)
        #expect(harness.session.status == .active)
        #expect(harness.recorders[0].state == .recording)
        #expect(harness.recorders[0].stopCount == 0)
        #expect(harness.recorders[0].discardCount == 0)
        #expect(file.contents().contains("recording.minimized"))

        harness.session.expand()
        #expect(harness.session.isExpanded)
        #expect(file.contents().contains("recording.expanded"))
    }

    @Test func discardingWhileMinimizedLeavesNothing() async throws {
        let harness = try RecordingSessionHarness()
        await harness.beginAndWait()
        harness.session.minimize()

        harness.session.discard()
        #expect(harness.recorders[0].discardedARunningRecording)
        #expect(harness.session.status == .idle)
        #expect(harness.session.recorder == nil)
        #expect(harness.session.liveSession == nil)
        #expect(harness.finished.isEmpty)
        #expect(try harness.ingest.entries().isEmpty)

        // A new recording can start straight away.
        await harness.beginAndWait()
        #expect(harness.session.status == .active)
    }

    @Test func discardingDuringStartStopsTheRecorderOnceItStarts() async throws {
        let harness = try RecordingSessionHarness()
        harness.startBehavior = .block
        harness.session.begin()
        #expect(harness.session.status == .starting)
        let start = try #require(harness.session.startTask)
        await harness.recorders[0].waitUntilBlocked()

        harness.session.close()
        #expect(harness.session.status == .idle)
        #expect(!harness.session.isExpanded)

        harness.recorders[0].unblock()
        await start.value
        #expect(harness.recorders[0].discardedARunningRecording)
        #expect(harness.liveSessions.isEmpty)
        #expect(harness.session.status == .idle)
    }

    @Test func finishIngestsOnceAndRoutesToTheEntry() async throws {
        let harness = try RecordingSessionHarness()
        harness.liveText = "Walked to the river."
        await harness.beginAndWait()
        harness.session.minimize()

        async let first: Void = harness.session.finish()
        async let second: Void = harness.session.finish()
        _ = await (first, second)

        let entries = try harness.ingest.entries()
        #expect(entries.count == 1)
        #expect(harness.recorders[0].stopCount == 1)
        #expect(harness.finished.count == 1)
        #expect(harness.finished.first?.id == harness.recorders[0].fileID)
        #expect(harness.finished.first?.text == "Walked to the river.")
        #expect(harness.afterIngestCount == 1)
        #expect(harness.session.status == .idle)
        #expect(!harness.session.isFinishing)
        #expect(harness.session.recorder == nil)
    }

    @Test func finishDoesNothingBeforeRecordingStarts() async throws {
        let harness = try RecordingSessionHarness()
        harness.startBehavior = .block
        harness.session.begin()
        let start = try #require(harness.session.startTask)
        await harness.recorders[0].waitUntilBlocked()

        await harness.session.finish()
        #expect(harness.session.status == .starting)
        #expect(harness.finished.isEmpty)

        harness.session.discard()
        harness.recorders[0].unblock()
        await start.value
        #expect(harness.recorders[0].discardedARunningRecording)
    }

    @Test func discardIsIgnoredWhileFinishing() async throws {
        let harness = try RecordingSessionHarness()
        let live = ParkingLiveSession()
        harness.makeLive = { live }
        await harness.beginAndWait()

        let finishing = Task { await harness.session.finish() }
        await live.waitUntilFinishing()
        #expect(harness.session.isFinishing)
        harness.session.discard()
        live.release()
        await finishing.value

        #expect(harness.recorders[0].discardCount == 0)
        #expect(try harness.ingest.entries().count == 1)
    }

    @Test func deniedPermissionShowsAndCloses() async throws {
        let harness = try RecordingSessionHarness()
        harness.startBehavior = .deny
        await harness.beginAndWait()
        #expect(harness.session.status == .permissionDenied)
        #expect(harness.session.isExpanded)

        harness.session.close()
        #expect(harness.session.status == .idle)
        #expect(!harness.session.isExpanded)
    }

    @Test func aFailedStartShowsAndCloses() async throws {
        let harness = try RecordingSessionHarness()
        harness.startBehavior = .fail
        await harness.beginAndWait()
        #expect(harness.session.status == .startFailed)

        harness.session.close()
        #expect(harness.session.status == .idle)
    }

    @Test func batchEngineStartsNoLiveSession() async throws {
        let harness = try RecordingSessionHarness(engine: .onDevice)
        await harness.beginAndWait()
        #expect(harness.session.status == .active)
        #expect(harness.liveSessions.isEmpty)
    }

    @Test func samplingKeepsAWindowAndMarksAGap() async throws {
        let harness = try RecordingSessionHarness()
        await harness.beginAndWait()
        let recorder = harness.recorders[0]

        recorder.level = 0.7
        harness.session.sample()
        #expect(harness.session.levels.count == RecordingSession.levelCount)
        #expect(harness.session.levels.last == 0.7)
        #expect(harness.liveSessions[0].isHealthy)

        recorder.audioGap = "interrupted"
        harness.session.sample()
        #expect(!harness.liveSessions[0].isHealthy)
        #expect(harness.liveSessions[0].unhealthyReason == "interrupted")
    }

    @Test func liveTextNeverReachesTheLog() async throws {
        let file = DiagnosticsFile()
        let harness = try RecordingSessionHarness(diagnostics: DiagnosticsLog(fileURL: file.url))
        harness.liveText = "Spoken \(DiagnosticsPrivacyTests.sentinel)"
        await harness.beginAndWait()
        harness.session.minimize()
        harness.session.expand()
        await harness.session.finish()

        #expect(harness.finished.first?.text.contains(DiagnosticsPrivacyTests.sentinel) == true)
        let contents = file.contents()
        #expect(contents.contains("recording.minimized"))
        #expect(contents.contains("live.availability"))
        #expect(!contents.contains(DiagnosticsPrivacyTests.sentinel))
    }
}

// A live session whose finish() parks until released, so a test can act while a recording is
// finishing.
@MainActor
final class ParkingLiveSession: LiveTranscriptionSession {
    let volatileText = ""
    let finalizedText = ""
    let isHealthy = true
    private var parked: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func start() async throws {}
    func feed(_ buffer: AVAudioPCMBuffer) {}
    func markUnhealthy(_ reason: String) {}

    func finish() async -> String? {
        await withCheckedContinuation { continuation in
            parked = continuation
            waiters.forEach { $0.resume() }
            waiters = []
        }
        return nil
    }

    func waitUntilFinishing() async {
        guard parked == nil else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        parked?.resume()
        parked = nil
    }
}
