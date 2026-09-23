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

    // The insights are what the real pipeline wrote (scripts/demo/regenerate-story.sh), so this
    // holds them to what a reviewed seed should be: every name is in the text as written, or as
    // the `writtenSurface` it was corrected from. Tags may be inferred rather than quoted, as they
    // are for a real entry, so they are held only to the parser's own shape.
    @Test func everyNameIsInTheTextAndEveryTagIsWellFormed() throws {
        for entry in try DemoStory.entries() {
            for mention in entry.mentions {
                let found = NameMatching.range(of: mention.name, in: entry.text) != nil
                    || mention.writtenSurface.map { NameMatching.range(of: $0, in: entry.text) != nil } == true
                #expect(found, "\(entry.date) \(mention.name)")
            }
            for tag in entry.tags {
                #expect(tag == tag.lowercased() && LifeArea(rawValue: tag) == nil, "\(entry.date) \(tag)")
            }
            #expect(entry.tags.count <= InsightsPromptBuilder.maxTags, "\(entry.date)")
            #expect(entry.areas.count <= LifeArea.maxPerEntry, "\(entry.date)")
            // What each kind keeps (InsightsResult.restrict): a creative piece has no area, no names,
            // and no parts; only a journal entry has a mood.
            if entry.kind == .creative {
                #expect(entry.areas.isEmpty && entry.mentions.isEmpty && entry.sections.isEmpty, "\(entry.date)")
            } else {
                #expect(!entry.areas.isEmpty, "\(entry.date)")
            }
            #expect((entry.mood != nil) == (entry.kind == .journal), "\(entry.date)")
            #expect(entry.opens.count <= InsightsPromptBuilder.maxNewLooseEnds, "\(entry.date)")
        }
    }

    // Parts as the parser stores them: capped, and each one starting after the last, inside the text.
    @Test func partsAreWellFormed() throws {
        for entry in try DemoStory.entries() {
            #expect(entry.sections.count <= InsightsPromptBuilder.maxSections, "\(entry.date)")
            let offsets = entry.sections.compactMap(\.offset)
            #expect(offsets == offsets.sorted() && Set(offsets).count == offsets.count, "\(entry.date)")
            #expect(offsets.allSatisfy { (0..<entry.text.count).contains($0) }, "\(entry.date)")
        }
    }

    // The fields the real pipeline adds reach the store: a written surface on the mention, the
    // parts on the insights, and the kind on the entry, with no mood for a note.
    @Test func seedingWritesPartsKindsAndWrittenSurfaces() throws {
        let fixture = #"""
        [
          {
            "date": "2025-09-23T19:10",
            "title": "Two things",
            "text": "Lunch with Sam at the diner. Later the landlord finally fixed the sink.",
            "summary": "Lunch with Sam, and the sink got fixed.",
            "mood": "content",
            "areas": ["friends", "home"],
            "tags": ["lunch"],
            "mentions": [{"name": "Samantha", "kind": "person", "writtenSurface": "Sam"}],
            "sections": [
              {"topic": "Lunch", "areasRaw": ["friends"], "tags": ["lunch"], "names": ["Samantha", "Sam"], "offset": 0},
              {"topic": "The sink", "areasRaw": ["home"], "tags": [], "names": [], "offset": 29}
            ]
          },
          {
            "date": "2025-09-24T09:00",
            "title": "Groceries",
            "text": "eggs, milk, coffee",
            "summary": "A grocery list.",
            "kind": "note",
            "areas": ["home"],
            "tags": [],
            "mentions": []
          }
        ]
        """#
        let story = try JSONDecoder().decode([DemoStory.StoryEntry].self, from: Data(fixture.utf8))
        let context = container.mainContext
        #expect(try DemoStory.seed(story, in: context, now: now) == 2)

        let entries = try context.fetch(FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.createdAt)]))
        #expect(entries.map(\.kind) == [.journal, .note])
        #expect(entries.first?.insights?.sections == story[0].sections)
        #expect(entries.first?.insights?.sections.map(\.offset) == [0, 29])
        #expect(entries.first?.insights?.mentions.first?.writtenSurface == "Sam")
        #expect(entries.last?.insights?.primaryMood == nil)
        #expect(entries.last?.insights?.sections.isEmpty == true)
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

    // Fading runs between entries the way daily launches would, so a thread the story settles
    // late has to still be open by then: resolved, not quietly faded first.
    @Test func everyThreadTheStorySettlesIsResolvedNotFaded() throws {
        let context = container.mainContext
        try DemoStory.seedIfEmpty(in: context, now: now)
        let story = try DemoStory.entries()
        let settled = Set(story.flatMap(\.resolves))
        let texts = Dictionary(uniqueKeysWithValues: story.flatMap(\.opens).map { ($0.id, $0.text) })
        let looseEnds = LooseEnd.all(in: context)
        #expect(looseEnds.count == texts.count)
        for id in settled {
            #expect(looseEnds.first { $0.text == texts[id] }?.status == .resolved, "\(id)")
        }
        // Nothing still open has gone quiet long enough that the next launch would fade it.
        #expect(looseEnds.filter(\.isOpen).allSatisfy { !LooseEnd.shouldFade($0, now: now) })
    }
}
