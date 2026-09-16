import SwiftUI
import UIKit

// A text view that grows with its text instead of scrolling on its own, so an entry's header
// (title, player, page thumbnails) scrolls together with the writing in one scroll view.
// It keeps at least `minHeight` so a tap below short text still lands in the text and puts the
// cursor at the end, the way Notes behaves.
struct GrowingTextEditor: UIViewRepresentable {
    @Binding var text: String
    var minHeight: CGFloat
    var isFocused: Bool
    var onFocusChange: (Bool) -> Void

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 24, right: 0)
        view.textContainer.lineFragmentPadding = 0
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text {
            // Keep the caret where it was when the text changed from elsewhere.
            let selection = view.selectedRange
            view.text = text
            view.selectedRange = NSRange(location: min(selection.location, text.utf16.count), length: 0)
        }
        view.minimumContentHeight = minHeight
        if isFocused && !view.isFirstResponder {
            view.becomeFirstResponder()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(fitting.height, minHeight))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: GrowingTextEditor

        init(_ parent: GrowingTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
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

private extension UITextView {
    // Taps below the last line should still reach the text view, so it never ends shorter than this.
    var minimumContentHeight: CGFloat {
        get { 0 }
        set {
            let inset = max(0, newValue - sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude)).height)
            if abs(textContainerInset.bottom - (24 + inset)) > 1 {
                textContainerInset.bottom = 24 + inset
            }
        }
    }
}
