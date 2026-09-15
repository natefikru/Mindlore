import Foundation
import SwiftData

extension Entry {
    var isBlank: Bool {
        title.isEmpty && text.isEmpty && audioData == nil && (pages ?? []).isEmpty
    }

    func userDidEditText() {
        awaitingText = false
        if textWasGenerated {
            textEditedByUser = true
        }
    }

    // Refuses once the user has typed into the entry, so generated text never overwrites theirs.
    @discardableResult
    func applyGeneratedText(_ generated: String) -> Bool {
        guard awaitingText else { return false }
        text = generated
        textWasGenerated = true
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
