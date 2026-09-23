import SwiftUI
import Testing
import UIKit
@testable import Mindlore

// The text view's own behaviour under the editor's rules: what typing after Return inherits, and
// that formatting never moves the caret.
@MainActor
struct GrowingTextEditorTests {
    private final class Holder {
        var text: String
        var formatting: EntryFormatting
        init(_ text: String, _ formatting: EntryFormatting) { self.text = text; self.formatting = formatting }
    }

    private func make(_ text: String, _ formatting: EntryFormatting = .empty) -> (UITextView, GrowingTextEditor.Coordinator) {
        let (view, coordinator, _) = makeReporting(text, formatting)
        return (view, coordinator)
    }

    // Also hands back what the editor reported through its bindings.
    private func makeReporting(_ text: String, _ formatting: EntryFormatting = .empty) -> (UITextView, GrowingTextEditor.Coordinator, Holder) {
        let holder = Holder(text, formatting)
        let editor = GrowingTextEditor(
            text: Binding(get: { holder.text }, set: { holder.text = $0 }),
            formatting: Binding(get: { holder.formatting }, set: { holder.formatting = $0 }),
            isFocused: false, focusAtEndToken: 0, accessibilityIdentifier: "t", onFocusChange: { _ in }
        )
        let coordinator = editor.makeCoordinator()
        let view = UITextView()
        view.delegate = coordinator
        coordinator.view = view
        coordinator.load(text, formatting, into: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.addSubview(view)
        view.frame = window.bounds
        window.makeKeyAndVisible()
        return (view, coordinator, holder)
    }

    // Types the way the keyboard does: asks the delegate, then inserts.
    private func type(_ text: String, into view: UITextView, _ coordinator: GrowingTextEditor.Coordinator) {
        for character in text {
            let piece = String(character)
            if coordinator.textView(view, shouldChangeTextIn: view.selectedRange, replacementText: piece) {
                view.insertText(piece)
                coordinator.textViewDidChange(view)
            }
        }
    }

    @Test func returnCarriesAListItemIntoTheNextParagraph() {
        let (view, coordinator) = make("Milk", EntryFormatting(paragraphs: [.init(index: 0, block: .bullet)]))
        view.selectedRange = NSRange(location: 4, length: 0)
        type("\n", into: view, coordinator)
        type("Eggs", into: view, coordinator)
        // No stray space: UIKit's own list editing, which writes "\n " on Return in a list
        // paragraph, is kept out of the Return path.
        #expect(view.text.replacingOccurrences(of: "\n", with: "|") == "Milk|Eggs")
        let formatting = FormattingStyle.formatting(of: view.textStorage)
        #expect(formatting.paragraphs == [.init(index: 0, block: .bullet), .init(index: 1, block: .bullet)])
        #expect(coordinator.paragraph(at: 9, in: view).block == .bullet)
    }

    @Test func returnOnAnEmptyItemLeavesTheListAndKeepsTheCaret() {
        let (view, coordinator) = make("Milk\n", EntryFormatting(paragraphs: [.init(index: 0, block: .bullet), .init(index: 1, block: .bullet)]))
        view.selectedRange = NSRange(location: 5, length: 0)
        type("\n", into: view, coordinator)
        #expect(view.text.replacingOccurrences(of: "\n", with: "|") == "Milk|", "no newline was added")
        #expect(view.selectedRange == NSRange(location: 5, length: 0))
        #expect(coordinator.paragraph(at: 5, in: view).block == nil)
        type("Plain", into: view, coordinator)
        #expect(FormattingStyle.formatting(of: view.textStorage).paragraphs == [.init(index: 0, block: .bullet)])
    }

    @Test func aBarActionKeepsTheSelection() {
        let (view, coordinator) = make("one two three")
        view.selectedRange = NSRange(location: 4, length: 3)
        coordinator.perform(.inline(.bold))
        #expect(view.selectedRange == NSRange(location: 4, length: 3))
        #expect(FormattingStyle.formatting(of: view.textStorage).spans == [.init(location: 4, length: 3, bold: true)])
        view.selectedRange = NSRange(location: 13, length: 0)
        coordinator.perform(.block(.number))
        #expect(view.selectedRange == NSRange(location: 13, length: 0))
        #expect(FormattingStyle.formatting(of: view.textStorage).paragraphs == [.init(index: 0, block: .number)])
    }

    private func deleteBackward(in view: UITextView, _ coordinator: GrowingTextEditor.Coordinator) {
        let caret = view.selectedRange.location
        let range = NSRange(location: caret - 1, length: 1)
        if coordinator.textView(view, shouldChangeTextIn: range, replacementText: "") {
            view.deleteBackward()
            coordinator.textViewDidChange(view)
        }
    }

    private func caretX(_ view: UITextView) -> CGFloat {
        view.layoutIfNeeded()
        if let layout = view.textLayoutManager { layout.ensureLayout(for: layout.documentRange) }
        guard let position = view.position(from: view.beginningOfDocument, offset: view.selectedRange.location) else { return -1 }
        return view.caretRect(for: position).minX
    }

    // TextKit draws no marker and no indent for a line with no characters, so the new empty item
    // at the end of a list holds a marked space that carries its list. It is never reported.
    @Test func returnAtTheEndOfAListDrawsTheNextItemBeforeAnythingIsTyped() throws {
        let (view, coordinator, holder) = makeReporting("Milk", EntryFormatting(paragraphs: [.init(index: 0, block: .number)]))
        // Where the first item's words start: the caret on the new item belongs there too.
        view.selectedRange = NSRange(location: 0, length: 0)
        let itemTextX = caretX(view)
        view.selectedRange = NSRange(location: 4, length: 0)
        type("\n", into: view, coordinator)

        #expect(holder.text == "Milk\n", "the words carry no marker")
        #expect(holder.formatting.paragraphs == [.init(index: 0, block: .number), .init(index: 1, block: .number)])
        #expect(view.selectedRange == NSRange(location: 5, length: 0))
        let style = try #require(view.textStorage.attribute(.paragraphStyle, at: 5, effectiveRange: nil) as? NSParagraphStyle)
        let first = try #require(view.textStorage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(style.textLists.first === first.textLists.first, "one list, so the new item is numbered 2")
        #expect(abs(caretX(view) - itemTextX) < 2, "the caret sits where the item's words start, not at the margin")

        type("Eggs", into: view, coordinator)
        #expect(holder.text == "Milk\nEggs")
        #expect(view.text == "Milk\nEggs", "the hidden space goes once the item has words")
    }

    @Test func aListPickedOnAnEmptyEntryHoldsUntilTheFirstLetter() {
        let (view, coordinator, holder) = makeReporting("")
        coordinator.perform(.block(.bullet))
        #expect(holder.text == "")
        #expect(holder.formatting.paragraphs == [.init(index: 0, block: .bullet)])
        #expect(coordinator.paragraph(at: 0, in: view).block == .bullet)
        type("M", into: view, coordinator)
        #expect(view.text == "M")
        #expect(holder.formatting.paragraphs == [.init(index: 0, block: .bullet)])
    }

    @Test func leavingTheEmptyLastItemDropsTheHiddenCharacter() {
        let (view, coordinator, holder) = makeReporting("Milk", EntryFormatting(paragraphs: [.init(index: 0, block: .bullet)]))
        view.selectedRange = NSRange(location: 4, length: 0)
        type("\n", into: view, coordinator)
        // Backspace at the start of the empty item takes its bullet first.
        deleteBackward(in: view, coordinator)
        #expect(view.text == "Milk\n")
        #expect(holder.formatting.paragraphs == [.init(index: 0, block: .bullet)])
        #expect(view.selectedRange == NSRange(location: 5, length: 0))
    }

    @Test func returnOnTheEmptyLastItemLeavesTheListAndDropsTheHiddenCharacter() {
        let (view, coordinator, holder) = makeReporting("Milk", EntryFormatting(paragraphs: [.init(index: 0, block: .bullet)]))
        view.selectedRange = NSRange(location: 4, length: 0)
        type("\n", into: view, coordinator)
        type("\n", into: view, coordinator)
        #expect(view.text == "Milk\n")
        #expect(holder.text == "Milk\n")
        #expect(holder.formatting.paragraphs == [.init(index: 0, block: .bullet)])
        #expect(view.selectedRange == NSRange(location: 5, length: 0))
    }

    @Test func loadingAnEntryThatEndsOnAnEmptyItemDrawsIt() {
        let (view, coordinator, holder) = makeReporting("Milk\n", EntryFormatting(paragraphs: [.init(index: 0, block: .check), .init(index: 1, block: .check)]))
        #expect(coordinator.paragraph(at: 5, in: view).block == .check)
        #expect(coordinator.currentFormatting() == holder.formatting)
        #expect((view.textStorage.string as NSString).length == 6)
    }

    // Only the marked space is the sentinel: a space the user typed on the line stays theirs.
    @Test func aTypedSpaceIsNeverTakenForTheHiddenOne() {
        let (view, coordinator, holder) = makeReporting("Milk", EntryFormatting(paragraphs: [.init(index: 0, block: .bullet)]))
        view.selectedRange = NSRange(location: 4, length: 0)
        type("\n", into: view, coordinator)
        type(" ", into: view, coordinator)
        #expect(holder.text == "Milk\n ")
        #expect(view.text == "Milk\n ")
        #expect(holder.formatting.paragraphs == [.init(index: 0, block: .bullet), .init(index: 1, block: .bullet)])
    }
}
