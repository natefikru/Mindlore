import Foundation
import Testing
@testable import Mindlore

// The voice reaches the prompts that write prose the user reads, and "the writer" is gone from
// every prompt the app sends.
@MainActor
struct PromptVoiceWiringTests {
    private func plan(_ voice: PromptVoice) -> InsightsRequestPlan {
        InsightsPromptBuilder.plan(
            text: "I walked to the river.",
            source: .voice,
            sections: InsightSections(),
            vocabulary: .empty,
            model: "gpt-test",
            voice: voice
        )
    }

    @Test func theInsightsSystemPromptCarriesTheVoiceInstruction() {
        #expect(plan(.default).request.system.contains("Write about the author in the first person, as I and my."))
        #expect(plan(PromptVoice(voice: .second, name: "")).request.system.contains("second person"))

        let named = plan(PromptVoice(voice: .name, name: "Nate"))
        #expect(named.request.system.contains("Write about the author by name, as Nate."))
    }

    // The other two voices have no use for the name, so it is never sent.
    @Test func theNameOnlyReachesTheProviderUnderTheNameVoice() {
        #expect(plan(PromptVoice(voice: .first, name: "Nate")).request.system.contains("Nate") == false)
        #expect(plan(PromptVoice(voice: .second, name: "Nate")).request.system.contains("Nate") == false)
        #expect(plan(PromptVoice(voice: .name, name: "Nate")).request.system.contains("Nate"))
    }

    @Test func theVoiceDoesNotChangeTheSchema() throws {
        let first = plan(.default)
        let named = plan(PromptVoice(voice: .name, name: "Nate"))
        #expect(first.request.schemaName == named.request.schemaName)
        #expect(first.asksForCleanedText == named.asksForCleanedText)
    }

    @Test func theBioPromptCarriesTheVoiceInstruction() throws {
        let excerpts = BioExcerpts.select(from: [
            BioExcerpts.Source(text: "I walked with Sarah by the river.", date: .now, surfaces: ["Sarah"])
        ])
        let request = try #require(EntityBioDrafter.request(
            name: "Sarah", kind: .person, excerpts: excerpts, model: "m",
            voice: PromptVoice(voice: .second, name: "")
        ))
        #expect(request.system.contains("second person"))
        #expect(request.system.contains("the author's journal"))
    }

    // The owner's complaint that started A8: the app called them "the writer".
    @Test func noPromptTheAppSendsSaysTheWriter() throws {
        let insights = plan(.default).request
        #expect(insights.system.lowercased().contains("the writer") == false)

        let excerpts = BioExcerpts.select(from: [
            BioExcerpts.Source(text: "I walked with Sarah by the river.", date: .now, surfaces: ["Sarah"])
        ])
        let bio = try #require(EntityBioDrafter.request(name: "Sarah", kind: .person, excerpts: excerpts, model: "m"))
        #expect(bio.system.lowercased().contains("the writer") == false)

        #expect(TitleCoordinator.systemPrompt.lowercased().contains("the writer") == false)
        #expect(OpenAICompatiblePageTranscriber.systemPrompt.lowercased().contains("the writer") == false)
    }

    // Life areas feed the insights guidance, so their wording ships in the prompt too.
    @Test func lifeAreaMeaningsDoNotSayTheWriter() {
        for area in LifeArea.allCases {
            #expect(area.meaning.lowercased().contains("the writer") == false, "\(area.rawValue)")
        }
    }
}
