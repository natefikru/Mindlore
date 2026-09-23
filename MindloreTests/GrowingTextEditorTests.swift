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
        return (view, coordinator)
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
}
