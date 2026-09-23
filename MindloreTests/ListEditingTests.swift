import Testing
@testable import Mindlore

struct ListEditingTests {
    private func paragraph(_ block: EntryFormatting.Block?, indent: Int = 0, empty: Bool = false) -> ListEditing.Paragraph {
        .init(block: block, indent: indent, isEmpty: empty)
    }

    @Test func returnContinuesAList() {
        #expect(ListEditing.onReturn(in: paragraph(.bullet, indent: 1)) == .newParagraph(block: .bullet, indent: 1))
        #expect(ListEditing.onReturn(in: paragraph(.number)) == .newParagraph(block: .number, indent: 0))
        // A ticked box continues as an empty box, not a ticked one.
        #expect(ListEditing.onReturn(in: paragraph(.checked)) == .newParagraph(block: .check, indent: 0))
        #expect(ListEditing.onReturn(in: paragraph(.quote)) == .newParagraph(block: .quote, indent: 0))
    }

    @Test func returnOnAnEmptyItemLeavesTheList() {
        #expect(ListEditing.onReturn(in: paragraph(.bullet, indent: 2, empty: true)) == .leaveList)
        #expect(ListEditing.onReturn(in: paragraph(.check, empty: true)) == .leaveList)
        #expect(ListEditing.onReturn(in: paragraph(.quote, empty: true)) == .leaveList)
        // An indented plain paragraph with nothing in it goes back to the margin the same way.
        #expect(ListEditing.onReturn(in: paragraph(nil, indent: 1, empty: true)) == .leaveList)
    }

    @Test func returnAfterAHeadingGivesBody() {
        #expect(ListEditing.onReturn(in: paragraph(.heading1)) == .newParagraph(block: nil, indent: 0))
        #expect(ListEditing.onReturn(in: paragraph(.heading2)) == .newParagraph(block: nil, indent: 0))
        // Return on an empty heading is a heading the user didn't want.
        #expect(ListEditing.onReturn(in: paragraph(.heading1, empty: true)) == .leaveList)
        #expect(ListEditing.onReturn(in: paragraph(nil)) == .newParagraph(block: nil, indent: 0))
    }

    @Test func backspaceAtTheStartTakesTheMarkerFirst() {
        #expect(ListEditing.onBackspaceAtStart(in: paragraph(.bullet, indent: 1)) == .removeBlock)
        #expect(ListEditing.onBackspaceAtStart(in: paragraph(nil, indent: 1)) == .outdent)
        #expect(ListEditing.onBackspaceAtStart(in: paragraph(nil)) == .none)
    }

    @Test func indentIsClamped() {
        #expect(ListEditing.indented(paragraph(.bullet, indent: 3), by: 1).indent == 3)
        #expect(ListEditing.indented(paragraph(.bullet), by: -1).indent == 0)
        #expect(ListEditing.indented(paragraph(.bullet, indent: 1), by: 1).indent == 2)
    }

    @Test func barButtonsToggle() {
        #expect(ListEditing.toggled(.bullet, on: paragraph(.bullet, indent: 2)) == paragraph(nil))
        #expect(ListEditing.toggled(.number, on: paragraph(.bullet, indent: 2)) == paragraph(.number, indent: 2))
        #expect(ListEditing.toggled(.check, on: paragraph(.checked)) == paragraph(nil))
        // A heading has no indent, so switching a list item to one drops it.
        #expect(ListEditing.toggled(.heading2, on: paragraph(.bullet, indent: 1)) == paragraph(.heading2))
        #expect(ListEditing.toggled(.heading1, on: paragraph(.heading1)) == paragraph(nil))
    }

    @Test func tickingABox() {
        #expect(ListEditing.ticked(paragraph(.check)).block == .checked)
        #expect(ListEditing.ticked(paragraph(.checked)).block == .check)
        #expect(ListEditing.ticked(paragraph(.bullet)).block == .bullet)
    }
}
