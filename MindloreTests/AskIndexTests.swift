import Foundation
import Testing
@testable import Mindlore

struct AskIndexTests {
    // Monday 14 September 2026, 14:00 UTC. The same `now` AskDatesTests uses.
    private let now = Date(timeIntervalSince1970: 1_789_394_400)

    private func date(daysAgo days: Int) -> Date {
        now.addingTimeInterval(-Double(days) * 86_400)
    }

    private func input(
        _ name: String,
        text: String = "",
        title: String = "",
        daysAgo: Int = 0,
        entityNames: [String] = [],
        entityIDs: [UUID] = [],
        tags: [String] = [],
        areas: [String] = [],
        mood: String? = nil,
        isSendable: Bool = true,
        blockCharacters: Int = 100
    ) -> AskIndex.DocumentInput {
        AskIndex.DocumentInput(
            id: id(for: name),
            date: date(daysAgo: daysAgo),
            title: title,
            text: text,
            entityIDs: entityIDs,
            entityNames: entityNames,
            tags: tags,
            areas: areas,
            mood: mood,
            isSendable: isSendable,
            blockCharacters: blockCharacters
        )
    }

    // Stable ids from a name, so an expectation can name the entry it wants.
    private func id(for name: String) -> UUID {
        var bytes = Array(name.utf8.prefix(16))
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 16 - bytes.count))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    private func query(
        _ words: String...,
        weights: [Double] = [],
        namedRange: DateInterval? = nil,
        inheritedRange: DateInterval? = nil,
        expandsLastTerm: Bool = false,
        sendableOnly: Bool = true
    ) -> AskIndex.Query {
        AskIndex.Query(
            terms: words.enumerated().map { AskIndex.Term(text: $1, weight: weights.indices.contains($0) ? weights[$0] : 1) },
            namedRange: namedRange,
            inheritedRange: inheritedRange,
            expandsLastTerm: expandsLastTerm,
            sendableOnly: sendableOnly,
            asOf: now
        )
    }

    private func ranked(_ index: AskIndex, _ query: AskIndex.Query) -> [UUID] {
        index.search(query).map { index.documents[Int($0.document)].id }
    }

    // MARK: - Terms

    @Test func caseAndDiacriticsFoldToOneTerm() {
        let index = AskIndex.build(from: [input("a", text: "Coffee with Renée")])
        #expect(ranked(index, query("renee")) == [id(for: "a")])
        #expect(ranked(index, query("RENÉE")) == [id(for: "a")])
    }

    @Test func twoLetterTermsAreKeptAndOneLetterTermsAreNot() {
        let index = AskIndex.build(from: [input("a", text: "Shipped the AI work in NY")])
        #expect(ranked(index, query("ai")) == [id(for: "a")])
        #expect(ranked(index, query("ny")) == [id(for: "a")])
        #expect(AskIndex.tokens(in: "a b ai").contains("ai"))
        #expect(AskIndex.tokens(in: "a b ai").contains("a") == false)
    }

    @Test func aWordInTheTitleOutweighsOneInTheBody() {
        let index = AskIndex.build(from: [
            input("body", text: "A long walk and somewhere in here the word deadline appears once"),
            input("title", text: "A long walk and nothing else worth saying about it today", title: "Deadline"),
        ])
        #expect(ranked(index, query("deadline")).first == id(for: "title"))
    }

    @Test func aRareWordOutranksACommonOne() {
        var inputs = (0..<20).map { input("common\($0)", text: "Another day of work and more work") }
        inputs.append(input("rare", text: "Work, and then the ayahuasca retreat came up again"))
        let index = AskIndex.build(from: inputs)
        // Both terms are in the rare entry; only "work" is in the other twenty. The entry holding
        // the rare term has to come first, which keyword counting alone would not guarantee.
        #expect(ranked(index, query("work", "ayahuasca")).first == id(for: "rare"))
    }

    @Test func aLongEntryDoesNotWinByAccident() {
        let padding = String(repeating: "and then some more unrelated words about nothing ", count: 40)
        let index = AskIndex.build(from: [
            input("short", text: "The deadline moved."),
            input("long", text: "The deadline moved. " + padding),
        ])
        #expect(ranked(index, query("deadline")).first == id(for: "short"))
    }

    // MARK: - Body against context

    @Test func aBodyHitOutranksAContextOnlyHitAtTheSameFrequency() {
        let index = AskIndex.build(from: [
            input("linked", text: "We talked about the move for an hour", entityNames: ["Maya"]),
            input("named", text: "Maya talked about the move for an hour"),
        ])
        let results = index.search(query("maya"))
        #expect(results.count == 2)
        #expect(index.documents[Int(results[0].document)].id == id(for: "named"))
        #expect(results[0].matchedInBody)
        #expect(results[1].matchedInBody == false)
    }

    @Test func contextStillFindsAnEntryThatNeverSpellsTheName() {
        let index = AskIndex.build(from: [
            input("linked", text: "Dinner and a long argument about nothing", entityNames: ["Maya"]),
            input("other", text: "Rebuilt the fence"),
        ])
        #expect(ranked(index, query("maya")) == [id(for: "linked")])
    }

    @Test func tagsAreasMoodAndTheMonthAreAllContextTerms() {
        let index = AskIndex.build(from: [
            input("a", text: "Nothing in the words themselves", daysAgo: 1, tags: ["deadline"], areas: ["work"], mood: "tired"),
        ])
        #expect(ranked(index, query("deadline")) == [id(for: "a")])
        #expect(ranked(index, query("work")) == [id(for: "a")])
        #expect(ranked(index, query("tired")) == [id(for: "a")])
        #expect(ranked(index, query("september")) == [id(for: "a")])
        #expect(ranked(index, query("2026")) == [id(for: "a")])
    }

    @Test func anAliasFindsARenamedEntity() {
        // Entries spell the old name; the entity carries both.
        let index = AskIndex.build(from: [input("a", text: "Lewis came by", entityNames: ["Luis", "Lewis"])])
        #expect(ranked(index, query("luis")) == [id(for: "a")])
    }

    @Test func aContextHitIsNotInflatedByAShortBody() {
        let index = AskIndex.build(from: [
            input("terse", text: "Dinner.", entityNames: ["Maya"]),
            input("detailed", text: "A long evening of catching up about the move, the new job, and everything else that has happened since spring.", entityNames: ["Maya"]),
        ])
        // Both are linked to her and neither says her name. Normalizing the context stream by body
        // length made the two-word entry score far higher, which is the inverse of the point.
        let results = index.search(query("maya"))
        #expect(results.count == 2)
        #expect(abs(results[0].score - results[1].score) < results[0].score * 0.35)
    }

    @Test func aPrefixKeepsTheRarestExpansionsNotTheAlphabeticalOnes() {
        // Enough common "ma" words to exhaust the expansion budget before reaching the name.
        var inputs = (0..<80).map { index in
            input("common\(index)", text: "made mail main make man many map march mark market marathon marriage word\(index)")
        }
        inputs.append(input("maria", text: "Maria came over"))
        let index = AskIndex.build(from: inputs)
        // Truncating in sorted order spent all 64 slots on the common words and never reached her.
        #expect(ranked(index, query("mari", expandsLastTerm: true)).first == id(for: "maria"))
    }

    // MARK: - Recency

    @Test func recencyBreaksATieAndNeverHidesTheOlderEntry() {
        let index = AskIndex.build(from: [
            input("old", text: "The deadline moved", daysAgo: 720),
            input("new", text: "The deadline moved", daysAgo: 1),
        ])
        let results = index.search(query("deadline"))
        #expect(index.documents[Int(results[0].document)].id == id(for: "new"))
        #expect(results.count == 2)
        // The floor is what stops two years old meaning invisible.
        #expect(results[1].score >= results[0].score * AskIndex.recencyFloor * 0.99)
    }

    @Test func relevanceStillBeatsRecency() {
        let index = AskIndex.build(from: [
            input("relevant", text: "The deadline moved and the deadline moved again", title: "Deadline", daysAgo: 400),
            input("recent", text: "A deadline was mentioned in passing among many other words here", daysAgo: 0),
        ])
        #expect(ranked(index, query("deadline")).first == id(for: "relevant"))
    }

    // MARK: - Dates

    @Test func aNamedRangeFiltersHalfOpen() {
        let index = AskIndex.build(from: [
            input("inside", text: "Deadline", daysAgo: 5),
            input("outside", text: "Deadline", daysAgo: 40),
        ])
        let start = date(daysAgo: 6)
        let range = DateInterval(start: start, end: date(daysAgo: 4))
        #expect(ranked(index, query("deadline", namedRange: range)) == [id(for: "inside")])

        // Half-open: an entry exactly on `end` is out, one exactly on `start` is in.
        let edge = DateInterval(start: date(daysAgo: 5), end: date(daysAgo: 4))
        #expect(ranked(index, query("deadline", namedRange: edge)) == [id(for: "inside")])
        let excluded = DateInterval(start: date(daysAgo: 7), end: date(daysAgo: 5))
        #expect(ranked(index, query("deadline", namedRange: excluded)).isEmpty)
    }

    @Test func anInheritedRangeBoostsAndNeverFilters() {
        let index = AskIndex.build(from: [
            input("inside", text: "Maya and the move", daysAgo: 5),
            input("outside", text: "Maya and the move", daysAgo: 300),
        ])
        let range = DateInterval(start: date(daysAgo: 6), end: date(daysAgo: 4))
        let results = ranked(index, query("maya", inheritedRange: range))
        // Both survive. This is the case a hard filter would have broken: asking about last week
        // and then asking about Maya must not throw away every older entry about her.
        #expect(results == [id(for: "inside"), id(for: "outside")])
    }

    @Test func aNamedRangeIsAnsweredEvenWhenNoWordOfTheQuestionAppearsInIt() {
        let index = AskIndex.build(from: [
            input("inside", text: "an ordinary day", daysAgo: 5),
            input("outside", text: "an ordinary day", daysAgo: 400),
        ])
        let range = DateInterval(start: date(daysAgo: 6), end: date(daysAgo: 4))
        // "feeling" is in neither entry. The person still asked about those days, and the old tier 3
        // would have sent them, so returning nothing here would be a regression.
        #expect(ranked(index, query("feeling", namedRange: range)) == [id(for: "inside")])
    }

    @Test func aQuestionThatNamesNoTimeAndMatchesNothingStillSendsNothing() {
        let index = AskIndex.build(from: [input("a", text: "an ordinary day")])
        // The restraint the old tier 4 learned: don't quietly send five entries and bill for them.
        #expect(index.search(query("ayahuasca")).isEmpty)
    }

    @Test func anEmptyQueryRanksByRecency() {
        let index = AskIndex.build(from: [
            input("old", text: "Anything", daysAgo: 90),
            input("new", text: "Anything", daysAgo: 1),
            input("middle", text: "Anything", daysAgo: 30),
        ])
        #expect(ranked(index, AskIndex.Query(asOf: now)) == [id(for: "new"), id(for: "middle"), id(for: "old")])
    }

    // MARK: - The gate

    @Test func onlySendableDocumentsAreSearchedUnlessTheCallerSaysOtherwise() {
        let index = AskIndex.build(from: [
            input("sendable", text: "Deadline"),
            input("held", text: "Deadline", isSendable: false),
        ])
        #expect(ranked(index, query("deadline")) == [id(for: "sendable")])
        #expect(ranked(index, query("deadline", sendableOnly: false)).count == 2)
    }

    // MARK: - Prefixes, for the panel

    @Test func aPrefixMatchesWhileTheWordIsStillBeingTyped() {
        let index = AskIndex.build(from: [input("a", text: "Walked by the river")])
        #expect(ranked(index, query("riv", expandsLastTerm: true)) == [id(for: "a")])
        #expect(ranked(index, query("riv")).isEmpty)
    }

    @Test func aPrefixTakesItsBestExpansionRatherThanTheSum() {
        let index = AskIndex.build(from: [
            input("spread", text: "March at the market before the marathon and marriage talk"),
            input("maria", text: "Maria came over"),
        ])
        // Four weak expansions must not outscore one real match, or typing "mar" buries the person
        // you were looking for under every other word starting the same way.
        #expect(ranked(index, query("mar", expandsLastTerm: true)).first == id(for: "maria"))
    }

    @Test func onlyTheLastTermExpands() {
        let index = AskIndex.build(from: [input("a", text: "Walked by the river with Maria")])
        // "riv" is not the last term here, so it has to match exactly, and nothing does.
        #expect(ranked(index, query("riv", "maria", expandsLastTerm: true)) == [id(for: "a")])
        #expect(index.search(query("riv", "mari", expandsLastTerm: true)).count == 1)
    }

    // MARK: - Weights

    @Test func aCarriedTermCountsForLessThanOneJustTyped() {
        let index = AskIndex.build(from: [
            input("carried", text: "Maya again"),
            input("current", text: "It started here"),
        ])
        // "maya" carried at half weight, "started" typed at full: the new subject leads, and the
        // conversation's subject is still in the list rather than gone.
        let results = ranked(index, query("maya", "started", weights: [0.5, 1.0]))
        #expect(results == [id(for: "current"), id(for: "carried")])
    }

    // MARK: - Tags and shape

    @Test func tagCountsMatchTheWholeTagCaseInsensitively() {
        let index = AskIndex.build(from: [
            input("a", tags: ["Deadline"]),
            input("b", tags: ["deadline"]),
            input("c", tags: ["deadlines"]),
        ])
        let counts = index.tagCounts(matching: "DEADLINE")
        #expect(counts.count == 1)
        #expect(counts[0].count == 2)
        #expect(counts[0].tag == "Deadline")
        #expect(index.tagCounts(matching: "dead").isEmpty)
    }

    @Test func entitiesNamedInAQuestionAreFoundByNameOrAlias() {
        let maya = UUID()
        let index = AskIndex.build(
            from: [input("a", text: "Anything")],
            entities: [AskIndex.Entity(id: maya, name: "Maya", aliases: ["Maia"], kindRaw: "person")]
        )
        #expect(index.entities(namedIn: "What's going on with maya?").map(\.id) == [maya])
        #expect(index.entities(namedIn: "How is Maia?").map(\.id) == [maya])
        // Whole words only, the same rule the rest of the app matches names by.
        #expect(index.entities(namedIn: "Mayan history").isEmpty)
    }

    @Test func anEmptyIndexAnswersNothingWithoutCrashing() {
        #expect(AskIndex.empty.isEmpty)
        #expect(AskIndex.empty.search(query("anything")).isEmpty)
        #expect(AskIndex.build(from: []).search(AskIndex.Query(asOf: now)).isEmpty)
    }

    @Test func documentsKeepWhatThePlanNeedsAndNoText() throws {
        let index = AskIndex.build(from: [input("a", text: "Secret text", tags: ["t"], blockCharacters: 420)])
        let document = try #require(index.document(withID: id(for: "a")))
        #expect(document.blockCharacters == 420)
        #expect(document.length == 2)
        // Nothing on a Document can hand back the entry's words.
        #expect(index.termCount > 0)
        #expect(index.postingCount > 0)
    }
}
