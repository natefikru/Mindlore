import ActivityKit
import AppIntents
import Foundation

// What the Lock Screen and the Dynamic Island show while a recording runs. Compiled into the app,
// which starts and ends the activity, and into MindloreWidgets, which draws it. It carries time and
// state only, never a word of the recording: the Lock Screen is readable by anyone holding the
// phone (HIG, Live Activities).
nonisolated struct RecordingActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        // Recording time already banked, frozen while paused.
        var elapsed: TimeInterval
        // When the clock last started running, or nil while paused or interrupted.
        var runningSince: Date?

        var isPaused: Bool { runningSince == nil }
        // Where a running timer counts from, so it shows the banked time plus the time since.
        var timerStart: Date { (runningSince ?? .now).addingTimeInterval(-elapsed) }
    }
}

// The Live Activity's Stop button. A LiveActivityIntent performs in the app's process, which is
// alive for as long as it records, so this only calls what the app registered at launch; in the
// widget extension, where it is only compiled for the button, the hook is never set.
struct StopRecordingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Recording"
    static let description = IntentDescription("Stops the Mindlore recording in progress and saves it.")
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        await RecordingControl.stop?()
        return .result()
    }
}

@MainActor
enum RecordingControl {
    static var stop: (() async -> Void)?
}
