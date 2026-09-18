import Foundation
import Testing
@testable import Mindlore

struct AskAnswerParserTests {
    private let known: Set<String> = ["E1", "E2"]

    @Test func jsonCitationsAreFilteredToHandlesThisConversationHandedOut() throws {
        let answer = try AskAnswerParser.parseJSON(#"{"answer":"You walked by the river.","citations":["E1","E9","E2","E1"]}"#, known: known)

        #expect(answer.text == "You walked by the river.")
        #expect(answer.handles == ["E1", "E2"], "unknown handles are dropped and a repeat counts once")
    }

    @Test func aMalformedJSONAnswerIsAnInvalidResponse() {
        #expect(throws: AIError.invalidResponse) {
            try AskAnswerParser.parseJSON("not json at all", known: known)
        }
    }

    @Test func markersAreExtractedAndRemovedFromTheText() {
        let answer = AskAnswerParser.parseMarkers("You walked by the river [E1]. Sarah came too [E2].", known: known)

        #expect(answer.handles == ["E1", "E2"])
        #expect(answer.text == "You walked by the river. Sarah came too.")
    }

    @Test func anUnknownMarkerStaysWhereItWasWritten() {
        let answer = AskAnswerParser.parseMarkers("You walked by the river [E9], with Sarah [E1].", known: known)

        #expect(answer.handles == ["E1"])
        #expect(answer.text == "You walked by the river [E9], with Sarah.")
    }

    @Test func aSpacedMarkerIsCitedAndRemoved() {
        let answer = AskAnswerParser.parseMarkers("The kayak was in the shed [ E2 ].", known: known)

        #expect(answer.handles == ["E2"])
        #expect(answer.text == "The kayak was in the shed.")
    }

    @Test func aCitationWithStrayWhitespaceStillCounts() throws {
        let answer = try AskAnswerParser.parseJSON(#"{"answer":"Yes.","citations":[" E1 ","not a handle","E"]}"#, known: known)

        #expect(answer.handles == ["E1"])
    }

    @Test func aLowercaseMarkerIsStillTheSameHandle() {
        let answer = AskAnswerParser.parseMarkers("The kayak was in the shed [e2].", known: known)

        #expect(answer.handles == ["E2"])
        #expect(answer.text == "The kayak was in the shed.")
    }
}
