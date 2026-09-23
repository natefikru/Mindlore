import Foundation
import Testing
@testable import Mindlore

struct EntityNameRangesTests {
    private let sarah = UUID()
    private let sarahKim = UUID()
    private let tom = UUID()

    private func linked(_ text: String, _ candidates: [EntityNameRanges.Candidate]) -> [(String, UUID)] {
        EntityNameRanges.matches(in: text, candidates: candidates).map { (String(text[$0.range]), $0.entityID) }
    }

    @Test func theLongerOverlappingNameWins() {
        let result = linked("Met Sarah Kim, then Sarah alone.", [
            .init(entityID: sarah, kind: .person, names: ["Sarah"]),
            .init(entityID: sarahKim, kind: .person, names: ["Sarah Kim"]),
        ])
        #expect(result.map(\.0) == ["Sarah Kim", "Sarah"])
        #expect(result.map(\.1) == [sarahKim, sarah])
    }

    @Test func aliasesAndWrittenSpellingsMatchAndPossessivesLinkOnlyTheName() {
        let result = linked("Tommy's bike and Tomás rode off.", [
            .init(entityID: tom, kind: .person, names: ["Tom", "Tommy", "Tomás"]),
        ])
        #expect(result.map(\.0) == ["Tommy", "Tomás"])
    }

    @Test func everyOccurrenceLinksInOrderWithoutOverlap() {
        let text = "Sarah, sarah, and SARAH."
        let matches = EntityNameRanges.matches(in: text, candidates: [.init(entityID: sarah, kind: .person, names: ["Sarah", "sarah"])])
        #expect(matches.count == 3)
        #expect(zip(matches, matches.dropFirst()).allSatisfy { $0.range.upperBound <= $1.range.lowerBound })
    }

    @Test func aCapitalisedNameNeedsACapitalInTheText() {
        let will = UUID()
        let result = linked("I will call Will. WILL answered, may be later.", [
            .init(entityID: will, kind: .person, names: ["Will"]),
            .init(entityID: tom, kind: .place, names: ["may"]),
        ])
        #expect(result.map(\.0) == ["Will", "WILL", "may"])
    }

    @Test func oneLetterAndEmptyNamesAreSkipped() {
        #expect(linked("A day with J and a walk.", [.init(entityID: tom, kind: .person, names: ["J", "", " "])]).isEmpty)
    }

    @Test func twoEntitiesOnTheSameWordsResolveTheSameWayEveryTime() {
        let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let a = linked("Lunch at Rosa.", [.init(entityID: second, kind: .place, names: ["Rosa"]), .init(entityID: first, kind: .person, names: ["Rosa"])])
        let b = linked("Lunch at Rosa.", [.init(entityID: first, kind: .person, names: ["Rosa"]), .init(entityID: second, kind: .place, names: ["Rosa"])])
        #expect(a.map(\.1) == [first])
        #expect(b.map(\.1) == [first])
    }

    @Test func aMatchEndingInsideADecomposedAccentIsDropped() {
        let text = "Saw Jose\u{0301} today."
        #expect(linked(text, [.init(entityID: tom, kind: .person, names: ["Jose"])]).isEmpty)
    }

    @Test func namesWithPunctuationAreMatchedLiterally() {
        #expect(linked("Went to C.J.'s (the diner).", [.init(entityID: tom, kind: .place, names: ["C.J."])]).map(\.0) == ["C.J."])
    }
}

@MainActor
struct EntryNameLinksTests {
    private let entryID = UUID()

    private func link(_ surface: String, kind: EntityKind = .person, to entity: Entity, entry: UUID? = nil, written: String? = nil) -> EntityLink {
        let link = EntityLink(surface: surface, kind: kind)
        link.entityID = entity.id
        link.entryID = entry ?? entryID
        link.writtenSurface = written
        return link
    }

    @Test func aMergedEntityLinksToTheWinnerWithItsNames() {
        let winner = Entity(name: "Sarah Kim", key: "sarah kim", kind: .person)
        winner.aliases = ["Sar"]
        let loser = Entity(name: "Sara", key: "sara", kind: .person)
        loser.mergedIntoID = winner.id
        let candidates = EntryNameLinks.candidates(
            forEntry: entryID,
            links: [link("Sara", to: loser, written: "Sarah"), link("Sarah Kim", to: winner)],
            entities: [winner, loser]
        )
        #expect(candidates.count == 1)
        #expect(candidates.first?.entityID == winner.id)
        #expect(Set(candidates.first?.names ?? []) == ["Sarah", "Sara", "Sarah Kim", "Sar"])
    }

    @Test func hiddenMissingTagAndOtherEntryLinksAreLeftOut() {
        let hidden = Entity(name: "Ghost", key: "ghost", kind: .person)
        hidden.hidden = true
        let tag = Entity(name: "river", key: "river", kind: .tag)
        let elsewhere = Entity(name: "Tom", key: "tom", kind: .person)
        let missing = Entity(name: "Gone", key: "gone", kind: .person)
        let candidates = EntryNameLinks.candidates(
            forEntry: entryID,
            links: [link("Ghost", to: hidden), link("river", kind: .tag, to: tag), link("Tom", to: elsewhere, entry: UUID()), link("Gone", to: missing)],
            entities: [hidden, tag, elsewhere]
        )
        #expect(candidates.isEmpty)
    }

    @Test func aMergeCycleEndsWithoutHanging() {
        let a = Entity(name: "A person", key: "a person", kind: .person)
        let b = Entity(name: "B person", key: "b person", kind: .person)
        a.mergedIntoID = b.id
        b.mergedIntoID = a.id
        let candidates = EntryNameLinks.candidates(forEntry: entryID, links: [link("A person", to: a)], entities: [a, b])
        // Both are merged, so neither is browsable and nothing links.
        #expect(candidates.isEmpty)
    }

    @Test func linksCoverTheNameAndOpenItsEntity() throws {
        let tom = UUID()
        let text = "Met Tom's dog."
        let links = EntryNameLinks.links(in: text, candidates: [.init(entityID: tom, kind: .person, names: ["Tom"])])
        #expect(links == [.init(range: NSRange(location: 4, length: 3), entityID: tom, kind: .person)])
        #expect(EntryNameLinks.entityID(from: EntryNameLinks.url(for: tom)) == tom)
        #expect(EntryNameLinks.entityID(from: URL(string: "https://example.com")!) == nil)
    }
}
