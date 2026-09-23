import UIKit

// Where a tap on an entry being read puts the caret once the editor opens. The read text is a
// SwiftUI `Text`, which can't say which character sits under a point, so the same words are laid
// out again with TextKit at the read text's width, font, and line spacing, and asked instead.
// Offsets are UTF-16, the unit a UITextView's selection counts in.
nonisolated enum ReadTapCaret {
    static func offset(at point: CGPoint, in text: String, width: CGFloat, font: UIFont, lineSpacing: CGFloat) -> Int {
        let length = text.utf16.count
        guard length > 0, width > 0 else { return length }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        let storage = NSTextStorage(string: text, attributes: [.font: font, .paragraphStyle: paragraph])
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)

        // Below the last line, the tap means "carry on writing".
        if point.y >= layout.usedRect(for: container).maxY { return length }
        var fraction: CGFloat = 0
        let glyph = layout.glyphIndex(for: point, in: container, fractionOfDistanceThroughGlyph: &fraction)
        let characters = layout.characterRange(forGlyphRange: NSRange(location: glyph, length: 1), actualGlyphRange: nil)
        // Past the middle of a character goes after it, except a line's own newline: a tap beyond
        // the end of a line belongs at the end of that line, not the start of the next.
        let isNewline = (text as NSString).substring(with: characters) == "\n"
        let index = fraction > 0.5 && !isNewline ? NSMaxRange(characters) : characters.location
        return min(index, length)
    }
}
