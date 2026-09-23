import Foundation
import Testing
@testable import Mindlore

struct EntryFormattingTests {
    @Test func emptyFormattingStoresNothing() {
        #expect(EntryFormatting.empty.raw == nil)
        #expect(EntryFormatting(raw: nil) == nil)
        #expect(EntryFormatting(raw: "not json") == nil)
        // A paragraph with no block and no indent is nothing to store either.
        #expect(EntryFormatting(paragraphs: [.init(index: 2)]).isEmpty)
        #expect(EntryFormatting(spans: [.init(location: 0, length: 3)]).isEmpty)
    }

    @Test func roundTripsThroughJSON() throws {
        let formatting = EntryFormatting(
            paragraphs: [.init(index: 3, block: .bullet, indent: 1), .init(index: 0, block: .heading1)],
            spans: [.init(location: 10, length: 4, italic: true), .init(location: 2, length: 3, bold: true)]
        )
        let raw = try #require(formatting.raw)
        let back = try #require(EntryFormatting(raw: raw))
        #expect(back == formatting)
        // Sorted on the way in, so equality doesn't depend on the order a caller listed them.
        #expect(back.paragraphs.map(\.index) == [0, 3])
        #expect(back.spans.map(\.location) == [2, 10])
    }

    @Test func setParagraphReplacesAndPrunes() {
        var formatting = EntryFormatting(paragraphs: [.init(index: 1, block: .quote)])
        formatting.setParagraph(.init(index: 1, block: .number, indent: 2))
        #expect(formatting.paragraph(at: 1) == .init(index: 1, block: .number, indent: 2))
        formatting.setParagraph(.init(index: 1))
        #expect(formatting.isEmpty)
        #expect(formatting.paragraph(at: 7) == .init(index: 7))
    }

    @Test func returnContinuesWhatItShould() {
        #expect(EntryFormatting.Block.bullet.continued == .bullet)
        #expect(EntryFormatting.Block.checked.continued == .check)
        #expect(EntryFormatting.Block.quote.continued == .quote)
        #expect(EntryFormatting.Block.heading1.continued == nil)
        #expect(EntryFormatting.Block.heading2.continued == nil)
    }

    @MainActor
    @Test func entryAccessorWritesTheRawColumn() {
        let entry = Entry(text: "a\nb")
        #expect(entry.formatting.isEmpty)
        entry.formatting = EntryFormatting(paragraphs: [.init(index: 1, block: .check)])
        #expect(entry.formattingRaw != nil)
        #expect(entry.formatting.paragraph(at: 1).block == .check)
        entry.formatting = .empty
        #expect(entry.formattingRaw == nil)
    }
}
