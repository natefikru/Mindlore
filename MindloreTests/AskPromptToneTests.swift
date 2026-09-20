import Foundation
import Testing
@testable import Mindlore

// The half of Ask nobody can unit-test by reading an answer: what the prompt actually asks for.
// An answer that narrates its own retrieval ("these are the 15 that best match") came from a note
// the prompt handed over as an instruction, so the instructions are what these tests hold.
struct AskPromptToneTests {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    @Test func theSystemPromptAsksForAVoiceBeforeItAsksForAnything() {
        let system = AskPrompt.system(today: now)
        #expect(system.hasPrefix(AskPrompt.opening))
        #expect(system.contains("plain sentences"))
        #expect(system.contains("Not a report."))
    }

    @Test func theSystemPromptForbidsTalkingAboutRetrieval() {
        let system = AskPrompt.system(today: now)
        for forbidden in ["searching", "matching", "what you can see", "how much of the journal you have"] {
            #expect(system.contains(forbidden), "the silence rule lost \"\(forbidden)\"")
        }
        // The worked contrast, which is the part that made the rule stick.
        #expect(system.contains("never \"your entry from 14 March says"))
    }

    // OpenAI returns citations in a field, so no handle belongs in the prose. The on-device model
    // has no structured output and has to mark them inline, where the parser takes them back out.
    @Test func onlyTheOnDeviceModelIsToldToWriteHandlesInline() {
        let cloud = AskPrompt.system(today: now, provider: .openAI)
        #expect(cloud.contains("citations field"))
        #expect(cloud.contains("Never write a handle"))
        #expect(cloud.contains("[E3]") == false)

        let device = AskPrompt.system(today: now, provider: .onDevice)
        #expect(device.contains("[E3]"))
        #expect(device.contains("citations field") == false)
    }

    // The short prompt exists because the whole on-device session is 6,000 characters. It may drop
    // the examples; it may not drop a rule that keeps an answer safe or quiet.
    @Test func theOnDevicePromptStaysShortWithoutLosingTheRules() {
        let device = AskPrompt.system(today: now, provider: .onDevice)
        let cloud = AskPrompt.system(today: now, provider: .openAI)
        #expect(device.count < cloud.count)
        #expect(device.count < 1_400)
        #expect(device.contains("Never mention entries, searching"))
        #expect(device.contains("No advice, no diagnosis"))
        #expect(device.contains(AskContextBuilder.openDelimiter))
    }

    @Test func thePermissionsAreAPatternAndOneQuestionAndNothingElse() {
        let system = AskPrompt.system(today: now)
        #expect(system.contains("name a pattern you actually see"))
        #expect(system.contains("ask one short question back"))
        #expect(system.contains("No advice, no diagnosis, no plan, no verdict on a life"))
    }

    @Test func theSummaryRuleTellsItToUseTheCountsAndNeverMentionThem() {
        let withSummary = AskPrompt.system(today: now, hasSummaries: true)
        #expect(withSummary.contains(AskPrompt.summaryRule))
        #expect(AskPrompt.summaryRule.contains("never mention that a list of counts exists"))
        #expect(AskPrompt.system(today: now, hasSummaries: false).contains(AskPrompt.summaryRule) == false)
    }

    // Every note is written to the model about the model's own situation, so every one of them has
    // to say it is not for the answer. This is the regression test for the sentence that started
    // the whole complaint: "say what you are looking at".
    @Test func everyNoteGagsItself() {
        var plan = AskRetrieval.Plan()
        plan.rankedEntryIDs = [UUID(), UUID()]
        plan.matchedCount = 40
        plan.appliedRange = DateInterval(start: now.addingTimeInterval(-86_400 * 30), duration: 86_400 * 30)
        plan.rangeWasInherited = true
        var context = AskContextBuilder.Context()
        context.entryIDs = plan.rankedEntryIDs
        context.matchedCount = 40

        let notes = AskPrompt.notes(for: context, plan: plan)
        #expect(notes.count == 2)
        #expect(notes.allSatisfy { $0.contains("for you, not for the answer") })
        #expect(notes.contains { $0.contains("You can see 2 of the 40") })
        #expect(notes.joined().contains("say what you are looking at") == false)
    }

    @Test func aQuestionThatMatchedNothingIsToldToSaySoWithoutDescribingTheLookup() {
        var plan = AskRetrieval.Plan()
        plan.matchedNothing = true
        var context = AskContextBuilder.Context()
        context.entryIDs = [UUID()]

        let notes = AskPrompt.notes(for: context, plan: plan)
        #expect(notes.count == 1)
        #expect(notes[0].contains("don't describe having looked"))
        #expect(notes[0].contains("one plain sentence"))
    }
}
