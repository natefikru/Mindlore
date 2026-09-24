import Foundation
import Observation
import SwiftUI

// Replay's clock: over `duration` seconds, linearly, from the start of the window on screen (or the
// first mention, if the journal is younger than the window) to now. It plays the window the user
// chose, not the whole journal (owner, 2026-09-23).
nonisolated struct MindReplay: Equatable, Sendable {
    static let duration: TimeInterval = 6
    static let stepInterval: Duration = .milliseconds(100)
    // Every step moves the map; every fifth also refreshes names, colours, and labels.
    static let publishEvery = 5

    static func publishes(step index: Int) -> Bool {
        index % publishEvery == 0
    }

    let start: Date
    let end: Date
    let duration: TimeInterval
    let window: MindWindow
    // The window's own start, which the snapshot is trimmed at. Nil for all time.
    let since: Date?

    // Nil when there is nothing to play: no mention in the window before `end`.
    init?(snapshot: MindMapSnapshot, window: MindWindow = .all, end: Date, duration: TimeInterval = MindReplay.duration) {
        let since = window.interval(endingAt: end)?.start
        guard let first = snapshot.earliestLinkDate(after: since, onOrBefore: end), duration > 0 else { return nil }
        // The window's start when the journal reaches back that far, so a quiet first fortnight
        // plays as a quiet fortnight; otherwise the first mention, as all time does.
        let journalStart = snapshot.earliestLinkDate(onOrBefore: end) ?? first
        let start = since.map { max($0, journalStart) } ?? first
        guard start < end else { return nil }
        self.start = start
        self.end = end
        self.duration = duration
        self.window = window
        self.since = since
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
    func start(now: Date, window: MindWindow = .all, fetch: @escaping () -> MindMapSnapshot) -> Bool {
        let snapshot = fetch()
        guard let replay = MindReplay(snapshot: snapshot, window: window, end: now) else {
            stop()
            return false
        }
        self.fetch = fetch
        self.snapshot = snapshot.since(replay.since)
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
        guard isRunning, let fetch, let replay else { return }
        snapshot = fetch().since(replay.since)
    }

    // What the date chip reads: days for a stretch short enough that the month barely moves.
    var window: MindWindow { replay?.window ?? .all }

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
    // Mind's top-bar glass namespace. Both states carry the same `glassEffectID`, so starting a
    // replay grows the round button into the date chip instead of swapping one view for another.
    let glass: Namespace.ID

    // The month on screen. A tick fires when this changes, which is the one thing in a replay the
    // user can both see and feel; a tick per 100 ms step would be sixty buzzes in six seconds.
    private var month: String {
        player.asOf.map { $0.formatted(.dateTime.month(.abbreviated).year()) } ?? ""
    }

    // What the chip says. A month's replay would read "Sep 2026" the whole way through.
    private var label: String {
        guard let asOf = player.asOf else { return "" }
        switch player.window {
        case .month, .quarter: return asOf.formatted(.dateTime.day().month(.abbreviated))
        case .year, .all: return month
        }
    }

    var body: some View {
        Group {
            if player.isRunning {
                Button(action: stop) {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill")
                            .contentTransition(.symbolEffect(.replace))
                        Text(label)
                            .monospacedDigit()
                            .accessibilityIdentifier("mindReplayDate")
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .glassEffectID("replay", in: glass)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop replay")
                .accessibilityIdentifier("mindReplayStop")
            } else {
                Button(action: play) {
                    Image(systemName: "play.fill")
                        .font(.body.weight(.semibold))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 40, height: 40)
                        .glassEffect(.regular.interactive(), in: Circle())
                        .glassEffectID("replay", in: glass)
                }
                .disabled(!available)
                .accessibilityLabel("Replay")
                .accessibilityIdentifier("mindReplay")
            }
        }
        .animation(Motion.carry, value: player.isRunning)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.4), trigger: month) { old, new in
            // Not on the first month, which is the replay starting rather than time passing.
            !old.isEmpty && !new.isEmpty
        }
    }
}
