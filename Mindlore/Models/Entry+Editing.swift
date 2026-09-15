import Foundation
import SwiftData

extension Entry {
    var isBlank: Bool {
        title.isEmpty && text.isEmpty && audioData == nil && (pages ?? []).isEmpty
    }

    func userDidEditText() {
        // Typing over text that was still coming (or never came) makes the entry the user's own
        // writing, which waits for Done like any typed entry.
        if !automaticAIPassUsed && (awaitingText || (source == .photo && !textWasGenerated)) {
            isDraft = true
        }
        awaitingText = false
        textFallbackReasonRaw = nil
        if textWasGenerated {
            textEditedByUser = true
        }
    }

    // Refuses once the user has typed into the entry, so generated text never overwrites theirs.
    @discardableResult
    func applyGeneratedText(_ generated: String, generatedBy: String? = nil) -> Bool {
        guard awaitingText else { return false }
        text = generated
        textWasGenerated = true
        textGeneratedBy = generatedBy
        awaitingText = false
        return true
    }

    func removeAudio() {
        audioData = nil
        audioDuration = nil
    }

    // The first point the user has seen generated text. Audio goes only if text remains,
    // otherwise removing it would leave a blank entry that then gets deleted.
    func discardAudioIfNotKept(keepAudio: Bool) {
        guard !keepAudio, textWasGenerated, !text.isEmpty, audioData != nil else { return }
        removeAudio()
    }

    // Returns true if the entry was deleted because nothing was left in it.
    @discardableResult
    static func editorDidClose(_ entry: Entry, keepAudio: Bool, in context: ModelContext) -> Bool {
        entry.discardAudioIfNotKept(keepAudio: keepAudio)
        guard entry.isBlank else { return false }
        delete(entry, in: context)
        return true
    }

    static func delete(_ entry: Entry, in context: ModelContext) {
        context.delete(entry)
    }
}

// MARK: - Drafts

extension Entry {
    // Returns false if the entry wasn't a draft. The caller fires the automatic AI pass.
    @discardableResult
    func finishDraft() -> Bool {
        guard isDraft else { return false }
        isDraft = false
        return true
    }
}

// MARK: - Title

extension Entry {
    static let derivedTitleLength = 60

    // What lists and the editor show: the title, or the first line of text cut at a word.
    var displayTitle: String {
        if !title.isEmpty { return title }
        let firstLine = text.split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        guard !firstLine.isEmpty else { return "Untitled" }
        guard firstLine.count > Self.derivedTitleLength else { return firstLine }
        let cut = firstLine.prefix(Self.derivedTitleLength)
        if let space = cut.lastIndex(of: " ") {
            return cut[..<space].trimmingCharacters(in: .whitespaces) + "…"
        }
        return cut + "…"
    }

    // A generated title only fills an empty title or replaces another generated one.
    @discardableResult
    func applyGeneratedTitle(_ generated: String) -> Bool {
        guard !generated.isEmpty, title.isEmpty || titleWasGenerated else { return false }
        title = generated
        titleWasGenerated = true
        return true
    }

    // Clearing the field hands the title back to generation, since an empty title can be filled.
    func userDidEditTitle(_ newTitle: String) {
        title = newTitle
        titleWasGenerated = false
    }
}

// MARK: - Entry date

extension Entry {
    // The user picked a day. Time isn't meaningful for a backdated entry, so it's noon and hidden.
    func setEntryDay(_ day: Date, calendar: Calendar = .current) {
        entryDate = EntryDates.noon(of: day, calendar: calendar)
        entryDateIsDayOnly = true
        if let suggestedEntryDate, EntryDates.isSameDay(suggestedEntryDate, entryDate, calendar: calendar) {
            self.suggestedEntryDate = nil
        }
    }

    func useOriginalEntryDate() {
        entryDate = createdAt
        entryDateIsDayOnly = false
    }

    // Returns false when the suggestion is the entry's current day, which isn't worth asking about.
    @discardableResult
    func storeSuggestedEntryDate(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard !EntryDates.isSameDay(date, entryDate, calendar: calendar) else { return false }
        suggestedEntryDate = EntryDates.noon(of: date, calendar: calendar)
        return true
    }

    func acceptSuggestedEntryDate(calendar: Calendar = .current) {
        guard let suggestedEntryDate else { return }
        setEntryDay(suggestedEntryDate, calendar: calendar)
        self.suggestedEntryDate = nil
    }

    func dismissSuggestedEntryDate() {
        suggestedEntryDate = nil
    }

    func shouldShowDateSuggestion(calendar: Calendar = .current) -> Bool {
        guard let suggestedEntryDate else { return false }
        return !EntryDates.isSameDay(suggestedEntryDate, entryDate, calendar: calendar)
    }

    // True when the entry's day was changed away from the day it was added.
    func entryDateDiffersFromCreation(calendar: Calendar = .current) -> Bool {
        entryDateIsDayOnly && !EntryDates.isSameDay(entryDate, createdAt, calendar: calendar)
    }
}

// MARK: - Cleaned-up text (voice entries)

extension Entry {
    // Cleanup only replaces the exact text it was made from, so it can never overwrite newer edits.
    // The first pre-cleanup text is kept for "Revert to original", however many cleanups follow.
    @discardableResult
    func applyCleanedText(_ cleaned: String) -> Bool {
        guard source == .voice, let insights, !cleaned.isEmpty, cleaned != text,
              TextHash.of(text) == insights.sourceTextHash else { return false }
        if originalText == nil {
            originalText = text
        }
        text = cleaned
        insights.appliedTextHash = TextHash.of(cleaned)
        return true
    }

    // True when the user has typed since the cleanup was applied, so reverting would discard those edits.
    var textChangedSinceCleanup: Bool {
        guard originalText != nil, let applied = insights?.appliedTextHash else { return false }
        return TextHash.of(text) != applied
    }

    @discardableResult
    func revertToOriginalText() -> Bool {
        guard let originalText else { return false }
        text = originalText
        self.originalText = nil
        insights?.appliedTextHash = nil
        return true
    }
}
