import Foundation
import Observation
import SwiftUI

// Replay's clock: from the first mention to now over `duration` seconds, linearly.
nonisolated struct MindReplay: Equatable, Sendable {
    static let duration: TimeInterval = 10
    static let stepInterval: Duration = .milliseconds(100)

    let start: Date
    let end: Date
    let duration: TimeInterval

    // Nil when there is nothing to play: no mention yet, or none before `end`.
    init?(snapshot: MindMapSnapshot, end: Date, duration: TimeInterval = MindReplay.duration) {
        guard let start = snapshot.earliestLinkDate(onOrBefore: end), start < end, duration > 0 else { return nil }
        self.start = start
        self.end = end
        self.duration = duration
    }

    func asOf(elapsed: TimeInterval) -> Date {
        let fraction = min(1, max(0, elapsed / duration))
        return start.addingTimeInterval(end.timeIntervalSince(start) * fraction)
    }

    func isFinished(elapsed: TimeInterval) -> Bool {
        elapsed >= duration
    }
}

// Holds a replay's one snapshot. `start` reads the store once; every step reuses what it read,
// so a step can't fetch. A graph change mid-run (a merge, say) reads again through `refetch`
// and keeps the clock.
@MainActor
@Observable
final class MindReplayPlayer {
    struct Step {
        let snapshot: MindMapSnapshot
        let asOf: Date
        let finished: Bool
    }

    private(set) var isRunning = false
    // The date the map shows, for the replay controls.
    private(set) var asOf: Date?
    @ObservationIgnored private var snapshot: MindMapSnapshot?
    @ObservationIgnored private var replay: MindReplay?
    @ObservationIgnored private var fetch: (() -> MindMapSnapshot)?
    // What `mind.replayed` reports: each step's own work, and when the run began.
    @ObservationIgnored private(set) var stepSeconds: [Double] = []
    @ObservationIgnored private(set) var startedAt: ContinuousClock.Instant?

    // Whether there was anything to play.
    @discardableResult
    func start(now: Date, fetch: @escaping () -> MindMapSnapshot) -> Bool {
        let snapshot = fetch()
        guard let replay = MindReplay(snapshot: snapshot, end: now) else {
            stop()
            return false
        }
        self.fetch = fetch
        self.snapshot = snapshot
        self.replay = replay
        asOf = replay.start
        stepSeconds = []
        startedAt = ContinuousClock.now
        isRunning = true
        return true
    }

    func step(elapsed: TimeInterval) -> Step? {
        guard isRunning, let snapshot, let replay else { return nil }
        let date = replay.asOf(elapsed: elapsed)
        if date != asOf { asOf = date }
        return Step(snapshot: snapshot, asOf: date, finished: replay.isFinished(elapsed: elapsed))
    }

    func noteStep(seconds: Double) {
        stepSeconds.append(seconds)
    }

    func refetch() {
        guard isRunning, let fetch else { return }
        snapshot = fetch()
    }

    func stop() {
        isRunning = false
        asOf = nil
        snapshot = nil
        replay = nil
        fetch = nil
    }
}

// Play, or the replay's date and stop while it runs. Its own view, so a step's date change
// re-renders only this.
struct MindReplayControls: View {
    let player: MindReplayPlayer
    let available: Bool
    let play: () -> Void
    let stop: () -> Void

    var body: some View {
        if player.isRunning {
            Button(action: stop) {
                HStack(spacing: 6) {
                    Image(systemName: "stop.fill")
                    Text(player.asOf.map { $0.formatted(.dateTime.month(.abbreviated).year()) } ?? "")
                        .monospacedDigit()
                        .accessibilityIdentifier("mindReplayDate")
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(.regularMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop replay")
            .accessibilityIdentifier("mindReplayStop")
        } else {
            Button(action: play) {
                Image(systemName: "play.fill")
                    .font(.body.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .background(.regularMaterial, in: Circle())
            }
            .disabled(!available)
            .accessibilityLabel("Replay")
            .accessibilityIdentifier("mindReplay")
        }
    }
}
