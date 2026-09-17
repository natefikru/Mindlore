import Foundation
import Testing
@testable import Mindlore

struct LifeAreaTests {
    // Raw values are stored and sent to the model, so the list only ever changes on purpose.
    @Test func theListIsPinned() {
        #expect(LifeArea.allCases.map(\.rawValue) == ["work", "money", "health", "mind", "family", "love", "friends", "play", "home"])
        #expect(LifeArea.maxPerEntry == 2)
    }

    @Test func theSchemaOffersExactlyTheListAndThePromptExplainsIt() throws {
        let plan = InsightsPromptBuilder.plan(text: "x", source: .typed, sections: InsightSections(), vocabulary: .empty, model: "m")
        let schema = try #require(plan.request.schema)
        let json = try #require(JSONSerialization.jsonObject(with: try schema.jsonData()) as? [String: Any])
        let properties = try #require(json["properties"] as? [String: [String: Any]])
        let items = try #require(properties["lifeAreas"]?["items"] as? [String: Any])
        #expect(items["enum"] as? [String] == LifeArea.allCases.map(\.rawValue))
        #expect(plan.request.system.contains("- home: where the writer lives"))
        #expect(plan.request.system.contains("Pick mind only when the entry is about the writer's inner life itself"))
        #expect(plan.request.system.contains("add a second only when the entry is clearly about both"))
    }

    @Test func switchingAreasOffLeavesThemOutOfTheRequest() throws {
        var sections = InsightSections()
        sections.lifeAreas = false
        let plan = InsightsPromptBuilder.plan(text: "x", source: .typed, sections: sections, vocabulary: .empty, model: "m")
        #expect(!plan.request.system.contains("Life areas come only"))
        #expect(plan.request.schema.map { String(decoding: (try? $0.jsonData()) ?? Data(), as: UTF8.self).contains("lifeAreas") } == false)
    }

    @Test func parsingDropsUnknownsAndDuplicatesAndCapsAtTwo() throws {
        let plan = InsightsPromptBuilder.plan(text: "x", source: .typed, sections: InsightSections(), vocabulary: .empty, model: "m")
        let result = try InsightsPromptBuilder.parse(#"{"lifeAreas":["career","Work","work","HOME","love"]}"#, plan: plan)
        #expect(result.areas == [.work, .home])
        #expect(try InsightsPromptBuilder.parse(#"{"lifeAreas":"work"}"#, plan: plan).areas.isEmpty)
    }

    @Test func storedAreasReadBackAndIgnoreUnknownValues() {
        let insights = EntryInsights()
        insights.areas = [.mind, .love]
        #expect(insights.areasRaw == ["mind", "love"])
        insights.areasRaw = ["mind", "retired-area"]
        #expect(insights.areas == [.mind])
    }

    @Test func distributionCountsEachEntryOncePerArea() {
        let shares = LifeAreaDistribution.shares([[.work], [.work, .friends], [.home], [.work]])
        let percent = Dictionary(uniqueKeysWithValues: shares.map { ($0.area, $0.percent) })
        #expect(percent[.work] == 75)
        #expect(percent[.friends] == 25)
        #expect(percent[.money] == 0)
        #expect(LifeAreaDistribution.shares([]).allSatisfy { $0.percent == 0 })
    }
}

@MainActor
struct LifeAreaSettingsTests {
    @Test func renamesAndHidingPersistAndFallBackToTheDefaults() {
        let store = FakeKeyValueStore()
        let settings = SettingsStore(store: store, diagnostics: .disabled)
        #expect(settings.name(of: .play) == "Play")
        #expect(settings.visibleLifeAreas == LifeArea.allCases)

        settings.rename(.play, to: "  Hobbies  ")
        settings.setHidden(.money, true)
        let reopened = SettingsStore(store: store, diagnostics: .disabled)
        #expect(reopened.name(of: .play) == "Hobbies")
        #expect(reopened.isHidden(.money))
        #expect(!reopened.visibleLifeAreas.contains(.money))

        reopened.rename(.play, to: "   ")
        reopened.setHidden(.money, false)
        #expect(reopened.name(of: .play) == "Play")
        #expect(reopened.lifeAreaNames.isEmpty)
        #expect(!reopened.isHidden(.money))
    }

    @Test func aRenameIsTrimmedAndCapped() {
        let settings = SettingsStore(store: FakeKeyValueStore(), diagnostics: .disabled)
        settings.rename(.work, to: String(repeating: "x", count: 80))
        #expect(settings.name(of: .work).count == 30)
        settings.rename(.work, to: "Work")
        #expect(settings.lifeAreaNames[LifeArea.work.rawValue] == nil, "the default name isn't stored")
    }

    // The model always gets the built-in values, whatever the user renamed.
    @Test func renamesNeverReachTheRequest() {
        let settings = SettingsStore(store: FakeKeyValueStore(), diagnostics: .disabled)
        settings.rename(.work, to: "The Grind")
        let plan = InsightsPromptBuilder.plan(text: "x", source: .typed, sections: AIServices.insightSections(settings), vocabulary: .empty, model: "m")
        #expect(!plan.request.system.contains("The Grind"))
        #expect(plan.request.system.contains("- work: job, school"))
    }
}
