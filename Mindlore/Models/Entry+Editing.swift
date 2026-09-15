import Foundation
import SwiftData

extension Entry {
    var isBlank: Bool {
        text.isEmpty && audioData == nil
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

    // Called when the user leaves an entry, the first point they've seen its generated text.
    func discardAudioIfNotKept(keepAudio: Bool) {
        guard !keepAudio, textWasGenerated, audioData != nil else { return }
        removeAudio()
    }

    static func delete(_ entry: Entry, in context: ModelContext) {
        context.delete(entry)
    }
}
