import Foundation

// What Return, Backspace, and the bar's indent buttons do to a structured paragraph, the way Notes
// behaves: Return continues a list, Return on an empty item leaves it, Backspace at the start of
// an item takes the marker off before it takes a character. Pure, over the paragraph's own state,
// so the text view only has to describe the paragraph under the caret and apply the answer.
nonisolated enum ListEditing {
    struct Paragraph: Equatable, Sendable {
        var block: EntryFormatting.Block?
        var indent: Int = 0
        var isEmpty: Bool
    }

    enum Action: Equatable, Sendable {
        // Insert the newline; the new paragraph takes this block and indent.
        case newParagraph(block: EntryFormatting.Block?, indent: Int)
        // Return on an empty item: drop the block (and indent) instead of adding a line.
        case leaveList
        // Backspace at the start: take the block off, or one level of indent, and delete nothing.
        case removeBlock
        case outdent
        // Nothing special; let the text view do what it does.
        case none
    }

    static func onReturn(in paragraph: Paragraph) -> Action {
        guard let block = paragraph.block else {
            return paragraph.indent > 0 && paragraph.isEmpty ? .leaveList : .newParagraph(block: nil, indent: paragraph.indent)
        }
        if paragraph.isEmpty { return .leaveList }
        return .newParagraph(block: block.continued, indent: block.continued == nil ? 0 : paragraph.indent)
    }

    // Backspace with the caret at the very start of the paragraph.
    static func onBackspaceAtStart(in paragraph: Paragraph) -> Action {
        if paragraph.block != nil { return .removeBlock }
        if paragraph.indent > 0 { return .outdent }
        return .none
    }

    static func indented(_ paragraph: Paragraph, by delta: Int) -> Paragraph {
        var next = paragraph
        next.indent = min(max(paragraph.indent + delta, 0), EntryFormatting.maxIndent)
        return next
    }

    // The bar's block buttons toggle: the same block again makes a plain paragraph, and the
    // checklist button treats a ticked box as a checklist item too.
    static func toggled(_ block: EntryFormatting.Block, on paragraph: Paragraph) -> Paragraph {
        var next = paragraph
        let current = paragraph.block == .checked ? EntryFormatting.Block.check : paragraph.block
        next.block = current == block ? nil : block
        if next.block?.isList != true { next.indent = 0 }
        return next
    }

    // A tap on the box itself.
    static func ticked(_ paragraph: Paragraph) -> Paragraph {
        var next = paragraph
        switch paragraph.block {
        case .check: next.block = .checked
        case .checked: next.block = .check
        default: break
        }
        return next
    }
}
