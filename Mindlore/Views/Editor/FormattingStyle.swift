import UIKit

// EntryFormatting as UIKit attributes, both ways. The text view's storage is the truth while the
// user types: a block and an inline mask ride on every character as custom attributes, so Return
// carries a list item into the next paragraph the way UITextView carries typing attributes, and
// `formatting(of:)` reads them back to store. Markers (bullets, numbers, boxes) are NSTextLists
// on the paragraph style, drawn by TextKit 2 in the gutter, never characters in the string, so an
// offset in the view is an offset in `Entry.text`. Consecutive numbered items share one NSTextList
// object, which is how TextKit counts them 1, 2, 3.
@MainActor
enum FormattingStyle {
    static let blockKey = NSAttributedString.Key("MindloreBlock")
    static let indentKey = NSAttributedString.Key("MindloreIndent")
    static let inlineKey = NSAttributedString.Key("MindloreInline")

    struct Inline: OptionSet, Sendable {
        let rawValue: Int
        static let bold = Inline(rawValue: 1)
        static let italic = Inline(rawValue: 2)
        static let strike = Inline(rawValue: 4)
    }

    static let indentStep: CGFloat = 22
    static let markerGap: CGFloat = 26
    static let quoteInset: CGFloat = 18
    static let lineSpacing: CGFloat = 4

    struct Palette {
        var ink: UIColor
        var quote: UIColor
        var marker: UIColor
    }

    // MARK: Fonts

    struct Fonts {
        let body: UIFont
        let heading1: UIFont
        let heading2: UIFont
        let design: UIFontDescriptor.SystemDesign

        init(journalFont: JournalFont) {
            design = journalFont.uiDesign
            body = .journal(.body, design: design)
            heading1 = Fonts.weighted(.journal(.title2, design: design), .semibold)
            heading2 = Fonts.weighted(.journal(.title3, design: design), .semibold)
        }

        func base(for block: EntryFormatting.Block?) -> UIFont {
            switch block {
            case .heading1: heading1
            case .heading2: heading2
            default: body
            }
        }

        func font(for block: EntryFormatting.Block?, inline: Inline) -> UIFont {
            var traits: UIFontDescriptor.SymbolicTraits = []
            if inline.contains(.bold) { traits.insert(.traitBold) }
            if inline.contains(.italic) { traits.insert(.traitItalic) }
            let base = base(for: block)
            guard !traits.isEmpty, let descriptor = base.fontDescriptor.withSymbolicTraits(base.fontDescriptor.symbolicTraits.union(traits)) else { return base }
            return UIFont(descriptor: descriptor, size: 0)
        }

        private static func weighted(_ font: UIFont, _ weight: UIFont.Weight) -> UIFont {
            let descriptor = font.fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
            return UIFont(descriptor: descriptor, size: 0)
        }
    }

    // MARK: Building

