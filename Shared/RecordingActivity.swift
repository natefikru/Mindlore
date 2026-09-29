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

// The Record control's action. Compiled into both targets, as Apple asks of a control that opens
// its app: with `openAppWhenRun` the system launches Mindlore and performs it there, where the hook
// is set before any scene exists (MindloreApp.init), so a cold launch takes the same path as Siri's
// Start Recording. A link opened from the extension instead (mindlore://record) did nothing on the
// phone.
struct RecordFromControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Record in Mindlore"
    static let description = IntentDescription("Opens Mindlore and starts a voice entry.")
    static let openAppWhenRun = true
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        RecordingControl.start?()
        return .result()
    }
}

@MainActor
enum RecordingControl {
    static var stop: (() async -> Void)?
    static var start: (() -> Void)?
}
