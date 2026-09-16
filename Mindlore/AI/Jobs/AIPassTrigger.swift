import Foundation
import Observation
import SwiftData

// The single automatic AI pass each entry gets. It fires at the first moment the entry has text
// worth working on, flags the jobs that settings allow, and never fires for that entry again.
@Observable
final class AIPassTrigger {
    enum Moment: String {
        case finished
        case editorClosed
        case textReady
        case approved
        case launchSweep
    }

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let presence: EditorPresence
    @ObservationIgnored private let titleUsable: () -> Bool
    @ObservationIgnored private let insightsUsable: () -> Bool
    @ObservationIgnored private let diagnostics: DiagnosticsLog
    // Runs the queues after flags are saved.
    @ObservationIgnored var onFlagged: (() -> Void)?

    init(
        settings: SettingsStore,
        presence: EditorPresence,
        titleUsable: @escaping () -> Bool,
        insightsUsable: @escaping () -> Bool = { false },
        diagnostics: DiagnosticsLog = .shared
    ) {
        self.settings = settings
        self.presence = presence
        self.titleUsable = titleUsable
        self.insightsUsable = insightsUsable
        self.diagnostics = diagnostics
    }

    static func isEligible(_ entry: Entry, automationStartedAt: Date?) -> Bool {
        guard !entry.automaticAIPassUsed, let automationStartedAt, entry.createdAt >= automationStartedAt else { return false }
        guard !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard !entry.awaitingText, !entry.textReviewPending, !entry.isDraft else { return false }
        // An unapproved photo entry never qualifies, so nothing can skip review.
        return entry.source != .photo || entry.pagesConfirmed
    }

    // Whether the editor offers Done: a draft waiting to be finished, or an entry whose text is ready
    // but hasn't had its automatic pass, like a recording just made. Done starts the pass right away
    // instead of when the entry closes.
    static func offersDone(_ entry: Entry, automationStartedAt: Date?) -> Bool {
        entry.isDraft || isEligible(entry, automationStartedAt: automationStartedAt)
    }

    // Returns true if the pass fired. The caller saves.
    @discardableResult
    func fire(for entry: Entry, at moment: Moment) -> Bool {
        guard Self.isEligible(entry, automationStartedAt: settings.automationStartedAt) else { return false }
        entry.automaticAIPassUsed = true
        let title = titleUsable() && (entry.title.isEmpty || entry.titleWasGenerated)
        let insights = insightsUsable()
        entry.titlePending = entry.titlePending || title
        entry.insightsPending = entry.insightsPending || insights
        diagnostics.record("ai.pass", ["id": .id(entry.id), "moment": .string(moment.rawValue), "title": .bool(title), "insights": .bool(insights)])
        return true
    }

    // Catches entries whose editor never closed because the app was killed.
    func sweep(context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { !$0.automaticAIPassUsed && !$0.awaitingText })
        var fired = 0
        for entry in (try? context.fetch(descriptor)) ?? [] where !presence.isOpen(entry.id) {
            if fire(for: entry, at: .launchSweep) { fired += 1 }
        }
        return fired
    }
}