    static func attributedString(text: String, formatting: EntryFormatting, fonts: Fonts, palette: Palette) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [.font: fonts.body, .foregroundColor: palette.ink])
        applyInline(formatting.spans, to: result, fonts: fonts)
        applyParagraphs(formatting, to: result, fonts: fonts, palette: palette)
        return result
    }

    private static func applyInline(_ spans: [EntryFormatting.Span], to storage: NSMutableAttributedString, fonts: Fonts) {
        let length = storage.length
        for span in spans where span.location >= 0 && span.location + span.length <= length {
            var inline: Inline = []
            if span.bold { inline.insert(.bold) }
            if span.italic { inline.insert(.italic) }
            if span.strike { inline.insert(.strike) }
            let range = NSRange(location: span.location, length: span.length)
            storage.addAttribute(inlineKey, value: inline.rawValue, range: range)
            if span.strike { storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
        }
    }

    // Sets every paragraph's block, indent, paragraph style, and font (the font carries the
    // paragraph's base and the character's inline traits). Safe to call on a text view's storage
    // mid-edit: attributes only, never characters, so the selection stays where it is.
    static func applyParagraphs(_ formatting: EntryFormatting, to storage: NSMutableAttributedString, fonts: Fonts, palette: Palette) {
        let string = storage.string as NSString
        var numberList: (indent: Int, list: NSTextList)?
        var location = 0
        var index = 0
        storage.beginEditing()
        while location <= string.length {
            let end = string.range(of: "\n", options: [], range: NSRange(location: location, length: string.length - location)).location
            let paragraphEnd = end == NSNotFound ? string.length : end
            let range = NSRange(location: location, length: paragraphEnd - location)
            let paragraph = formatting.paragraph(at: index)
            if paragraph.block == .number {
                if let current = numberList, current.indent == paragraph.indent {
                    // Same run: keep the list so the numbering continues.
                } else {
                    numberList = (paragraph.indent, NSTextList(markerFormat: .init(rawValue: "{decimal}."), options: 0))
                }
            } else {
                numberList = nil
            }
            // The newline belongs to the paragraph: the style must cover it, or Return at the end
            // of a list item starts a plain paragraph.
            let withNewline = NSRange(location: location, length: min(range.length + 1, string.length - location))
            style(withNewline, paragraph: paragraph, list: numberList?.list, in: storage, fonts: fonts, palette: palette)
            index += 1
            if end == NSNotFound { break }
            location = end + 1
        }
        storage.endEditing()
    }

    static func style(_ range: NSRange, paragraph: EntryFormatting.Paragraph, list: NSTextList?, in storage: NSMutableAttributedString, fonts: Fonts, palette: Palette) {
        let attributes = paragraphAttributes(paragraph, list: list, palette: palette)
        if range.length == 0 {
            return
        }
        storage.addAttributes(attributes, range: range)
        if paragraph.block == nil {
            storage.removeAttribute(blockKey, range: range)
        }
        if paragraph.indent == 0 {
            storage.removeAttribute(indentKey, range: range)
        }
        storage.enumerateAttribute(inlineKey, in: range) { value, subrange, _ in
            let inline = Inline(rawValue: value as? Int ?? 0)
            storage.addAttribute(.font, value: fonts.font(for: paragraph.block, inline: inline), range: subrange)
        }
    }

    // The attributes a paragraph's characters (and its typing attributes) carry for its block.
    static func paragraphAttributes(_ paragraph: EntryFormatting.Paragraph, list: NSTextList?, palette: Palette) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [.paragraphStyle: paragraphStyle(paragraph, list: list), .foregroundColor: paragraph.block == .quote ? palette.quote : palette.ink]
        if let block = paragraph.block { attributes[blockKey] = block.rawValue }
        if paragraph.indent > 0 { attributes[indentKey] = paragraph.indent }
        return attributes
    }

    static func paragraphStyle(_ paragraph: EntryFormatting.Paragraph, list: NSTextList?) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        let indent = CGFloat(paragraph.indent) * indentStep
        switch paragraph.block {
        case .bullet, .number, .check, .checked:
            let marker: NSTextList
            switch paragraph.block {
            case .number: marker = list ?? NSTextList(markerFormat: .init(rawValue: "{decimal}."), options: 0)
            case .check: marker = NSTextList(markerFormat: .init(rawValue: "\u{2610}"), options: 0)
            case .checked: marker = NSTextList(markerFormat: .init(rawValue: "\u{2611}"), options: 0)
            default: marker = NSTextList(markerFormat: .disc, options: 0)
            }
            style.textLists = [marker]
            style.firstLineHeadIndent = indent
            style.headIndent = indent + markerGap
        case .quote:
            style.textLists = [NSTextList(markerFormat: .init(rawValue: "\u{258E}"), options: 0)]
            style.firstLineHeadIndent = 0
            style.headIndent = quoteInset
        case .heading1, .heading2:
            style.paragraphSpacingBefore = 10
            style.paragraphSpacing = 2
        case nil:
            style.firstLineHeadIndent = indent
            style.headIndent = indent
        }
        return style
    }

    // MARK: Reading back

    static func formatting(of storage: NSAttributedString) -> EntryFormatting {
        let string = storage.string as NSString
        var paragraphs: [EntryFormatting.Paragraph] = []
        var location = 0
        var index = 0
        while location <= string.length {
            let end = string.range(of: "\n", options: [], range: NSRange(location: location, length: string.length - location)).location
            let paragraphEnd = end == NSNotFound ? string.length : end
            // The paragraph's characters and its newline.
            let withNewline = NSRange(location: location, length: min(paragraphEnd - location + 1, string.length - location))
            let (block, indent) = blockAndIndent(in: withNewline, of: storage)
            if block != nil || indent > 0 {
                paragraphs.append(.init(index: index, block: block, indent: indent))
            }
            index += 1
            if end == NSNotFound { break }
            location = end + 1
        }
        var spans: [EntryFormatting.Span] = []
        storage.enumerateAttribute(inlineKey, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            let inline = Inline(rawValue: value as? Int ?? 0)
            guard !inline.isEmpty else { return }
            spans.append(.init(location: range.location, length: range.length, bold: inline.contains(.bold), italic: inline.contains(.italic), strike: inline.contains(.strike)))
        }
        return EntryFormatting(paragraphs: paragraphs, spans: spans)
    }

    // The block and indent a paragraph carries, from whichever of its characters still has the
    // key: typed characters arrive without it (typing attributes drop custom keys), so the first
    // character is not enough once the user has typed at the start of a line.
    static func blockAndIndent(in range: NSRange, of storage: NSAttributedString) -> (EntryFormatting.Block?, Int) {
        var block: EntryFormatting.Block?
        var indent = 0
        guard range.length > 0, NSMaxRange(range) <= storage.length else { return (nil, 0) }
        storage.enumerateAttributes(in: range) { attributes, _, stop in
            if block == nil, let raw = attributes[blockKey] as? String, let found = EntryFormatting.Block(rawValue: raw) {
                block = found
            }
            if indent == 0, let found = attributes[indentKey] as? Int {
                indent = found
            }
            if block != nil && indent > 0 { stop.pointee = true }
        }
        return (block, min(indent, EntryFormatting.maxIndent))
    }

    // Writes a paragraph's block and indent keys across a range (attributes only).
    static func setBlock(_ block: EntryFormatting.Block?, indent: Int, in range: NSRange, of storage: NSMutableAttributedString) {
        guard range.length > 0, NSMaxRange(range) <= storage.length else { return }
        storage.beginEditing()
        if let block {
            storage.addAttribute(blockKey, value: block.rawValue, range: range)
        } else {
            storage.removeAttribute(blockKey, range: range)
        }
        if indent > 0 {
            storage.addAttribute(indentKey, value: indent, range: range)
        } else {
            storage.removeAttribute(indentKey, range: range)
        }
        storage.endEditing()
    }

    static func inline(at location: Int, in storage: NSAttributedString) -> Inline {
        guard storage.length > 0 else { return [] }
        let probe = max(0, min(location, storage.length) - 1)
        return Inline(rawValue: storage.attributes(at: probe, effectiveRange: nil)[inlineKey] as? Int ?? 0)
    }

    // Toggles one inline mark over a range: on if any part lacks it, off if the whole range has it.
    static func toggle(_ mark: Inline, in range: NSRange, of storage: NSMutableAttributedString, fonts: Fonts) {
        var everyPart = true
        storage.enumerateAttribute(inlineKey, in: range) { value, _, _ in
            if !Inline(rawValue: value as? Int ?? 0).contains(mark) { everyPart = false }
        }
        storage.beginEditing()
        storage.enumerateAttributes(in: range) { attributes, subrange, _ in
            var inline = Inline(rawValue: attributes[inlineKey] as? Int ?? 0)
            if everyPart { inline.remove(mark) } else { inline.insert(mark) }
            setInline(inline, in: subrange, of: storage, fonts: fonts, block: (attributes[blockKey] as? String).flatMap(EntryFormatting.Block.init(rawValue:)))
        }
        storage.endEditing()
    }

    static func setInline(_ inline: Inline, in range: NSRange, of storage: NSMutableAttributedString, fonts: Fonts, block: EntryFormatting.Block?) {
        if inline.isEmpty {
            storage.removeAttribute(inlineKey, range: range)
        } else {
            storage.addAttribute(inlineKey, value: inline.rawValue, range: range)
        }
        if inline.contains(.strike) {
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        } else {
            storage.removeAttribute(.strikethroughStyle, range: range)
        }
        storage.addAttribute(.font, value: fonts.font(for: block, inline: inline), range: range)
    }

    // The typing attributes for a caret, given what surrounds it, so typed text takes the
    // paragraph's block and the toggled inline marks.
    static func typingAttributes(paragraph: EntryFormatting.Paragraph, inline: Inline, list: NSTextList?, fonts: Fonts, palette: Palette) -> [NSAttributedString.Key: Any] {
        var attributes = paragraphAttributes(paragraph, list: list, palette: palette)
        attributes[.font] = fonts.font(for: paragraph.block, inline: inline)
        if inline.isEmpty {
            attributes[inlineKey] = nil
        } else {
            attributes[inlineKey] = inline.rawValue
        }
        if inline.contains(.strike) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        return attributes
    }

    // MARK: Paragraph geometry

    static func paragraphIndex(at location: Int, in string: NSString) -> Int {
        var count = 0
        var cursor = 0
        while cursor < min(location, string.length) {
            let next = string.range(of: "\n", options: [], range: NSRange(location: cursor, length: string.length - cursor)).location
            if next == NSNotFound || next >= location { break }
            count += 1
            cursor = next + 1
        }
        return count
    }

    // The paragraph's characters, without its newline.
    static func paragraphRange(at location: Int, in string: NSString) -> NSRange {
        let clamped = max(0, min(location, string.length))
        var start = clamped
        while start > 0, string.character(at: start - 1) != 10 { start -= 1 }
        var end = clamped
        while end < string.length, string.character(at: end) != 10 { end += 1 }
        return NSRange(location: start, length: end - start)
    }

    // The range of the paragraph at `index`, without its newline; nil past the end.
    static func range(ofParagraph index: Int, in string: NSString) -> NSRange? {
        var cursor = 0
        var current = 0
        while current < index {
            let next = string.range(of: "\n", options: [], range: NSRange(location: cursor, length: string.length - cursor)).location
            guard next != NSNotFound else { return nil }
            cursor = next + 1
            current += 1
        }
        return paragraphRange(at: cursor, in: string)
    }
}
