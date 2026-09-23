import Foundation
import Testing
@testable import Mindlore

struct MentionDetectionTests {
    @Test func anAtSignStartsAMentionUpToTheCaret() {
        let text = "Lunch with @Sar"
        #expect(MentionDetection.mention(in: text, caret: 15) == .init(range: NSRange(location: 11, length: 4), query: "Sar"))
        #expect(MentionDetection.mention(in: text, caret: 12) == .init(range: NSRange(location: 11, length: 1), query: ""))
        // The caret before the "@" is not in a mention, and neither is one past a space.
        #expect(MentionDetection.mention(in: text, caret: 11) == nil)
        #expect(MentionDetection.mention(in: "with @Sarah and", caret: 15) == nil)
    }

    @Test func anAtSignInsideAWordIsNotAMention() {
        #expect(MentionDetection.mention(in: "mail me@work", caret: 12) == nil)
        #expect(MentionDetection.mention(in: "@start", caret: 6) == .init(range: NSRange(location: 0, length: 6), query: "start"))
        #expect(MentionDetection.mention(in: "line\n@Tom", caret: 9) == .init(range: NSRange(location: 5, length: 4), query: "Tom"))
    }

    @Test func aTagIsCompleteOnceSomethingFollowsIt() {
        #expect(MentionDetection.completedTag(in: "by the #river ", endingAt: 13) == .init(range: NSRange(location: 7, length: 6), word: "river"))
        #expect(MentionDetection.completedTag(in: "by the #river", endingAt: 13) == .init(range: NSRange(location: 7, length: 6), word: "river"))
        // Still being typed: the next character is a letter.
        #expect(MentionDetection.completedTag(in: "by the #rivers", endingAt: 13) == nil)
        #expect(MentionDetection.completedTag(in: "# alone", endingAt: 1) == nil)
        #expect(MentionDetection.completedTag(in: "#2024 was", endingAt: 5) == nil, "a number is not a tag")
        #expect(MentionDetection.completedTag(in: "C#", endingAt: 2) == nil)
        #expect(MentionDetection.completedTag(in: "a#b", endingAt: 3) == nil, "a # inside a word is not a tag")
        #expect(MentionDetection.completedTag(in: "#slow_days,", endingAt: 10) == .init(range: NSRange(location: 0, length: 10), word: "slow_days"))
    }
}
