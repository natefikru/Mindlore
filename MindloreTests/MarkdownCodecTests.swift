import Testing
@testable import Mindlore

struct MarkdownCodecTests {
    @Test func plainTextPassesThroughBothWays() {
        let text = "Walked to the river.\n\nIt rained later, 3 times."
        #expect(MarkdownCodec.render(text: text, formatting: .empty) == text)
        let parsed = MarkdownCodec.parse(text)
        #expect(parsed.text == text)
        #expect(parsed.formatting.isEmpty)
    }

    @Test func rendersEveryBlock() {
        let text = "Monday\nfirst\nsecond\nmilk\neggs\nbread\nA thought\nnote"
        let formatting = EntryFormatting(paragraphs: [
            .init(index: 0, block: .heading1),
            .init(index: 1, block: .number), .init(index: 2, block: .number),
            .init(index: 3, block: .check), .init(index: 4, block: .checked, indent: 1),
            .init(index: 5, block: .bullet, indent: 2),
            .init(index: 6, block: .quote),
            .init(index: 7, block: .heading2),
        ])
        let expected = "# Monday\n1. first\n2. second\n- [ ] milk\n  - [x] eggs\n    - bread\n> A thought\n## note"
        #expect(MarkdownCodec.render(text: text, formatting: formatting) == expected)
    }

    @Test func numbersRestartAfterABreak() {
        let text = "a\nb\nplain\nc"
        let formatting = EntryFormatting(paragraphs: [
            .init(index: 0, block: .number), .init(index: 1, block: .number), .init(index: 3, block: .number),
        ])
        #expect(MarkdownCodec.render(text: text, formatting: formatting) == "1. a\n2. b\nplain\n1. c")
    }

    @Test func rendersInlineMarks() {
        let text = "I felt calm about the move."
        let formatting = EntryFormatting(spans: [
            .init(location: 7, length: 4, bold: true),
            .init(location: 22, length: 4, italic: true, strike: true),
        ])
        #expect(MarkdownCodec.render(text: text, formatting: formatting) == "I felt **calm** about the *~~move~~*.")
    }

    @Test func parsesTheSameSubset() {
        let markdown = "# Monday\n1. first\n2) second\n- [ ] milk\n  - [x] eggs\n\t- bread\n> A thought\n## note\n* star bullet"
        let parsed = MarkdownCodec.parse(markdown)
        #expect(parsed.text == "Monday\nfirst\nsecond\nmilk\neggs\nbread\nA thought\nnote\nstar bullet")
        #expect(parsed.formatting.paragraphs == [
            .init(index: 0, block: .heading1),
            .init(index: 1, block: .number), .init(index: 2, block: .number),
            .init(index: 3, block: .check), .init(index: 4, block: .checked, indent: 1),
            .init(index: 5, block: .bullet, indent: 1),
            .init(index: 6, block: .quote),
            .init(index: 7, block: .heading2),
            .init(index: 8, block: .bullet),
        ])
    }

    @Test func parsesInlineMarksAndLeavesStraysAlone() {
        let parsed = MarkdownCodec.parse("I felt **calm** about the *~~move~~*.\nA lone * star and snake_case_name stay.")
        #expect(parsed.text == "I felt calm about the move.\nA lone * star and snake_case_name stay.")
        #expect(parsed.formatting.spans == [
            .init(location: 7, length: 4, bold: true),
            .init(location: 22, length: 4, italic: true, strike: true),
        ])
    }

    @Test func roundTripsAFormattedEntry() {
        let text = "Plans\ncall the landlord\nbook flights\nSo tired."
        let formatting = EntryFormatting(
            paragraphs: [.init(index: 0, block: .heading2), .init(index: 1, block: .check), .init(index: 2, block: .checked, indent: 1)],
            spans: [.init(location: 40, length: 5, bold: true)]
        )
        let markdown = MarkdownCodec.render(text: text, formatting: formatting)
        let back = MarkdownCodec.parse(markdown)
        #expect(back.text == text)
        #expect(back.formatting == formatting)
    }

    @Test func aHeadingOnlyAtTheMargin() {
        // Indented, "#" is a word the way "#2" or a hashtag is.
        let parsed = MarkdownCodec.parse("  # not a heading\n#tag at the start")
        #expect(parsed.text == "# not a heading\n#tag at the start")
        #expect(parsed.formatting.paragraphs == [.init(index: 0, indent: 1)])
    }

    @Test func illegibleMarkersAreNotCheckboxes() {
        let parsed = MarkdownCodec.parse("[illegible] then home\n- [illegible] item")
        #expect(parsed.text == "[illegible] then home\n[illegible] item")
        #expect(parsed.formatting.paragraphs == [.init(index: 1, block: .bullet)])
    }
}
