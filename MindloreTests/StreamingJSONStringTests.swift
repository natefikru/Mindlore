import Foundation
import Testing
@testable import Mindlore

struct StreamingJSONStringTests {
    private func answer(_ json: String) -> String? {
        StreamingJSONString.value(of: "answer", in: json)
    }

    @Test func aFinishedObjectReadsLikeAnyOtherJSON() {
        #expect(answer(#"{"answer":"Hello","citations":["E1"]}"#) == "Hello")
    }

    @Test func aHalfWrittenStringIsWhatHasArrived() {
        #expect(answer(#"{"answer":"Hel"#) == "Hel")
    }

    @Test func aFieldThatHasNotStartedIsNothingYet() {
        #expect(answer(#"{"ans"#) == nil)
        #expect(answer(#"{"answer""#) == nil)
        #expect(answer(#"{"answer":"#) == nil)
        #expect(answer(#"{"answer": "#) == nil)
    }

    @Test func anEmptyValueIsEmptyRatherThanMissing() {
        #expect(answer(#"{"answer":""#) == "")
    }

    @Test func whitespaceAroundTheColonIsAllowed() {
        #expect(answer("{\"answer\" : \"ok\"}") == "ok")
    }

    @Test func escapesAreDecoded() {
        #expect(answer(#"{"answer":"a\nb\tc\\d\"e\/f"}"#) == "a\nb\tc\\d\"e/f")
    }

    @Test func aQuoteInsideTheAnswerDoesNotEndIt() {
        #expect(answer(#"{"answer":"she said \"go\" twice","citations":[]}"#) == #"she said "go" twice"#)
    }

    // The field is the first key, and this is the text of it: a naive search for the next
    // `","citations":` would cut the answer in half here.
    @Test func textThatLooksLikeTheEndOfTheFieldIsJustText() {
        let json = #"{"answer":"I wrote \"},\"citations\":[\"E9\"]\" in my journal","citations":["E1"]}"#
        #expect(answer(json) == #"I wrote "},"citations":["E9"]" in my journal"#)
    }

    // The whole point of re-scanning: every prefix of a real answer reads as a prefix of the text.
    @Test func everyPrefixOfAStreamIsAPrefixOfTheAnswer() throws {
        let json = #"{"answer":"Café at 7, then a run 🏃 and \"rest\".","citations":["E3"]}"#
        let whole = try #require(answer(json))
        var last = ""
        for length in 1...json.count {
            guard let soFar = answer(String(json.prefix(length))) else { continue }
            #expect(whole.hasPrefix(soFar), "\(soFar) is not a prefix of the answer")
            #expect(soFar.count >= last.count, "the answer went backwards at \(length)")
            last = soFar
        }
        #expect(last == whole)
    }

    @Test func aTrailingBackslashWaitsForWhatFollowsIt() {
        #expect(answer(#"{"answer":"line\"#) == "line")
        #expect(answer(#"{"answer":"line\n"#) == "line\n")
    }

    @Test func aUnicodeEscapeSplitAcrossFramesIsNeverHalfDecoded() {
        #expect(answer(#"{"answer":"caf\u00"#) == "caf")
        #expect(answer(#"{"answer":"caf\u00e"#) == "caf")
        #expect(answer(#"{"answer":"café"#) == "caf\u{00E9}")
    }

    @Test func aSurrogatePairWaitsForItsSecondHalf() {
        #expect(answer(#"{"answer":"run \ud83c"#) == "run ")
        #expect(answer(#"{"answer":"run \ud83c\udfc"#) == "run ")
        #expect(answer(#"{"answer":"run 🏃"#) == "run \u{1F3C3}")
    }

    @Test func anotherFieldIsReadableToo() {
        #expect(StreamingJSONString.value(of: "citations", in: #"{"answer":"a","citations":["E1"]}"#) == nil)
        #expect(StreamingJSONString.value(of: "text", in: #"{"text":"ok"}"#) == "ok")
    }

    // A key that only looks like one: this is the value of "note", not the answer field.
    @Test func theFieldIsOnlyReadWhereAKeyCanBe() {
        #expect(answer(#"{"note":"\"answer\":\"decoy\"","answer":"real"}"#) == "real")
    }
}
