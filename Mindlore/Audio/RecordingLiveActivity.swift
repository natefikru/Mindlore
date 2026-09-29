import ActivityKit
import Foundation

// Keeps the Lock Screen and Dynamic Island in step with the recording: an activity exists exactly
// while a recording is capturing (running or paused), and ends the moment it stops, is discarded, or
// fails, with no lingering card, since there is nothing left to show (HIG, Live Activities). It is
// told the recorder's state only when that changes; a running clock counts on its own.
@MainActor
final class RecordingLiveActivity {
    private var activity: Activity<RecordingActivityAttributes>?
    private let diagnostics: DiagnosticsLog

    init(diagnostics: DiagnosticsLog = .shared) {
        self.diagnostics = diagnostics
    }

    // What the activity shows for a recorder in `state` with `elapsed` banked, or nil for no
    // activity at all.
    nonisolated static func content(isRecording: Bool, recorderState: AudioRecorder.State?, elapsed: TimeInterval, now: Date) -> RecordingActivityAttributes.ContentState? {
        guard isRecording else { return nil }
        let running = recorderState == .recording
        return .init(elapsed: elapsed, runningSince: running ? now : nil)
    }

    func update(_ content: RecordingActivityAttributes.ContentState?) {
        guard let content else {
            end()
            return
        }
        if let activity {
            Task { await activity.update(ActivityContent(state: content, staleDate: nil)) }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            activity = try Activity.request(attributes: RecordingActivityAttributes(), content: ActivityContent(state: content, staleDate: nil))
            diagnostics.record("liveActivity.started")
        } catch {
            diagnostics.record("liveActivity.failed", ["error": .error(error)])
        }
    }

    private func end() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
        diagnostics.record("liveActivity.ended")
    }

    // A recording the app was killed during is recovered into an entry at launch; its activity
    // would otherwise sit on the Lock Screen for hours showing a clock for nothing.
    static func endOrphans() {
        for activity in Activity<RecordingActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
