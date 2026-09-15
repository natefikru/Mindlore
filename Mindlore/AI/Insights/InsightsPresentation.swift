import Foundation

// What the insights screen and the entry's sparkles glyph should show. Kept out of the views so the
// wording and the rules are testable.
nonisolated enum InsightsPresentation {
    enum State: Equatable {
        case aiOff
        case missingKey
        case draft
        case awaitingText
        case awaitingApproval
        case running
        case failed(String)
        // No insights yet, and nothing is stopping a run.
        case none
        case current
        case stale
        // Ran, but every section came back empty.
        case empty
    }

    struct Inputs {
        var isDraft = false
        var awaitingText = false
        var textReviewPending = false
        var hasText = true
        var hasInsights = false
        var insightsAreEmpty = false
        var insightsAreCurrent = false
        var running = false
        var failure: AIJobFailure?
        var aiEnabled = false
        var hasKey = false
    }

    static func state(_ inputs: Inputs) -> State {
        if inputs.running { return .running }
        if inputs.awaitingText { return .awaitingText }
        if inputs.textReviewPending { return .awaitingApproval }
        if !inputs.aiEnabled { return .aiOff }
        if !inputs.hasKey { return .missingKey }
        if let failure = inputs.failure, !inputs.hasInsights || !inputs.insightsAreCurrent { return .failed(failure.userMessage) }
        if inputs.isDraft { return .draft }
        if !inputs.hasText { return .none }
        guard inputs.hasInsights else { return .none }
        if !inputs.insightsAreCurrent { return .stale }
        return inputs.insightsAreEmpty ? .empty : .current
    }

    // The button that starts a run, or nil when running isn't the next step.
    static func runButtonTitle(for state: State) -> String? {
        switch state {
        case .none: "Generate insights"
        case .stale: "Update insights"
        case .current, .empty: "Generate again"
        case .failed: "Try again"
        case .draft: "Finish and generate insights"
        case .aiOff, .missingKey, .awaitingText, .awaitingApproval, .running: nil
        }
    }

    // Asked before spending again on an entry whose insights already match its text.
    static func confirmsBeforeRunning(_ state: State) -> Bool {
        state == .current || state == .empty
    }

    static func explanation(for state: State) -> String? {
        switch state {
        case .aiOff: "Turn on AI in Settings to generate insights."
        case .missingKey: "Add your OpenAI key in Settings to generate insights."
        case .draft: "Insights run on finished entries, so they read what you meant to write."
        case .awaitingText: "Insights run once this entry's text is ready."
        case .awaitingApproval: "Approve this entry's text first."
        case .running: "Reading this entry…"
        case .none: "Nothing has been generated for this entry yet."
        case .stale: "Your entry changed since these insights."
        case .empty: "Nothing to show for this entry."
        case .current, .failed: nil
        }
    }

    // The glyph on the entry row and the editor toolbar.
    static func symbol(for state: State) -> String {
        switch state {
        case .failed: "exclamationmark.triangle"
        case .current, .empty: "sparkles"
        case .stale: "sparkles"
        default: "sparkles"
        }
    }

    static func showsStaleBadge(_ state: State) -> Bool {
        state == .stale
    }

    static func isFilled(_ state: State) -> Bool {
        switch state {
        case .current, .empty, .stale: true
        default: false
        }
    }
}
