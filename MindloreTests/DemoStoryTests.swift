import Foundation
import SwiftData
import Testing
@testable import Mindlore

@MainActor
struct DemoStoryTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    // Held for the test's lifetime: a context whose container is freed traps on first use.
    private let container: ModelContainer

    init() throws {
        container = try ModelContainerFactory.make(.inMemory)
    }

    @Test func theStoryIsTwoHundredEntriesInOrder() throws {
        let entries = try DemoStory.entries()
        #expect(entries.count == 200)
        #expect(entries.map(\.date) == entries.map(\.date).sorted())
        #expect(entries.allSatisfy { DemoStory.written(from: $0.date) != nil })
    }

    // The same promise the insights pipeline keeps: a name, a tag, or an area is only there
    // because the text says so.
    @Test func everyNameAndTagIsInTheText() throws {
        for entry in try DemoStory.entries() {
            for mention in entry.mentions {
                #expect(NameMatching.range(of: mention.name, in: entry.text) != nil, "\(entry.date) \(mention.name)")
            }
            for tag in entry.tags {
                #expect(NameMatching.range(of: tag, in: entry.text) != nil, "\(entry.date) \(tag)")
                #expect(tag == tag.lowercased() && LifeArea(rawValue: tag) == nil, "\(entry.date) \(tag)")
            }
            #expect((1...LifeArea.maxPerEntry).contains(entry.areas.count), "\(entry.date)")
            #expect(entry.opens.count <= InsightsPromptBuilder.maxNewLooseEnds, "\(entry.date)")
        }
    }

    @Test func looseEndsCloseOnlyAfterTheyOpen() throws {
        var opened: Set<String> = []
        for entry in try DemoStory.entries() {
            for id in entry.resolves + entry.touches {
                #expect(opened.contains(id), "\(entry.date) \(id)")
            }
            let names = Set(entry.mentions.map(\.name))
            for looseEnd in entry.opens {
                #expect(!opened.contains(looseEnd.id), "\(looseEnd.id) opened twice")
                #expect(Set(looseEnd.about).isSubset(of: names), "\(entry.date) \(looseEnd.id)")
                opened.insert(looseEnd.id)
            }
        }
    }

    @Test func theYearEndsOnTheDayItIsSeeded() throws {
        let dates = DemoStory.dates(for: try DemoStory.entries(), now: now)
        let last = try #require(dates.last)
        let first = try #require(dates.first)
        #expect(last <= now)
        #expect(now.timeIntervalSince(last) < 86_400)
        #expect((360...366).contains(Calendar.current.dateComponents([.day], from: first, to: last).day ?? 0))
    }

    @Test func seedingWritesTheJournalTheGraphAndTheLooseEnds() throws {
        let context = container.mainContext
        #expect(try DemoStory.seedIfEmpty(in: context, now: now) == 200)

        let entries = try context.fetch(FetchDescriptor<Entry>())
        #expect(entries.count == 200)
        #expect(entries.allSatisfy { $0.insights?.isCurrent(for: $0) == true && $0.automaticAIPassUsed && $0.createdAt <= now })

        // One cast, not a new stranger per entry: the people who carry the story each land on one
        // entity with plenty of links.
        let entities = try context.fetch(FetchDescriptor<Entity>())
        for name in ["Maya", "Danny", "Mom", "Dad", "Dr. Adler"] {
            let matches = entities.filter { $0.name == name && $0.mergedIntoID == nil }
            #expect(matches.count == 1, "\(name)")
            #expect((matches.first?.linkCount ?? 0) >= 8, "\(name)")
        }

        // The plot's threads end the way the story does: the confession is made, the move-in
        // question is never answered, and the last days still leave something on the list.
        let looseEnds = LooseEnd.all(in: context)
        #expect(looseEnds.first { $0.text == "Tell Maya the truth about Lauren" }?.status == .resolved)
        #expect(looseEnds.first { $0.text == "Give Maya an answer about moving in" }?.status == .faded)
        #expect(looseEnds.contains { $0.isOpen })
        #expect(try DemoStory.seedIfEmpty(in: context, now: now) == 0)
    }
}
