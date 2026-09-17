import Foundation

// Whether an entry opens for reading or for typing. Past, finished entries are read; anything the
// user is still working on, or that is still waiting on text, opens for typing.
enum EntryReadMode {
    static func opensForReading(_ entry: Entry?, routeWantsTyping: Bool, automationStartedAt: Date?) -> Bool {
        guard let entry, !routeWantsTyping else { return false }
        return !mustType(entry) && !AIPassTrigger.offersDone(entry, automationStartedAt: automationStartedAt)
    }

    // States that need the editor. An entry that reaches one while being read (Edit pages, Replace
    // with page transcription) switches to typing and stays there.
    static func mustType(_ entry: Entry) -> Bool {
        entry.isDraft
            || entry.awaitingText
            || entry.textReviewPending
            || entry.isAwaitingPageConfirmation
            || entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
