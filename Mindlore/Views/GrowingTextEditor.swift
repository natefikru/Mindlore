import SwiftUI
import UIKit

// A text view that grows with its text instead of scrolling on its own, so an entry's header
// (title, player, page thumbnails) scrolls together with the writing in one scroll view.
// The blank space below the text belongs to the view above it, which focuses this one and puts the
// caret at the end, the way Notes behaves.
struct GrowingTextEditor: UIViewRepresentable {
    @Binding var text: String
    var isFocused: Bool
    // Bumped by the caller to ask for focus with the caret at the end of the text.
    var focusAtEndToken: Int
    var onFocusChange: (Bool) -> Void

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.font = .journal(.body)
        view.textColor = UIColor(Palette.ink)
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        view.textContainer.lineFragmentPadding = 0
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        // Never replace text while the keyboard is mid-composition (marked text, dictation): assigning
        // would drop what the user is in the middle of typing.
        if view.text != text, view.markedTextRange == nil {
            let selection = view.selectedRange
            view.text = text
            view.selectedRange = NSRange(location: min(selection.location, text.utf16.count), length: 0)
        }
        if focusAtEndToken != context.coordinator.handledFocusToken {
            context.coordinator.handledFocusToken = focusAtEndToken
            view.selectedRange = NSRange(location: view.text.utf16.count, length: 0)
            view.becomeFirstResponder()
        } else if isFocused && !view.isFirstResponder {
            view.becomeFirstResponder()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: fitting.height)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        // Updated on every render, so the delegate always writes through the current binding.
        var parent: GrowingTextEditor
        var handledFocusToken: Int

        init(_ parent: GrowingTextEditor) {
            self.parent = parent
            handledFocusToken = parent.focusAtEndToken
        }

        func textViewDidChange(_ textView: UITextView) {
            // Always recorded, including while text is marked: inline predictions and dictation mark
            // text as you type, and skipping those would lose what was typed.
            parent.text = textView.text
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onFocusChange(true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.onFocusChange(false)
        }
    }
}
