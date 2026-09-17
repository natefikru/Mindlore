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

    @Test func everyEntryIsFiledUnderOneOrTwoAreas() throws {
        let drafts = DemoJournal.makeEntries(count: 200, now: now)
        #expect(drafts.allSatisfy { (1...2).contains($0.areas.count) && Set($0.areas).count == $0.areas.count })
        #expect(Set(drafts.flatMap(\.areas)).count == LifeArea.allCases.count)

        let context = context()
        try DemoJournal.seedIfEmpty(count: 20, in: context, now: now)
        #expect(try context.fetch(FetchDescriptor<EntryInsights>()).allSatisfy { !$0.areas.isEmpty })
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
