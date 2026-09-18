import Foundation
import Testing
@testable import Mindlore

struct AskRetrievalQueryTests {
    // Monday 14 September 2026, 14:00 UTC, the same `now` the other Ask suites use.
    private let now = Date(timeIntervalSince1970: 1_789_394_400)

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    private let maya = UUID()
    private let sarah = UUID()

    private var index: AskIndex {
        AskIndex.build(
            from: [
                AskIndex.DocumentInput(id: UUID(), date: now, text: "Anything at all"),
            ],
            entities: [
                AskIndex.Entity(id: maya, name: "Maya", aliases: ["Maia"], kindRaw: "person"),
                AskIndex.Entity(id: sarah, name: "Sarah Chen", kindRaw: "person"),
                AskIndex.Entity(id: UUID(), name: "Hidden", kindRaw: "person", isBrowsable: false),
            ]
        )
    }

    private func build(_ question: String, previous: [String] = [], cited: [[UUID]] = []) -> AskRetrievalQuery {
        AskRetrievalQuery.build(
            question: question,
            previousQuestions: previous,
            citedEntryIDs: cited,
            index: index,
            now: now,
            calendar: calendar
        )
    }

    private func weight(_ query: AskRetrievalQuery, _ term: String) -> Double? {
        query.terms.first { $0.text == term }?.weight
    }

    // MARK: - The complaint that started the phase

    @Test func aFollowUpThatNamesNobodyKeepsTheSubject() {
        let query = build("Why do you think that started?", previous: ["What's going on with Maya?"])
        // Today this question retrieves entries containing the word "started" and loses Maya
        // completely: every other word of it is a stop word.
        #expect(weight(query, "started") == 1)
        #expect(weight(query, "maya") == 0.5)
        #expect(query.carriedEntityIDs == [maya])
    }

    @Test func aQuestionOfNothingButStopWordsStillCarriesTheSubject() {
        let query = build("Why?", previous: ["What's going on with Maya?"])
        // Her name and the other spelling the entries use, both at the carried weight. Today this
        // question retrieves nothing at all and falls back to the five newest entries, so the model
        // is asked to explain something about Maya while reading last Tuesday's grocery run.
        #expect(query.terms.map(\.text) == ["maya", "maia"])
        #expect(weight(query, "maya") == 0.5)
        #expect(weight(query, "maia") == 0.5)
    }

    // MARK: - The decay ladder

    @Test func termsDecayOverThreeQuestionsAndThenStop() {
        let query = build("current", previous: ["older", "oldest", "ancient"])
        #expect(weight(query, "current") == 1)
        #expect(weight(query, "older") == 0.5)
        #expect(weight(query, "oldest") == 0.25)
        // carryDepth is 3 questions in total, so the fourth contributes nothing.
        #expect(weight(query, "ancient") == nil)
    }

    @Test func aRepeatedTermTakesItsHighestWeightNotTheSum() {
        let query = build("deadline", previous: ["deadline", "deadline"])
        #expect(weight(query, "deadline") == 1)
        #expect(query.terms.count == 1)
    }

    @Test func aCarriedTermPromotedByTheNewQuestionGoesToFullWeight() {
        let query = build("What about the deadline?", previous: ["deadline and the move"])
        #expect(weight(query, "deadline") == 1)
        #expect(weight(query, "move") == 0.5)
    }

    @Test func termsKeepTheOrderTheConversationRanIn() {
        let query = build("current words", previous: ["older words"])
        #expect(query.terms.map(\.text) == ["current", "words", "older"])
    }

    // MARK: - Words

    @Test func stopWordsGoAndTwoLetterWordsStay() {
        #expect(AskRetrievalQuery.terms(in: "What did I do with the AI work?") == ["ai", "work"])
        // Every word a stop word: nothing survives, which is the case the carryforward exists for.
        #expect(AskRetrievalQuery.terms(in: "Why do you think that?").isEmpty)
    }

    @Test func aTermIsAlwaysASingleTokenTheIndexCouldHold() {
        let query = build("How is Sarah Chen?")
        // A two-word name has to arrive as two terms, or an exact lookup finds nothing.
        #expect(query.terms.map(\.text).contains("sarah"))
        #expect(query.terms.map(\.text).contains("chen"))
        #expect(query.terms.contains { $0.text.contains(" ") } == false)
    }

