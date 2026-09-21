import Foundation
import SwiftData
import Testing
@testable import Mindlore

@MainActor
struct DemoJournalTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    // Held for the test's lifetime: a context whose container is freed traps on first use.
    private let container: ModelContainer

    init() throws {
        container = try ModelContainerFactory.make(.inMemory)
    }

    private func context() -> ModelContext {
        container.mainContext
    }

    @Test func seedsTheRequestedEntriesAndIndexesThem() throws {
        let context = context()
        #expect(try DemoJournal.seedIfEmpty(count: 60, in: context, now: now) == 60)

        let entries = try context.fetch(FetchDescriptor<Entry>())
        #expect(entries.count == 60)
        #expect(entries.allSatisfy { $0.insights != nil && $0.graphIndexedAt == $0.insights?.generatedAt })
        #expect(try context.fetchCount(FetchDescriptor<EntityLink>()) > 60)
        #expect(try context.fetchCount(FetchDescriptor<Entity>()) > 20)
    }

    @Test func entriesAreBackdatedAndNeverEligibleForTheAutomaticPass() throws {
        let context = context()
        try DemoJournal.seedIfEmpty(count: 30, in: context, now: now)
        let entries = try context.fetch(FetchDescriptor<Entry>())
        #expect(entries.allSatisfy { $0.createdAt < now && $0.automaticAIPassUsed && !$0.isDraft })
        #expect(entries.allSatisfy { $0.insights?.isCurrent(for: $0) == true })
        #expect(entries.allSatisfy { !AIPassTrigger.isEligible($0, automationStartedAt: .distantPast) })
    }

    @Test func mentionedNamesAppearInTheEntryText() {
        for draft in DemoJournal.makeEntries(count: 40, now: now) {
            for mention in draft.mentions {
                #expect(NameMatching.range(of: mention.name, in: draft.text) != nil)
            }
        }
    }

    // A tag the text never mentions made the demo map look wrong under a tag's page.
    @Test func everyTagIsAWordInItsEntryAndNeverAnAreaName() {
        let areaNames = Set(LifeArea.allCases.map(\.rawValue))
        let drafts = DemoJournal.makeEntries(count: 300, now: now)
        #expect(drafts.allSatisfy { !$0.tags.isEmpty })
        for draft in drafts {
            for tag in draft.tags {
                #expect(NameMatching.range(of: tag, in: draft.text) != nil, "\(tag) in \(draft.text)")
                #expect(!areaNames.contains(tag))
            }
        }
        #expect(DemoJournal.Scene.weighted.flatMap(\.topics).allSatisfy { topic in topic.tags.allSatisfy { NameMatching.range(of: $0, in: topic.sentence) != nil } })
    }

    // The 300-entry seed is what the device gate measures, so it has to stay a busy map.
    @Test func theLargeSeedStillMakesABusyMap() throws {
        let context = context()
        try DemoJournal.seedIfEmpty(count: 300, in: context, now: now)
        let data = GraphServices(diagnostics: .disabled).globalGraph(asOf: now, kinds: nil, minimumLinkCount: 2, in: context)
        #expect(data.nodes.count >= 150, "\(data.nodes.count) nodes")
    }

    // A scene decides who, where, what, and how it felt together: a coworker only turns up at work,
    // under their own organization, and the mood is one the text describes.
    @Test func scenesKeepPeopleAndOrganizationsTogether() {
        let drafts = DemoJournal.makeEntries(count: 300, now: now)
        var orgsByPerson: [String: Set<String>] = [:]
        for draft in drafts {
            let orgs = draft.mentions.filter { $0.kind == .organization }.map(\.name)
            guard let org = orgs.first, let lead = draft.mentions.first(where: { $0.kind == .person }) else { continue }
            #expect(draft.areas.first == .work)
            orgsByPerson[lead.name, default: []].insert(org)
        }
        #expect(!orgsByPerson.isEmpty)
        #expect(orgsByPerson.values.allSatisfy { $0.count == 1 }, "a coworker works in one place")
        let topicMoods = Set(DemoJournal.Scene.weighted.flatMap(\.topics).map(\.mood))
        #expect(drafts.allSatisfy { topicMoods.contains($0.primaryMood) })
    }

    // Loose ends are sentences in the entry, and a settled one is settled in a later entry's words.
    @Test func looseEndsAreWrittenIntoTheText() {
        let drafts = DemoJournal.makeEntries(count: 120, now: now)
        let opened = drafts.compactMap { draft in draft.opens.map { (draft, $0) } }
        #expect(opened.count >= 15)
        #expect(opened.allSatisfy { $0.0.text.contains($0.1.opened) })
        let settling = drafts.filter { $0.settles != nil }
        #expect(settling.count >= 5)
        for draft in settling {
            #expect(opened.contains { draft.text.contains($0.1.settled) })
        }
    }

    @Test func everyEntryIsFiledUnderOneOrTwoAreas() throws {
        let drafts = DemoJournal.makeEntries(count: 200, now: now)
        #expect(drafts.allSatisfy { (1...2).contains($0.areas.count) && Set($0.areas).count == $0.areas.count })
        #expect(Set(drafts.flatMap(\.areas)).count == LifeArea.allCases.count)

        let context = context()
        try DemoJournal.seedIfEmpty(count: 20, in: context, now: now)
        #expect(try context.fetch(FetchDescriptor<EntryInsights>()).allSatisfy { !$0.areas.isEmpty })
    }

    @Test func looseEndsAreSpreadAcrossTheJournalInEveryState() throws {
        let context = context()
        try DemoJournal.seedIfEmpty(count: 300, in: context, now: now)
        let all = LooseEnd.all(in: context)
        let byStatus = Dictionary(grouping: all, by: \.status).mapValues(\.count)
        #expect(all.count >= 40)
        #expect(byStatus[.open, default: 0] > 0 && byStatus[.faded, default: 0] > 0 && byStatus[.resolved, default: 0] > 0)
        #expect(all.allSatisfy { !$0.entityIDs.isEmpty }, "each is about its entry's first person")
    }

    @Test func frequentPeopleHaveVariedSurnames() {
        let people = DemoJournal.makeEntries(count: 1200, now: now)
            .flatMap(\.mentions).filter { $0.kind == .person }.map(\.name)
        let surnames = Set(people.prefix(80).compactMap { $0.split(separator: " ").last })
        #expect(surnames.count > 10)
    }

    @Test func theSameCountAndDateWriteTheSameJournal() {
        #expect(DemoJournal.makeEntries(count: 50, now: now) == DemoJournal.makeEntries(count: 50, now: now))
    }

    @Test func aStoreThatAlreadyHasEntriesIsLeftAlone() throws {
        let context = context()
        try DemoJournal.seedIfEmpty(count: 10, in: context, now: now)
        #expect(try DemoJournal.seedIfEmpty(count: 10, in: context, now: now) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Entry>()) == 10)
    }

    @Test func threeHundredEntriesGiveAGraphOfRoughlyThreeHundredNodes() throws {
        let context = context()
        try DemoJournal.seedIfEmpty(count: 300, in: context, now: now)
        let entities = try context.fetchCount(FetchDescriptor<Entity>())
        #expect((200...360).contains(entities))
    }

    @Test func theArgumentReadsItsCountOrDefaultsTo300() {
        #expect(DemoJournal.requestedCount(in: ["app"]) == nil)
        #expect(DemoJournal.requestedCount(in: ["app", "-seedDemoJournal", "120"]) == 120)
        #expect(DemoJournal.requestedCount(in: ["app", "-seedDemoJournal"]) == 300)
        #expect(DemoJournal.requestedCount(in: ["app", "-seedDemoJournal", "-other"]) == 300)
    }

    @Test func theDemoNeverOpensTheDefaultStore() {
        let directory = URL(fileURLWithPath: "/tmp/demo-test")
        let location = StoreLocation.resolve(arguments: ["app", "-seedDemoJournal", "50"], environment: [:], directory: directory)
        #expect(location == .file(directory.appendingPathComponent(DemoJournal.storeFileName)))
        // UI tests keep their own named store even if the argument is present.
        let uiTest = StoreLocation.resolve(
            arguments: ["app", "-uiTesting", "-seedDemoJournal", "50"],
            environment: [StoreLocation.uiTestStoreNameKey: "x"],
            directory: directory
        )
        #expect(uiTest == .file(directory.appendingPathComponent("uitest-x.store")))
    }
}
