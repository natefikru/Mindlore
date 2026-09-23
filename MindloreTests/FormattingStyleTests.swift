import Testing
import UIKit
@testable import Mindlore

// The attribute codec under the editor: formatting in, the same formatting out, markers as text
// lists rather than characters, and numbered runs sharing one list so TextKit counts them.
@MainActor
struct FormattingStyleTests {
    private let fonts = FormattingStyle.Fonts(journalFont: .serif)
    private let palette = FormattingStyle.Palette(ink: .black, quote: .darkGray, marker: .gray)

    private func styled(_ text: String, _ formatting: EntryFormatting) -> NSMutableAttributedString {
        NSMutableAttributedString(attributedString: FormattingStyle.attributedString(text: text, formatting: formatting, fonts: fonts, palette: palette))
    }

    @Test func roundTripsFormattingThroughAttributes() {
        let text = "Monday\nfirst\nsecond\nmilk\neggs\nA thought\nplain and bold"
        let formatting = EntryFormatting(
            paragraphs: [
                .init(index: 0, block: .heading1), .init(index: 1, block: .number), .init(index: 2, block: .number),
                .init(index: 3, block: .check, indent: 1), .init(index: 4, block: .checked, indent: 2), .init(index: 5, block: .quote),
            ],
            spans: [.init(location: 49, length: 4, bold: true), .init(location: 43, length: 5, italic: true, strike: true)]
        )
        let storage = styled(text, formatting)
        #expect(storage.string == text, "markers are never characters")
        #expect(FormattingStyle.formatting(of: storage) == formatting)
    }

    @Test func numberedRunsShareOneListAndBreakOnAGap() throws {
        let text = "a\nb\nplain\nc\nd"
        let formatting = EntryFormatting(paragraphs: [
            .init(index: 0, block: .number), .init(index: 1, block: .number), .init(index: 3, block: .number), .init(index: 4, block: .number, indent: 1),
        ])
        let storage = styled(text, formatting)
        func list(atParagraph index: Int) -> NSTextList? {
            let range = try! #require(FormattingStyle.range(ofParagraph: index, in: storage.string as NSString))
            return (storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)?.textLists.first
        }
        let a = try #require(list(atParagraph: 0)), b = try #require(list(atParagraph: 1))
        #expect(a === b)
        #expect(list(atParagraph: 2) == nil)
        let c = try #require(list(atParagraph: 3))
        #expect(c !== a, "a plain paragraph between them starts the count again")
        #expect(list(atParagraph: 4) !== c, "a different indent is its own list")
        #expect(a.marker(forItemNumber: 2) == "2.")
    }

    @Test func markersAndIndentsSitInTheGutter() throws {
        let storage = styled("item\nquote", EntryFormatting(paragraphs: [.init(index: 0, block: .bullet, indent: 2), .init(index: 1, block: .quote)]))
        let bullet = try #require(storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(bullet.firstLineHeadIndent == 2 * FormattingStyle.indentStep)
        #expect(bullet.headIndent == 2 * FormattingStyle.indentStep + FormattingStyle.markerGap)
        #expect(bullet.textLists.first?.markerFormat == .disc)
        let quote = try #require(storage.attribute(.paragraphStyle, at: 5, effectiveRange: nil) as? NSParagraphStyle)
        #expect(quote.headIndent == FormattingStyle.quoteInset)
        #expect(storage.attribute(.foregroundColor, at: 5, effectiveRange: nil) as? UIColor == palette.quote)
    }

    @Test func headingsAndInlineMarksChangeTheFont() {
        let storage = styled("Head\nbody", EntryFormatting(paragraphs: [.init(index: 0, block: .heading1)], spans: [.init(location: 5, length: 4, bold: true, italic: true)]))
        let heading = storage.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        let body = storage.attribute(.font, at: 5, effectiveRange: nil) as? UIFont
        #expect((heading?.pointSize ?? 0) > (body?.pointSize ?? 0))
        #expect(body?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
        #expect(body?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true)
        #expect(storage.attribute(.strikethroughStyle, at: 5, effectiveRange: nil) == nil)
    }

    @Test func toggleTurnsOnWhenAnyPartLacksItAndOffWhenAllHaveIt() {
        let storage = styled("one two", EntryFormatting(spans: [.init(location: 0, length: 3, bold: true)]))
        FormattingStyle.toggle(.bold, in: NSRange(location: 0, length: 7), of: storage, fonts: fonts)
        #expect(FormattingStyle.formatting(of: storage).spans == [.init(location: 0, length: 7, bold: true)])
        FormattingStyle.toggle(.bold, in: NSRange(location: 0, length: 7), of: storage, fonts: fonts)
        #expect(FormattingStyle.formatting(of: storage).spans.isEmpty)
        FormattingStyle.toggle(.strike, in: NSRange(location: 4, length: 3), of: storage, fonts: fonts)
        #expect(storage.attribute(.strikethroughStyle, at: 4, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)
    }

    @Test func aParagraphIsReadFromWhicheverCharacterStillCarriesTheKey() {
        let storage = styled("ab\ncd", EntryFormatting(paragraphs: [.init(index: 1, block: .bullet, indent: 1)]))
        // Typed characters arrive without the key, as UIKit's typing attributes drop custom ones.
        storage.removeAttribute(FormattingStyle.blockKey, range: NSRange(location: 3, length: 1))
        storage.removeAttribute(FormattingStyle.indentKey, range: NSRange(location: 3, length: 1))
        let (block, indent) = FormattingStyle.blockAndIndent(in: NSRange(location: 3, length: 2), of: storage)
        #expect(block == .bullet)
        #expect(indent == 1)
        #expect(FormattingStyle.formatting(of: storage).paragraphs == [.init(index: 1, block: .bullet, indent: 1)])
        FormattingStyle.setBlock(nil, indent: 0, in: NSRange(location: 3, length: 2), of: storage)
        #expect(FormattingStyle.formatting(of: storage).isEmpty)
    }

    @Test func paragraphGeometry() {
        let string = "ab\n\ncd" as NSString
        #expect(FormattingStyle.paragraphIndex(at: 0, in: string) == 0)
        #expect(FormattingStyle.paragraphIndex(at: 3, in: string) == 1)
        #expect(FormattingStyle.paragraphIndex(at: 6, in: string) == 2)
        #expect(FormattingStyle.paragraphRange(at: 1, in: string) == NSRange(location: 0, length: 2))
        #expect(FormattingStyle.paragraphRange(at: 3, in: string) == NSRange(location: 3, length: 0))
        #expect(FormattingStyle.range(ofParagraph: 2, in: string) == NSRange(location: 4, length: 2))
        #expect(FormattingStyle.range(ofParagraph: 3, in: string) == nil)
    }

    @Test func aFontChangeKeepsTheFormatting() {
        let formatting = EntryFormatting(paragraphs: [.init(index: 0, block: .heading2)], spans: [.init(location: 0, length: 2, italic: true)])
        let storage = styled("Hi there", formatting)
        let mono = FormattingStyle.Fonts(journalFont: .monospaced)
        FormattingStyle.applyParagraphs(FormattingStyle.formatting(of: storage), to: storage, fonts: mono, palette: palette)
        #expect(FormattingStyle.formatting(of: storage) == formatting)
        let font = storage.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        #expect(font?.fontName == mono.font(for: .heading2, inline: .italic).fontName)
        #expect(font?.fontName != fonts.font(for: .heading2, inline: .italic).fontName)
        #expect(font?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true)
    }
}
