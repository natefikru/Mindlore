import Foundation
import Testing
@testable import Mindlore

struct TextDiffTests {
    @Test func marksOnlyTheWordsThatChanged() {
        let runs = TextDiff.runs(original: "i walked to the river", cleaned: "I walked to the river.")

        #expect(runs.original.map(\.text).joined() == "i walked to the river")
        #expect(runs.cleaned.map(\.text).joined() == "I walked to the river.")
        #expect(runs.original.filter(\.changed).map(\.text) == ["i ", "river"])
        #expect(runs.cleaned.filter(\.changed).map(\.text) == ["I ", "river."])
        #expect(runs.cleaned.first { !$0.changed }?.text == "walked to the ")
    }

    @Test func identicalTextHasNoChanges() {
        let runs = TextDiff.runs(original: "same words", cleaned: "same words")
        #expect(runs.original.allSatisfy { !$0.changed })
        #expect(TextDiff.summary(original: "same words", cleaned: "same words") == "No changes.")
    }

    @Test func summaryCountsAddedAndRemovedWords() {
        #expect(TextDiff.summary(original: "one two", cleaned: "one two three") == "1 word added, 0 words removed.")
        #expect(TextDiff.summary(original: "one two three", cleaned: "one three") == "0 words added, 1 word removed.")
    }

    @Test func handlesEmptyTextAndNewlines() {
        #expect(TextDiff.runs(original: "", cleaned: "added").cleaned.map(\.text) == ["added"])
        let paragraphs = TextDiff.runs(original: "one two", cleaned: "one\n\ntwo")
        #expect(paragraphs.cleaned.map(\.text).joined() == "one\n\ntwo")
    }
}
