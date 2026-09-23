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
        view.font = .journal(.body, design: context.environment.journalFont.uiDesign)
        context.coordinator.appliedFont = context.environment.journalFont
        view.textColor = UIColor(Palette.ink)
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        view.textContainer.lineFragmentPadding = 0
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        let font = context.environment.journalFont
        if font != coordinator.appliedFont {
            // Setting the font re-applies attributes to the whole text; the selection is kept
            // across it so a font change from Settings never moves a caret.
            let selection = view.selectedRange
            view.font = .journal(.body, design: font.uiDesign)
            view.selectedRange = selection
            coordinator.appliedFont = font
        }
        // Text is only ever pushed in from outside for text the view didn't type itself: a
        // transcription landing, a cleanup applied, a revert. What the view just reported through
        // the binding comes straight back as `text` on the next update and is never re-assigned,
        // because assigning a UITextView's text, even to an equal string, resets its selection and
        // the caret lands at the start (the first keystroke of a new entry created the entry, the
        // screen redrew with a toolbar and a title, and the second keystroke went in front of the
        // first). Never while the keyboard is mid-composition (marked text, dictation) either:
        // assigning would drop what the user is in the middle of typing.
        if text != coordinator.lastReportedText, view.text != text, view.markedTextRange == nil {
            let wasEditing = view.isFirstResponder
            let selection = view.selectedRange
            view.text = text
            coordinator.lastReportedText = text
            let end = text.utf16.count
            // Text arriving under a caret keeps the caret where it was; text arriving into an
            // unfocused view leaves the caret at its end, where typing would continue.
            view.selectedRange = NSRange(location: wasEditing ? min(selection.location, end) : end, length: 0)
        }
        if focusAtEndToken != coordinator.handledFocusToken {
            coordinator.handledFocusToken = focusAtEndToken
            view.selectedRange = NSRange(location: view.text.utf16.count, length: 0)
            if !view.isFirstResponder {
                view.becomeFirstResponder()
            }
        } else if isFocused && !view.isFirstResponder && !coordinator.resignedByUser {
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
        var appliedFont: JournalFont = .serif
        // The last text this view sent out through the binding, so an update that only echoes it
        // back is told apart from text that really changed outside the view.
        var lastReportedText: String?
        // The keyboard went away by the user's hand (a drag on the scroll view, the Done button),
        // so a stale focus flag must not bring it straight back.
        var resignedByUser = false

        init(_ parent: GrowingTextEditor) {
            self.parent = parent
            handledFocusToken = parent.focusAtEndToken
        }

        func textViewDidChange(_ textView: UITextView) {
            // Always recorded, including while text is marked: inline predictions and dictation mark
            // text as you type, and skipping those would lose what was typed.
            lastReportedText = textView.text
            parent.text = textView.text
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            resignedByUser = false
            parent.onFocusChange(true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            resignedByUser = true
            parent.onFocusChange(false)
        }
    }
}
