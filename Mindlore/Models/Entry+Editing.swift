import Foundation
import SwiftData

extension Entry {
    var isBlank: Bool {
        title.isEmpty && text.isEmpty && audioData == nil && (pages ?? []).isEmpty
    }

    func userDidEditText() {
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
