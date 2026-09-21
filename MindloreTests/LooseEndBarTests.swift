import Foundation
import Testing
@testable import Mindlore

// The bar the model is held to. A5b's journal produced loose ends for passing remarks, so the
// guidance now names the horizon and shows both sides.
@MainActor
struct LooseEndBarTests {
    private func system(handles: [InsightsPromptBuilder.KnownLooseEnd] = [], entryDate: Date? = nil) -> String {
        var sections = InsightSections()
        sections.looseEnds = true
        return InsightsPromptBuilder.plan(
            text: "I should call the landlord.",
            source: .voice,
            sections: sections,
            vocabulary: .init(looseEnds: handles),
            model: "gpt-test",
            entryDate: entryDate
        ).request.system
    }

    @Test func theBarIsACommitmentWorthKeeping() {
        let prompt = system()
        #expect(prompt.contains("A loose end is a commitment"))
        #expect(prompt.contains("worth keeping for days or weeks"))
        #expect(prompt.contains("still be open when the entry ends"))
    }

    @Test func bothSidesAreShown() {
        let prompt = system()
        #expect(prompt.contains("Yes: call the landlord about the lease."))
        #expect(prompt.contains("No: a feeling or a mood."))
        #expect(prompt.contains("grabbing coffee after this"))
    }

    @Test func zeroIsStillTheNormalAnswerAndTheCapIsInterpolated() {
        let prompt = system()
        #expect(prompt.contains("an empty list is the normal answer"))
        #expect(prompt.contains("Write at most \(InsightsPromptBuilder.maxNewLooseEnds) new ones."))
    }

    // The bar sits in front of the two blocks that follow it; rewriting it must leave them alone.
    @Test func theEntryDateSentenceSurvivesTheNewBar() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(system(entryDate: date).contains("read relative dates from that day"))
    }

    @Test func theKnownHandleBlockSurvivesTheNewBar() {
        let known = InsightsPromptBuilder.KnownLooseEnd(id: UUID(), text: "Call the clinic back", own: false)
        let prompt = system(handles: [known])
        #expect(prompt.contains("Known loose ends, one per line with its handle"))
        #expect(prompt.contains("give its handle as sameAs instead of writing a new one"))
        #expect(prompt.contains("- L1: Call the clinic back"))
    }
}
