import SwiftUI
import UIKit

// The entry's text, read or typed, in one UITextView that grows with its text instead of scrolling
// on its own, so an entry's header (title, player, page thumbnails) scrolls together with the
// writing in one scroll view. Read mode is the same view made non-editable, with the names linked:
// a tap on a name opens it through the text view's own link action, and a tap anywhere else says
// which character it landed on, so the editor can open with the caret there. Formatting (headings,
// lists, bold) lives in the view's attributes while typing, drawn by TextKit 2 from
// `FormattingStyle`, and is reported back as `EntryFormatting` beside the text.
//
// One fact shapes the coordinator: UITextView's typing attributes keep only the font, colour, and
// paragraph style (measured in GrowingTextEditorTests), so a custom attribute never reaches typed
// text on its own and the empty paragraph after the last newline has no character to carry one.
// So Return is always applied by hand, and after every edit the paragraph touched is normalised
// from whichever character still carries the key, with inline marks read back from the font UIKit
// did keep. An empty last paragraph with a list or indent holds one space marked `sentinelKey` to
// carry its block, because TextKit draws neither a marker nor an indent for a line with no
// characters: without it, Return at the end of a list left the caret at the margin and the "2."
// appeared only with the first letter. A zero-width space drew the marker but TextKit lays it out
// as nothing, so the caret still sat in front of the "2."; a space has width and puts the caret
// where the words start. The mark, not the character, is what makes it the sentinel, so a space
// the user typed is never taken for one. It is never reported; the text is the words.
struct GrowingTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var formatting: EntryFormatting
    var isEditable = true
    var isFocused: Bool
    // Bumped by the caller to ask for focus, with the caret at `focusOffset` when there is one
    // (a tap on the text being read) and at the end of the text otherwise.
    var focusAtEndToken: Int
    var focusOffset: Int? = nil
    // False while something covers the journal (the app lock): focus the app took with it when it
    // left waits until then, so a keyboard never opens over the lock cover.
    var canRestoreFocus = true
    // The format bar goes away while a recording sits in the accessory: the two would stack.
    var showsFormatBar = true
    // Names to link while reading.
    var links: [EntryNameLinks.Link] = []
    var accessibilityIdentifier: String
    // Who an "@" could mean, for the bar's completion row.
    var mentionRows: [EntitySearch.Row] = []
    var onFocusChange: (Bool) -> Void
    var onLinkTap: (UUID) -> Void = { _ in }
    // A tap on the text being read, at a UTF-16 offset.
    var onReadTap: (Int) -> Void = { _ in }
    var onFormatted: () -> Void = {}
    // A name picked from the "@" row (the name is already in the text), and a "#word" completed.
    var onMention: (GraphServices.AddedNameTarget) -> Void = { _ in }
    var onTag: (String) -> Void = { _ in }

    func makeUIView(context: Context) -> UITextView {
        let view = EditorTextView()
        let coordinator = context.coordinator
        view.backspaceAtStart = { [weak coordinator, weak view] in
            guard let coordinator, let view else { return false }
            return coordinator.backspaceAtStart(of: view)
        }
        view.delegate = context.coordinator
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        view.textContainer.lineFragmentPadding = 0
        // Link colours come from the text's own attributes, per kind.
        view.linkTextAttributes = [:]
        coordinator.fonts = FormattingStyle.Fonts(journalFont: context.environment.journalFont)
        coordinator.appliedFont = context.environment.journalFont
        coordinator.view = view
        coordinator.bar.model.onAction = { [weak coordinator] action in coordinator?.perform(action) }
        coordinator.bar.model.onPick = { [weak coordinator] pick in coordinator?.pick(pick) }
        let tap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = coordinator
        view.addGestureRecognizer(tap)
        coordinator.load(text, formatting, into: view)
        // Selector observers are removed with the coordinator.
        NotificationCenter.default.addObserver(coordinator, selector: #selector(Coordinator.appWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(coordinator, selector: #selector(Coordinator.appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(coordinator, selector: #selector(Coordinator.inputModeChanged), name: UITextInputMode.currentInputModeDidChangeNotification, object: nil)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        view.accessibilityIdentifier = accessibilityIdentifier
        let font = context.environment.journalFont
        if font != coordinator.appliedFont {
            // Re-fonting the whole text is attributes only; the selection is kept across it so a
            // font change from Settings never moves a caret.
            coordinator.fonts = FormattingStyle.Fonts(journalFont: font)
            coordinator.appliedFont = font
            if view.textStorage.length == 0 { view.font = coordinator.fonts.body }
            coordinator.restyleAll()
        }
        // Text is only ever pushed in from outside for text the view didn't type itself: a
        // transcription landing, a cleanup applied, a revert. What the view just reported through
        // the binding comes straight back as `text` on the next update and is never re-assigned,
        // because assigning a UITextView's text, even to an equal string, resets its selection and
        // the caret lands at the start (the first keystroke of a new entry created the entry, the
        // screen redrew with a toolbar and a title, and the second keystroke went in front of the
        // first). Never while the keyboard is mid-composition (marked text, dictation) either:
        // assigning would drop what the user is in the middle of typing.
        let outside = (text, formatting)
        let echoed = coordinator.lastReported.map { $0 == outside } ?? false
        if !echoed, view.markedTextRange == nil, Coordinator.plain(view.textStorage) != text || coordinator.currentFormatting() != formatting {
            let wasEditing = view.isFirstResponder
            let selection = view.selectedRange
            coordinator.load(text, formatting, into: view)
            let end = text.utf16.count
            // Text arriving under a caret keeps the caret where it was; text arriving into an
            // unfocused view leaves the caret at its end, where typing would continue.
            view.selectedRange = NSRange(location: wasEditing ? min(selection.location, end) : end, length: 0)
            coordinator.appliedLinks = []
        }
        if view.isEditable != isEditable {
            view.isEditable = isEditable
            if !isEditable, view.isFirstResponder {
                coordinator.resignedByUser = true
                view.resignFirstResponder()
            }
        }
        let wantedLinks = isEditable ? [] : links
        if coordinator.appliedLinks != wantedLinks {
            coordinator.apply(links: wantedLinks)
        }
        let bar: UIView? = isEditable && showsFormatBar ? coordinator.bar.view : nil
        if view.inputAccessoryView !== bar {
            view.inputAccessoryView = bar
            if view.isFirstResponder { view.reloadInputViews() }
        }
        if focusAtEndToken != coordinator.handledFocusToken {
            coordinator.handledFocusToken = focusAtEndToken
            let end = Coordinator.plain(view.textStorage).utf16.count
            view.selectedRange = NSRange(location: min(focusOffset ?? end, end), length: 0)
            if isEditable, !view.isFirstResponder {
                view.becomeFirstResponder()
            }
        } else if isEditable && isFocused && !view.isFirstResponder && !coordinator.resignedByUser {
            view.becomeFirstResponder()
        }
        // The lock lifting is an update, not an activation, so a focus held back for it comes here.
        if canRestoreFocus { coordinator.restoreFocusIfNeeded() }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: fitting.height)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        // Updated on every render, so the delegate always writes through the current binding.
        var parent: GrowingTextEditor
        weak var view: UITextView?
        var handledFocusToken: Int
        var appliedFont: JournalFont = .serif
        var fonts = FormattingStyle.Fonts(journalFont: .serif)
        let bar = FormatBarHost()
        // The last text and formatting this view sent out through the binding, so an update that
        // only echoes them back is told apart from text that really changed outside the view.
        var lastReported: (String, EntryFormatting)?
        var appliedLinks: [EntryNameLinks.Link] = []
        // The keyboard went away by the user's hand (a drag on the scroll view, the Done button),
        // so a stale focus flag must not bring it straight back.
        var resignedByUser = false
        // The selection the view was editing with when the app went inactive, until the app is
        // back. A third-party keyboard's voice typing (Gboard's microphone key) switches to the
        // keyboard's own app to record and then types into this view through the keyboard once
        // the user comes back, so coming back must find the view still editing with the caret where
        // it was. UIKit can end editing while the app is away; that is not the user's hand.
        var focusToRestore: NSRange?
        // Carries the block of an empty last paragraph; see the note at the top of the file.
        static let sentinelKey = NSAttributedString.Key("mindlore.sentinel")

        static func isSentinel(at index: Int, in storage: NSAttributedString) -> Bool {
            index >= 0 && index < storage.length && storage.attribute(sentinelKey, at: index, effectiveRange: nil) != nil
        }

        // The words, without the sentinel.
        static func plain(_ storage: NSAttributedString) -> String {
            guard isSentinel(at: storage.length - 1, in: storage) else { return storage.string }
            return (storage.string as NSString).substring(to: storage.length - 1)
        }

        static func sentinel(font: UIFont) -> NSAttributedString {
            NSAttributedString(string: " ", attributes: [.font: font, sentinelKey: true])
        }
        // The inline marks typed text takes: toggled by the bar, otherwise read from the text
        // before the caret whenever the caret moves.
        private var typingInline: FormattingStyle.Inline = []
        // Set by the delegate before an edit, read after it to normalise what changed.
        private var pendingEdit: (range: NSRange, inserted: Int, crossesParagraphs: Bool)?
        // What the system's dictation has written so far, normalised once it finishes. The
        // microphone in the bar under a third-party keyboard (and the one on Apple's) switches the
        // view into dictation, which streams its text in and revises it as it goes; restyling the
        // storage or moving the selection under it makes UIKit treat the text as changed from
        // outside and end dictation at once, which is what made the button look dead.
        private var dictatedRange: NSRange?
        private var dictationChangedUnseen = false

        static func isDictating(_ textView: UITextView) -> Bool {
            textView.textInputMode?.primaryLanguage == "dictation"
        }

        init(_ parent: GrowingTextEditor) {
            self.parent = parent
            handledFocusToken = parent.focusAtEndToken
        }

        var palette: FormattingStyle.Palette {
            FormattingStyle.Palette(ink: UIColor(Palette.ink), quote: UIColor(Palette.ink).withAlphaComponent(0.7), marker: UIColor(Palette.ink).withAlphaComponent(0.6))
        }

        func styled(_ text: String, _ formatting: EntryFormatting) -> NSAttributedString {
            FormattingStyle.attributedString(text: text, formatting: formatting, fonts: fonts, palette: palette)
        }

        // Text from outside, whole.
        func load(_ text: String, _ formatting: EntryFormatting, into view: UITextView) {
            var display = text
            if hasTrailingParagraph(text as NSString) {
                let index = FormattingStyle.paragraphIndex(at: text.utf16.count, in: text as NSString)
                let paragraph = formatting.paragraph(at: index)
                if paragraph.block != nil || paragraph.indent > 0 { display += " " }
            }
            let styledText = NSMutableAttributedString(attributedString: styled(display, formatting))
            if display != text {
                styledText.addAttribute(Self.sentinelKey, value: true, range: NSRange(location: styledText.length - 1, length: 1))
            }
            view.attributedText = styledText
            lastReported = (text, formatting)
            typingInline = []
            // An empty text has no characters to carry a font, so without this an empty entry
            // lays out its caret and its first line in UIKit's default font, and the first letter
            // then jumps the text to the journal font's size. Only when empty: setting `font` on
            // text restyles every character and would flatten headings and bold.
            if display.isEmpty { view.font = fonts.body }
            applyTypingAttributes(view)
        }

        // What the view holds now, the sentinel's paragraph included.
        func currentFormatting() -> EntryFormatting {
            guard let view else { return .empty }
            return FormattingStyle.formatting(of: view.textStorage)
        }

        // MARK: Reporting

        func textViewDidChange(_ textView: UITextView) {
            // Always recorded, including while text is marked: inline predictions and dictation mark
            // text as you type, and skipping those would lose what was typed.
            if Self.isDictating(textView) {
                noteDictated(textView)
                report(from: textView)
                return
            }
            normaliseAfterEdit(textView)
            syncSentinel(textView)
            report(from: textView)
        }

        private func report(from textView: UITextView) {
            let formatting = currentFormatting()
            let text = Self.plain(textView.textStorage)
            lastReported = (text, formatting)
            if parent.text != text { parent.text = text }
            if parent.formatting != formatting { parent.formatting = formatting }
            refreshBar(textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard textView.markedTextRange == nil, !Self.isDictating(textView) else { return }
            // Never past the sentinel: typing goes in front of it, into its paragraph.
            let end = (Self.plain(textView.textStorage) as NSString).length
            if textView.selectedRange.length == 0, textView.selectedRange.location > end {
                textView.selectedRange = NSRange(location: end, length: 0)
                return
            }
            let caret = textView.selectedRange.location
            // Typed text takes the marks of what it follows. The bar's toggle changes this after.
            typingInline = FormattingStyle.inline(at: caret, in: textView.textStorage)
            applyTypingAttributes(textView)
            refreshBar(textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            resignedByUser = false
            parent.onFocusChange(true)
        }

        // Between the app going inactive and becoming active again, when nothing is restored.
        private var appIsAway = false

        @objc func appWillResignActive() {
            appIsAway = true
            // Not cleared when the view isn't editing: after a trip away with the app lock on, the
            // Face ID sheet makes the app inactive again while the focus is still held back.
            guard let view, view.isEditable, view.isFirstResponder else { return }
            focusToRestore = view.selectedRange
        }

        @objc func appDidBecomeActive() {
            appIsAway = false
            guard parent.canRestoreFocus else { return }
            restoreFocusIfNeeded()
        }

        func restoreFocusIfNeeded() {
            guard let selection = focusToRestore, !appIsAway else { return }
            focusToRestore = nil
            guard let view, view.isEditable, !view.isFirstResponder, view.window != nil else { return }
            let end = Self.plain(view.textStorage).utf16.count
            let location = min(selection.location, end)
            view.selectedRange = NSRange(location: location, length: min(selection.length, end - location))
            resignedByUser = false
            view.becomeFirstResponder()
            DiagnosticsLog.shared.record("editor.focusRestored")
        }

        // MARK: Dictation

        // Leaves the storage alone while dictation runs and remembers the span it touched, moved
        // along by each later edit, so nothing it wrote goes without its paragraph's formatting.
        private func noteDictated(_ textView: UITextView) {
            guard let edit = pendingEdit else {
                dictationChangedUnseen = true
                return
            }
            pendingEdit = nil
            let start = edit.range.location
            var end = start + edit.inserted
            if let previous = dictatedRange {
                var previousEnd = NSMaxRange(previous)
                if start <= previousEnd { previousEnd += edit.inserted - edit.range.length }
                end = max(end, previousEnd)
                dictatedRange = NSRange(location: min(start, previous.location), length: max(0, end - min(start, previous.location)))
            } else {
                dictatedRange = NSRange(location: start, length: edit.inserted)
            }
        }

        @objc func inputModeChanged() {
            // The input mode reports the switch back a moment after the notification.
            DispatchQueue.main.async { [weak self] in self?.finishDictationIfEnded() }
        }

        // Once dictation has handed the keyboard back, what it wrote is normalised the way a
        // typed edit is: its paragraphs re-marked, the sentinel kept in place, the result reported.
        func finishDictationIfEnded() {
            guard let view, dictatedRange != nil || dictationChangedUnseen, !Self.isDictating(view), view.markedTextRange == nil else { return }
            let length = (view.textStorage.string as NSString).length
            if let range = dictatedRange {
                let location = min(range.location, length)
                let clamped = NSRange(location: location, length: min(range.length, length - location))
                pendingEdit = (clamped, clamped.length, true)
                normaliseAfterEdit(view)
            } else {
                restyleAll()
                applyTypingAttributes(view)
            }
            dictatedRange = nil
            dictationChangedUnseen = false
            syncSentinel(view)
            report(from: view)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            finishDictationIfEnded()
            // Ended by UIKit while the app was away, not by the user: coming back restores it.
            resignedByUser = focusToRestore == nil
            bar.model.mention = nil
            // A tag the text ends on has nothing typed after it; leaving the field completes it.
            let text = Self.plain(textView.textStorage)
            if let tag = MentionDetection.completedTag(in: text, endingAt: text.utf16.count) {
                parent.onTag(tag.word)
            }
            parent.onFocusChange(false)
        }

        private func refreshBar(_ textView: UITextView) {
            let paragraph = paragraph(at: textView.selectedRange.location, in: textView)
            bar.model.block = paragraph.block
            bar.model.indent = paragraph.indent
            bar.model.inline = textView.selectedRange.length == 0
                ? typingInline
                : FormattingStyle.inline(at: textView.selectedRange.location + 1, in: textView.textStorage)
            refreshMention(textView)
        }

        // MARK: Paragraphs

        private func hasTrailingParagraph(_ string: NSString) -> Bool {
            string.length == 0 || string.character(at: string.length - 1) == 10
        }

        private func isTrailing(_ location: Int, in string: NSString) -> Bool {
            location >= string.length && hasTrailingParagraph(string)
        }

        func paragraph(at location: Int, in textView: UITextView) -> EntryFormatting.Paragraph {
            let string = textView.textStorage.string as NSString
            let index = FormattingStyle.paragraphIndex(at: location, in: string)
            if isTrailing(location, in: string) {
                return EntryFormatting.Paragraph(index: index)
            }
            let range = FormattingStyle.paragraphRange(at: location, in: string)
            let (block, indent) = FormattingStyle.blockAndIndent(in: NSRange(location: range.location, length: min(range.length + 1, string.length - range.location)), of: textView.textStorage)
            return EntryFormatting.Paragraph(index: index, block: block, indent: indent)
        }

        // MARK: Undo

        // Return in a list, Backspace at an item's start, the bar, a tick, and a picked name change
        // the storage directly, where UIKit's undo manager never sees them: undo then skipped the
        // change and could replay an older keystroke at a range that no longer matched the text.
        // Each one registers its own step instead, a snapshot of the text and the caret before it;
        // undoing restores it and registers the reverse as the redo. Nested calls (a Return that
        // sets its new paragraph's block, a bar action over several lines) make one step.
        private var undoDepth = 0

        func undoable(_ view: UITextView, _ change: () -> Void) {
            undoDepth += 1
            defer { undoDepth -= 1 }
            guard undoDepth == 1, let undoManager = view.undoManager else {
                change()
                return
            }
            let before = NSAttributedString(attributedString: view.textStorage)
            let selection = view.selectedRange
            change()
            undoManager.registerUndo(withTarget: self) { coordinator in
                coordinator.restore(before, selection: selection, in: view)
            }
        }

        private func restore(_ snapshot: NSAttributedString, selection: NSRange, in view: UITextView) {
            let current = NSAttributedString(attributedString: view.textStorage)
            let currentSelection = view.selectedRange
            view.undoManager?.registerUndo(withTarget: self) { coordinator in
                coordinator.restore(current, selection: currentSelection, in: view)
            }
            let storage = view.textStorage
            storage.beginEditing()
            storage.setAttributedString(snapshot)
            storage.endEditing()
            view.selectedRange = NSRange(location: min(selection.location, storage.length), length: min(selection.length, max(0, storage.length - selection.location)))
            syncSentinel(view)
            applyTypingAttributes(view)
            report(from: view)
        }

        // Backspace with the caret at the very start of the text: there is no character before it,
        // so UIKit never asks the delegate, and a first line that is a list or a heading kept its
        // marker. Returns true when the keystroke was used here.
        func backspaceAtStart(of view: UITextView) -> Bool {
            guard view.isEditable, view.markedTextRange == nil, view.selectedRange == NSRange(location: 0, length: 0) else { return false }
            let paragraph = paragraph(at: 0, in: view)
            let state = ListEditing.Paragraph(block: paragraph.block, indent: paragraph.indent, isEmpty: false)
            switch ListEditing.onBackspaceAtStart(in: state) {
            case .removeBlock:
                set(EntryFormatting.Paragraph(index: 0, block: nil, indent: paragraph.indent), at: 0, in: view)
                return true
            case .outdent:
                set(EntryFormatting.Paragraph(index: 0, indent: paragraph.indent - 1), at: 0, in: view)
                return true
            default:
                return false
            }
        }

        // Gives the paragraph under `location` a block and indent, carried as attributes, and
        // restyles the whole text so numbered runs recount. The empty last paragraph gets the
        // sentinel to carry them.
        private func set(_ paragraph: EntryFormatting.Paragraph, at location: Int, in textView: UITextView) {
            undoable(textView) { apply(paragraph, at: location, in: textView) }
        }

        private func apply(_ paragraph: EntryFormatting.Paragraph, at location: Int, in textView: UITextView) {
            let storage = textView.textStorage
            let string = storage.string as NSString
            if isTrailing(location, in: string) {
                if paragraph.block != nil || paragraph.indent > 0 {
                    let selection = textView.selectedRange
                    // Read before the append: `storage.string` is live and grows with it.
                    let end = string.length
                    storage.beginEditing()
                    storage.append(Self.sentinel(font: fonts.body))
                    storage.endEditing()
                    FormattingStyle.setBlock(paragraph.block, indent: paragraph.indent, in: NSRange(location: end, length: 1), of: storage)
                    textView.selectedRange = selection
                    restyleAll()
                }
            } else {
                let range = FormattingStyle.paragraphRange(at: location, in: string)
                let withNewline = NSRange(location: range.location, length: min(range.length + 1, string.length - range.location))
                FormattingStyle.setBlock(paragraph.block, indent: paragraph.indent, in: withNewline, of: storage)
                restyleAll()
            }
            syncSentinel(textView)
            applyTypingAttributes(textView)
            report(from: textView)
            parent.onFormatted()
        }

        // The caret's paragraph and inline marks, as what typed text will take; UIKit keeps the
        // font and paragraph style of these and drops the rest, which the edit path restores.
        private func applyTypingAttributes(_ textView: UITextView) {
            let paragraph = paragraph(at: textView.selectedRange.location, in: textView)
            let string = textView.textStorage.string as NSString
            var list: NSTextList?
            if paragraph.block == .number, !isTrailing(textView.selectedRange.location, in: string) {
                let range = FormattingStyle.paragraphRange(at: textView.selectedRange.location, in: string)
                if range.location < string.length {
                    list = (textView.textStorage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)?.textLists.first
                }
            }
            let attributes = FormattingStyle.typingAttributes(paragraph: paragraph, inline: typingInline, list: list, fonts: fonts, palette: palette)
            // Only when something UIKit keeps would change (it drops the custom keys anyway): a
            // needless reset mid-dictation is one more outside change under it.
            let kept: [NSAttributedString.Key] = [.font, .foregroundColor, .paragraphStyle, .strikethroughStyle]
            let current = textView.typingAttributes
            let unchanged = kept.allSatisfy { key in
                switch (current[key] as? NSObject, attributes[key] as? NSObject) {
                case (nil, nil): true
                case let (lhs?, rhs?): lhs.isEqual(rhs)
                default: false
                }
            }
            if !unchanged { textView.typingAttributes = attributes }
        }

        // After UIKit applied an edit: the characters it inserted carry no custom keys, so the
        // paragraph they landed in is re-marked from the key on any character it still has (or
        // from the sentinel, if it was the empty last paragraph), and the inserted characters take
        // the inline marks the caret was typing with.
        private func normaliseAfterEdit(_ textView: UITextView) {
            let storage = textView.textStorage
            let string = storage.string as NSString
            guard let edit = pendingEdit else { return }
            pendingEdit = nil
            guard textView.markedTextRange == nil else { return }
            let inserted = NSRange(location: edit.range.location, length: min(edit.inserted, max(0, string.length - edit.range.location)))
            // Plain words into a plain paragraph already carry what UIKit's typing attributes gave
            // them, which is all this would write. Leaving the storage untouched there is what
            // keeps Apple's dictation running: on its keyboard it streams text in with the keyboard
            // still up (the input mode never reads "dictation"), and any write to the storage
            // under it ends it.
            if typingInline.isEmpty, !edit.crossesParagraphs {
                let current = paragraph(at: inserted.location, in: textView)
                if current.block == nil, current.indent == 0 {
                    applyTypingAttributes(textView)
                    return
                }
            }
            if inserted.length > 0 {
                FormattingStyle.setInline(typingInline, in: inserted, of: storage, fonts: fonts, block: nil)
            }
            var location = inserted.location
            let last = max(inserted.location, NSMaxRange(inserted) - 1)
            var restyled = false
            repeat {
                let range = FormattingStyle.paragraphRange(at: location, in: string)
                let withNewline = NSRange(location: range.location, length: min(range.length + 1, string.length - range.location))
                let (block, indent) = FormattingStyle.blockAndIndent(in: withNewline, of: storage)
                FormattingStyle.setBlock(block, indent: indent, in: withNewline, of: storage)
                if block == .number { restyled = true }
                location = NSMaxRange(withNewline)
            } while location <= last && location < string.length
            if restyled || edit.crossesParagraphs {
                restyleAll()
            } else {
                let range = FormattingStyle.paragraphRange(at: inserted.location, in: string)
                let withNewline = NSRange(location: range.location, length: min(range.length + 1, string.length - range.location))
                let paragraph = paragraph(at: inserted.location, in: textView)
                let list = (storage.attribute(.paragraphStyle, at: min(range.location, max(0, string.length - 1)), effectiveRange: nil) as? NSParagraphStyle)?.textLists.first
                FormattingStyle.style(withNewline, paragraph: paragraph, list: list, in: storage, fonts: fonts, palette: palette)
            }
            applyTypingAttributes(textView)
        }

        // Keeps the sentinel where it belongs: the only character of a last paragraph that has a
        // list or an indent. Anywhere else (its paragraph got words, its block was taken away, it
        // was pasted or joined into another line) it goes, and the caret never sits after it.
        func syncSentinel(_ view: UITextView) {
            guard view.markedTextRange == nil else { return }
            let storage = view.textStorage
            var selection = view.selectedRange
            var changed = false
            func remove(at index: Int) {
                storage.beginEditing()
                storage.deleteCharacters(in: NSRange(location: index, length: 1))
                storage.endEditing()
                if index < selection.location {
                    selection.location -= 1
                } else if index < NSMaxRange(selection) {
                    selection.length -= 1
                }
                changed = true
            }
            var index = (storage.string as NSString).length - 2
            while index >= 0 {
                if Self.isSentinel(at: index, in: storage) { remove(at: index) }
                index -= 1
            }
            let string = storage.string as NSString
            if Self.isSentinel(at: string.length - 1, in: storage) {
                let last = string.length - 1
                let range = FormattingStyle.paragraphRange(at: last, in: string)
                let (block, indent) = FormattingStyle.blockAndIndent(in: NSRange(location: last, length: 1), of: storage)
                if range.length > 1 || (block == nil && indent == 0) { remove(at: last) }
            }
            let end = (Self.plain(storage) as NSString).length
            if selection.location > end { selection = NSRange(location: end, length: 0) }
            if NSMaxRange(selection) > storage.length { selection.length = storage.length - selection.location }
            if changed || view.selectedRange != selection { view.selectedRange = selection }
        }

        // Attributes only, never characters, so the selection stays where it is.
        func restyleAll() {
            guard let view else { return }
            let formatting = FormattingStyle.formatting(of: view.textStorage)
            FormattingStyle.applyParagraphs(formatting, to: view.textStorage, fonts: fonts, palette: palette)
            if !appliedLinks.isEmpty, !view.isEditable {
                apply(links: appliedLinks)
            }
        }

        // MARK: Return and Backspace

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            let string = textView.textStorage.string as NSString
            if range.length == 0, text.count == 1 {
                noteCompletedTag(before: range.location, typing: text, in: textView)
            }
            if text == "\n", range.length == 0 {
                let paragraph = paragraph(at: range.location, in: textView)
                let paragraphRange = FormattingStyle.paragraphRange(at: range.location, in: string)
                // A paragraph holding only the sentinel is an empty item.
                let isEmpty = paragraphRange.length == 0 || (paragraphRange.length == 1 && Self.isSentinel(at: paragraphRange.location, in: textView.textStorage))
                let state = ListEditing.Paragraph(block: paragraph.block, indent: paragraph.indent, isEmpty: isEmpty)
                switch ListEditing.onReturn(in: state) {
                case .leaveList:
                    set(EntryFormatting.Paragraph(index: paragraph.index), at: range.location, in: textView)
                    return false
                case .newParagraph(let block, let indent):
                    // Through the storage, never `insertText`: in a list paragraph UIKit's own
                    // list editing takes that over and writes a newline plus a space (measured
                    // in GrowingTextEditorTests' probes; the space is a real character).
                    undoable(textView) {
                        let storage = textView.textStorage
                        storage.beginEditing()
                        storage.replaceCharacters(in: range, with: NSAttributedString(string: "\n", attributes: textView.typingAttributes))
                        storage.endEditing()
                        textView.selectedRange = NSRange(location: range.location + 1, length: 0)
                        let caret = textView.selectedRange.location
                        // The text after the caret, if any, is the new paragraph; it keeps whatever
                        // block it had until set below.
                        let index = FormattingStyle.paragraphIndex(at: caret, in: textView.textStorage.string as NSString)
                        set(EntryFormatting.Paragraph(index: index, block: block, indent: indent), at: caret, in: textView)
                    }
                    return false
                default:
                    break
                }
            }
            if text.isEmpty, range.length == 1, range.location < string.length, string.character(at: range.location) == 10 {
                let start = range.location + 1
                let paragraph = paragraph(at: start, in: textView)
                let state = ListEditing.Paragraph(block: paragraph.block, indent: paragraph.indent, isEmpty: false)
                switch ListEditing.onBackspaceAtStart(in: state) {
                case .removeBlock:
                    set(EntryFormatting.Paragraph(index: paragraph.index, block: nil, indent: paragraph.indent), at: start, in: textView)
                    return false
                case .outdent:
                    set(EntryFormatting.Paragraph(index: paragraph.index, indent: paragraph.indent - 1), at: start, in: textView)
                    return false
                default:
                    break
                }
            }
            let replaced = range.length > 0 ? string.substring(with: range) : ""
            pendingEdit = (range, text.utf16.count, text.contains("\n") || replaced.contains("\n"))
            return true
        }

        // MARK: The bar

        func perform(_ action: FormatAction) {
            guard let view else { return }
            switch action {
            case .dismissKeyboard:
                resignedByUser = true
                view.resignFirstResponder()
            case .block(let block):
                let paragraph = paragraph(at: view.selectedRange.location, in: view)
                let next = ListEditing.toggled(block, on: .init(block: paragraph.block, indent: paragraph.indent, isEmpty: false))
                undoable(view) {
                    forEachParagraph(in: view.selectedRange, of: view) { location, index in
                        set(EntryFormatting.Paragraph(index: index, block: next.block, indent: next.indent), at: location, in: view)
                    }
                }
            case .indent(let delta):
                undoable(view) {
                    forEachParagraph(in: view.selectedRange, of: view) { location, index in
                        let paragraph = paragraph(at: location, in: view)
                        let next = ListEditing.indented(.init(block: paragraph.block, indent: paragraph.indent, isEmpty: false), by: delta)
                        set(EntryFormatting.Paragraph(index: index, block: next.block, indent: next.indent), at: location, in: view)
                    }
                }
            case .inline(let mark):
                toggle(mark, in: view)
            }
        }

        private func forEachParagraph(in selection: NSRange, of view: UITextView, _ body: (Int, Int) -> Void) {
            let string = view.textStorage.string as NSString
            var location = selection.location
            var starts: [Int] = []
            repeat {
                let range = FormattingStyle.paragraphRange(at: location, in: string)
                starts.append(range.location)
                location = NSMaxRange(range) + 1
            } while location <= NSMaxRange(selection) && location <= string.length
            for start in starts {
                body(start, FormattingStyle.paragraphIndex(at: start, in: string))
            }
        }

        private func toggle(_ mark: FormattingStyle.Inline, in view: UITextView) {
            let selection = view.selectedRange
            if selection.length > 0 {
                undoable(view) {
                    FormattingStyle.toggle(mark, in: selection, of: view.textStorage, fonts: fonts)
                }
                typingInline = FormattingStyle.inline(at: selection.location + 1, in: view.textStorage)
                report(from: view)
            } else if typingInline.contains(mark) {
                typingInline.remove(mark)
            } else {
                typingInline.insert(mark)
            }
            applyTypingAttributes(view)
            refreshBar(view)
            parent.onFormatted()
        }

        // MARK: "@" names and "#" tags

        private func refreshMention(_ textView: UITextView) {
            guard textView.isEditable, textView.selectedRange.length == 0, textView.markedTextRange == nil,
                  let mention = MentionDetection.mention(in: Self.plain(textView.textStorage), caret: textView.selectedRange.location) else {
                if bar.model.mention != nil { bar.model.mention = nil }
                return
            }
            let rows = parent.mentionRows
            let matches = mention.query.isEmpty
                ? Array(rows.sorted { ($0.lastMentioned ?? .distantPast) > ($1.lastMentioned ?? .distantPast) }.prefix(6))
                : Array(EntitySearch.rank(EntitySearch.filter(rows, segment: .all, query: mention.query), query: mention.query).prefix(6))
            let state = MentionState(query: mention.query, matches: matches)
            if bar.model.mention != state { bar.model.mention = state }
        }

        // The picked name replaces "@" and whatever was typed after it, as plain words.
        func pick(_ pick: MentionPick) {
            guard let view, let mention = MentionDetection.mention(in: Self.plain(view.textStorage), caret: view.selectedRange.location) else { return }
            let name: String
            let target: GraphServices.AddedNameTarget
            switch pick {
            case .existing(let row):
                name = row.name
                target = .existing(row.id)
            case .new(let typed):
                name = typed
                target = .new(name: typed, kind: .person)
            }
            let storage = view.textStorage
            let follows = NSMaxRange(mention.range) < storage.length ? (storage.string as NSString).character(at: NSMaxRange(mention.range)) : 32
            let inserted = follows == 32 || follows == 10 ? name : name + " "
            var attributes = view.typingAttributes
            attributes[.link] = nil
            undoable(view) {
                storage.beginEditing()
                storage.replaceCharacters(in: mention.range, with: NSAttributedString(string: inserted, attributes: attributes))
                storage.endEditing()
                pendingEdit = (mention.range, inserted.utf16.count, false)
                view.selectedRange = NSRange(location: mention.range.location + inserted.utf16.count, length: 0)
                normaliseAfterEdit(view)
                syncSentinel(view)
            }
            report(from: view)
            bar.model.mention = nil
            parent.onMention(target)
        }

        // A "#word" is complete the moment something other than a letter follows it.
        private func noteCompletedTag(before location: Int, typing replacement: String, in textView: UITextView) {
            guard let first = replacement.unicodeScalars.first, !CharacterSet.alphanumerics.contains(first), first != "_",
                  let tag = MentionDetection.completedTag(in: Self.plain(textView.textStorage), endingAt: location) else { return }
            parent.onTag(tag.word)
        }

        // MARK: Links (read mode)

        func apply(links: [EntryNameLinks.Link]) {
            guard let view else { return }
            let storage = view.textStorage
            let whole = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.removeAttribute(.link, range: whole)
            storage.endEditing()
            // Colour goes back to what the paragraph gives it.
            FormattingStyle.applyParagraphs(FormattingStyle.formatting(of: storage), to: storage, fonts: fonts, palette: palette)
            storage.beginEditing()
            for link in links where NSMaxRange(link.range) <= storage.length {
                storage.addAttribute(.link, value: EntryNameLinks.url(for: link.entityID), range: link.range)
                storage.addAttribute(.foregroundColor, value: UIColor(link.kind.color), range: link.range)
            }
            storage.endEditing()
            appliedLinks = links
        }

        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
            guard case .link(let url) = textItem.content, let id = EntryNameLinks.entityID(from: url) else { return defaultAction }
            return UIAction { [weak self] _ in self?.parent.onLinkTap(id) }
        }

        func textView(_ textView: UITextView, menuConfigurationFor textItem: UITextItem, defaultMenu: UIMenu) -> UITextItem.MenuConfiguration? {
            nil
        }

        // MARK: Taps

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view, gesture.state == .ended else { return }
            let point = gesture.location(in: view)
            guard let position = view.closestPosition(to: point) else { return }
            let offset = view.offset(from: view.beginningOfDocument, to: position)
            let paragraph = paragraph(at: offset, in: view)
            // A tap in the gutter of a checklist item ticks it, reading or writing.
            if paragraph.block == .check || paragraph.block == .checked {
                let textStart = view.textContainerInset.left + CGFloat(paragraph.indent) * FormattingStyle.indentStep + FormattingStyle.markerGap
                if point.x < textStart {
                    let ticked = ListEditing.ticked(.init(block: paragraph.block, indent: paragraph.indent, isEmpty: false))
                    set(EntryFormatting.Paragraph(index: paragraph.index, block: ticked.block, indent: ticked.indent), at: offset, in: view)
                    DiagnosticsLog.shared.record("editor.checkboxTicked", ["checked": .bool(ticked.block == .checked), "reading": .bool(!view.isEditable)])
                    return
                }
            }
            guard !view.isEditable else { return }
            // A name's own action already ran for a tap on a link.
            if offset < view.textStorage.length, view.textStorage.attribute(.link, at: offset, effectiveRange: nil) != nil { return }
            parent.onReadTap(offset)
        }
    }
}

// UIKit asks the delegate about a Backspace only when there is a character to delete, so one at the
// very start of the text never reaches it. This hands that keystroke to the coordinator first.
final class EditorTextView: UITextView {
    var backspaceAtStart: () -> Bool = { false }

    override func deleteBackward() {
        if backspaceAtStart() { return }
        super.deleteBackward()
    }
}