    @Test func anEntitysOtherSpellingsComeAlongAsTerms() {
        let query = build("What's going on with Maya?")
        #expect(query.namedEntityIDs == [maya])
        // The entries may spell her "Maia", and the alias is what reaches them.
        #expect(weight(query, "maia") == 1)
    }

    @Test func aHiddenEntityIsNeverNamedOrCarried() {
        let query = build("How is Hidden doing?", previous: ["Tell me about Hidden"])
        #expect(query.namedEntityIDs.isEmpty)
        #expect(query.carriedEntityIDs.isEmpty)
    }

    // MARK: - Dates

    @Test func thisQuestionsRangeIsNamedAndNothingIsInherited() {
        let query = build("What did I do last week?")
        #expect(query.namedRange != nil)
        #expect(query.inheritedRange == nil)
    }

    @Test func aRangeCarriesExactlyOneTurn() {
        // Framed as a date, because AskDates rightly refuses a bare "March": "may" and "march" are
        // ordinary words, and AskDatesTests defends that.
        let first = build("How was it in March?")
        #expect(first.namedRange != nil)

        let second = build("What about work then?", previous: ["How was it in March?"])
        #expect(second.namedRange == nil)
        #expect(second.inheritedRange == first.namedRange)

        // The turn after that, the question it would inherit from named no range itself, so the
        // inheritance dies on its own rather than sticking to the conversation.
        let third = build("And the deadline?", previous: ["What about work then?", "How was it in March?"])
        #expect(third.inheritedRange == nil)
    }

    @Test func theCurrentQuestionsRangeBeatsAnInheritedOne() {
        let query = build("What about yesterday?", previous: ["How was it in March?"])
        #expect(query.namedRange != nil)
        #expect(query.inheritedRange == nil)
    }

    @Test func namingSomeoneDropsTheInheritedRange() {
        // "What did I do last week?" then "What about Maya?" must not be answered from last week
        // alone, or every older entry about her is thrown away before scoring.
        let query = build("What about Maya?", previous: ["What did I do last week?"])
        #expect(query.inheritedRange == nil)
        #expect(query.namedEntityIDs == [maya])
    }

    // MARK: - Continuity

    @Test func theLastTwoAnswersCitationsComeBack() {
        let a = UUID(), b = UUID(), c = UUID()
        let query = build("And why?", cited: [[a, b], [b, c], [UUID()]])
        #expect(query.continuityEntryIDs == [a, b, c])
    }

    @Test func noCitationsMeansNoContinuity() {
        #expect(build("Anything").continuityEntryIDs.isEmpty)
    }

    // MARK: - Shape

    @Test func aggregateMarkersAreRecognisedAsAHint() {
        #expect(build("How often do I run?").aggregateHint)
        #expect(build("How have I usually felt about it?").aggregateHint)
        #expect(build("Who do I mention most?").aggregateHint)
        #expect(build("What do I keep coming back to?").aggregateHint)
        #expect(build("Am I doing better than last year?").aggregateHint)
        #expect(build("What's the pattern here?").aggregateHint)
    }

    @Test func anOrdinaryQuestionIsNotAnAggregateOne() {
        #expect(build("What did I do last week?").aggregateHint == false)
        #expect(build("What's going on with Maya?").aggregateHint == false)
        #expect(build("Why?").aggregateHint == false)
    }

    // MARK: - What reaches the index

    @Test func theIndexQueryCarriesTheRangesAndNeverExpandsATerm() {
        let query = build("What about work then?", previous: ["How was it in March?"])
        let indexQuery = query.indexQuery
        #expect(indexQuery.namedRange == nil)
        #expect(indexQuery.inheritedRange == query.inheritedRange)
        #expect(indexQuery.asOf == now)
        // A sent question is finished, so only the panel expands its last word.
        #expect(indexQuery.expandsLastTerm == false)
        // The gate: Ask never searches an entry it may not send.
        #expect(indexQuery.sendableOnly)
    }

    @Test func aRebuildFromStoredMessagesMatchesTheLiveConversation() {
        // Nothing about the carryforward is persisted, so a reopened conversation has to derive the
        // same query from the question text and citations it saved.
        let cited = [[UUID()]]
        let live = build("Why do you think that started?", previous: ["What's going on with Maya?"], cited: cited)
        let reopened = build("Why do you think that started?", previous: ["What's going on with Maya?"], cited: cited)
        #expect(live == reopened)
    }
}
