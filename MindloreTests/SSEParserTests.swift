import Foundation
import Testing
@testable import Mindlore

struct SSEParserTests {
    private func events(_ chunks: [String], finish: Bool = true) -> [SSEParser.Event] {
        var parser = SSEParser()
        var events: [SSEParser.Event] = []
        for chunk in chunks { events += parser.consume(Data(chunk.utf8)) }
        if finish { events += parser.finish() }
        return events
    }

    @Test func oneFramePerBlankLine() {
        #expect(events(["data: a\n\ndata: b\n\n"]) == [.payload("a"), .payload("b")])
    }

    @Test func aFrameSplitAcrossChunksArrivesOnce() {
        #expect(events(["data: hel", "lo the", "re\n\n"]) == [.payload("hello there")])
    }

    @Test func aFrameSplitInsideItsFieldNameStillParses() {
        #expect(events(["da", "ta: x\n", "\n"]) == [.payload("x")])
    }

    @Test func multiByteCharacterSplitAcrossChunksIsDecodedOnce() {
        let bytes = Array("data: caf\u{00E9}\n\n".utf8)
        var parser = SSEParser()
        var events: [SSEParser.Event] = []
        // The split lands between the two bytes of é.
        let cut = bytes.count - 4
        events += parser.consume(Data(bytes[..<cut]))
        events += parser.consume(Data(bytes[cut...]))
        #expect(events == [.payload("caf\u{00E9}")])
    }

    @Test func carriageReturnsAreNotPartOfThePayload() {
        #expect(events(["data: a\r\n\r\n"]) == [.payload("a")])
    }

    @Test func severalDataLinesInOneFrameJoinWithNewlines() {
        #expect(events(["data: one\ndata: two\n\n"]) == [.payload("one\ntwo")])
    }

    @Test func commentsAndKeepAlivesAreIgnored() {
        #expect(events([": keep-alive\n\ndata: a\n\n"]) == [.payload("a")])
    }

    @Test func otherFieldsAreIgnored() {
        #expect(events(["event: message\nid: 7\ndata: a\n\n"]) == [.payload("a")])
    }

    @Test func doneIsItsOwnEvent() {
        #expect(events(["data: a\n\ndata: [DONE]\n\n"]) == [.payload("a"), .done])
    }

    @Test func aStreamEndingWithoutItsBlankLineStillYieldsTheLastFrame() {
        #expect(events(["data: a\n\ndata: b"]) == [.payload("a"), .payload("b")])
    }

    @Test func nothingIsEmittedUntilTheFrameCloses() {
        var parser = SSEParser()
        #expect(parser.consume(Data("data: a\n".utf8)).isEmpty)
        #expect(parser.consume(Data("\n".utf8)) == [.payload("a")])
    }

    @Test func aValueWithNoLeadingSpaceKeepsEveryCharacter() {
        #expect(events(["data:{\"a\":1}\n\n"]) == [.payload("{\"a\":1}")])
    }

    @Test func aPayloadContainingColonsIsNotCutAtTheFirstOne() {
        #expect(events([#"data: {"answer":"12:30"}"# + "\n\n"]) == [.payload(#"{"answer":"12:30"}"#)])
    }
}
