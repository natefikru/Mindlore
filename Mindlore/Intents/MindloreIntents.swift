import AppIntents

// What Siri, Shortcuts, Spotlight, and the Action button can ask of the app. In the app target, not
// an extension: every one of them opens the app, which is where the recorder, the editor, and Ask
// already live, and an extension would need an App Group the Personal Team can't sign.
//
// Each intent only leaves a request; RootView carries it out once it exists (IntentRequests).

struct StartRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Recording"
    static let description = IntentDescription("Opens Mindlore and starts a voice entry.")
    static let openAppWhenRun = true

    // Nothing is spoken back. A reply on the way in would be the first thing the microphone heard,
    // and the recorder appearing is the answer. If one is already running it comes back instead.
    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRequests.shared.request(.record)
        return .result()
    }
}

struct NewEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "New Written Entry"
    static let description = IntentDescription("Opens Mindlore on a new entry, ready to type.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRequests.shared.request(.newEntry)
        return .result()
    }
}

struct AskJournalIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Your Journal"
    static let description = IntentDescription("Opens Ask, with a question in the field if you give one. You send it.")
    static let openAppWhenRun = true

    @Parameter(title: "Question")
    var question: String?

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRequests.shared.request(.ask(question))
        return .result()
    }
}

// The phrases Siri knows without any setup, and what the Action button and Spotlight offer.
struct MindloreShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRecordingIntent(),
            phrases: [
                "Record in \(.applicationName)",
                "Start a \(.applicationName) recording",
                "New \(.applicationName) voice entry",
            ],
            shortTitle: "Record",
            systemImageName: "mic"
        )
        AppShortcut(
            intent: NewEntryIntent(),
            phrases: [
                "New \(.applicationName) entry",
                "Write in \(.applicationName)",
            ],
            shortTitle: "New Entry",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: AskJournalIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Ask my \(.applicationName) journal",
            ],
            shortTitle: "Ask",
            systemImageName: "bubble.left.and.text.bubble.right"
        )
    }
}
