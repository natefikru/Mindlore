import Foundation
import Testing
@testable import Mindlore

struct InsightsPresentationTests {
    private func inputs(_ change: (inout InsightsPresentation.Inputs) -> Void) -> InsightsPresentation.Inputs {
        var inputs = InsightsPresentation.Inputs(aiEnabled: true, hasKey: true)
        change(&inputs)
        return inputs
    }

    @Test func blockedStatesComeFirstAndExplainThemselves() {
        #expect(InsightsPresentation.state(inputs { $0.running = true }) == .running)
        #expect(InsightsPresentation.state(inputs { $0.awaitingText = true }) == .awaitingText)
        #expect(InsightsPresentation.state(inputs { $0.textReviewPending = true }) == .awaitingApproval)
        #expect(InsightsPresentation.state(inputs { $0.aiEnabled = false }) == .aiOff)
        #expect(InsightsPresentation.state(inputs { $0.hasKey = false }) == .missingKey)
        #expect(InsightsPresentation.state(inputs { $0.isDraft = true }) == .draft)

        for state in [InsightsPresentation.State.aiOff, .missingKey, .awaitingText, .awaitingApproval, .running] {
            #expect(InsightsPresentation.runButtonTitle(for: state) == nil, "\(state)")
            #expect(InsightsPresentation.explanation(for: state) != nil, "\(state)")
        }
    }

    @Test func aDraftOffersToFinishInsteadOfRunning() {
        let state = InsightsPresentation.state(inputs { $0.isDraft = true })
        #expect(InsightsPresentation.runButtonTitle(for: state) == "Finish and generate insights")
        #expect(InsightsPresentation.explanation(for: state) == "Insights run on finished entries, so they read what you meant to write.")
    }

    @Test func resultStatesAndTheirButtons() {
        let none = InsightsPresentation.state(inputs { _ in })
        let current = InsightsPresentation.state(inputs { $0.hasInsights = true; $0.insightsAreCurrent = true })
        let stale = InsightsPresentation.state(inputs { $0.hasInsights = true })
        let empty = InsightsPresentation.state(inputs { $0.hasInsights = true; $0.insightsAreCurrent = true; $0.insightsAreEmpty = true })

        #expect((none, current, stale, empty) == (.none, .current, .stale, .empty))
        #expect(InsightsPresentation.runButtonTitle(for: none) == "Generate insights")
        #expect(InsightsPresentation.runButtonTitle(for: stale) == "Update insights")
        #expect(InsightsPresentation.runButtonTitle(for: current) == "Generate again")
        #expect(InsightsPresentation.runButtonTitle(for: empty) == "Generate again")
        #expect(InsightsPresentation.explanation(for: stale) == "Your entry changed since these insights.")
        #expect(InsightsPresentation.explanation(for: current) == nil)
    }

    @Test func spendingAgainOnCurrentInsightsIsConfirmedFirst() {
        #expect(InsightsPresentation.confirmsBeforeRunning(.current))
        #expect(InsightsPresentation.confirmsBeforeRunning(.empty))
        #expect(!InsightsPresentation.confirmsBeforeRunning(.stale))
        #expect(!InsightsPresentation.confirmsBeforeRunning(.none))
        #expect(!InsightsPresentation.confirmsBeforeRunning(.failed("x")))
    }

    @Test func aFailureShowsUntilInsightsAreCurrentAgain() {
        let failed = InsightsPresentation.state(inputs { $0.failure = AIJobFailure(.invalidKey) })
        #expect(failed == .failed(AIError.invalidKey.userMessage))
        #expect(InsightsPresentation.runButtonTitle(for: failed) == "Try again")
        // Insights that still match the entry outrank an older failure.
        #expect(InsightsPresentation.state(inputs { $0.failure = AIJobFailure(.invalidKey); $0.hasInsights = true; $0.insightsAreCurrent = true }) == .current)
    }

    // Opening insights on an entry that has none starts the run; anything else waits for a tap.
    @Test func openingRunsOnlyAFirstRunWithNothingInTheWay() {
        #expect(InsightsPresentation.runsWhenOpened(inputs { _ in }))

        // Spending again, retrying a failure, and finishing a draft all stay deliberate.
        #expect(!InsightsPresentation.runsWhenOpened(inputs { $0.hasInsights = true; $0.insightsAreCurrent = true }))
        #expect(!InsightsPresentation.runsWhenOpened(inputs { $0.hasInsights = true }))
        #expect(!InsightsPresentation.runsWhenOpened(inputs { $0.failure = AIJobFailure(any: AIError.invalidKey) }))
        #expect(!InsightsPresentation.runsWhenOpened(inputs { $0.isDraft = true }))

        // Nothing to analyze, or not allowed to yet.
        #expect(!InsightsPresentation.runsWhenOpened(inputs { $0.hasText = false }))
        #expect(!InsightsPresentation.runsWhenOpened(inputs { $0.awaitingText = true }))
        #expect(!InsightsPresentation.runsWhenOpened(inputs { $0.textReviewPending = true }))
        #expect(!InsightsPresentation.runsWhenOpened(inputs { $0.running = true }))
        #expect(!InsightsPresentation.runsWhenOpened(inputs { $0.aiEnabled = false }))
        #expect(!InsightsPresentation.runsWhenOpened(inputs { $0.hasKey = false }))
    }

    @Test func glyphTellsNoneCurrentStaleAndFailedApart() {
        #expect(InsightsPresentation.symbol(for: .failed("x")) == "exclamationmark.triangle")
        #expect(InsightsPresentation.symbol(for: .current) == "sparkles")
        #expect(!InsightsPresentation.isFilled(.none))
        #expect(InsightsPresentation.isFilled(.current))
        #expect(InsightsPresentation.isFilled(.stale))
        #expect(InsightsPresentation.showsStaleBadge(.stale))
        #expect(!InsightsPresentation.showsStaleBadge(.current))
    }

    @Test func theHeaderShowsTheModelWithoutItsProvider() {
        #expect(EntryInsightsView.modelName("openai:gpt-5.6-luna") == "gpt-5.6-luna")
        #expect(EntryInsightsView.modelName("gpt-5.6-luna") == "gpt-5.6-luna")
    }
}
