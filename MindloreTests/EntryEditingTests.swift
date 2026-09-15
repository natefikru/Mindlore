import Foundation
import Testing
@testable import Mindlore

@MainActor
struct EntryEditingTests {
    @Test func generatedTextAppliesWhileAwaiting() {
        let entry = Entry(source: .voice, awaitingText: true, audioData: Data([1]))

        #expect(entry.applyGeneratedText("from speech"))
        #expect(entry.text == "from speech")
        #expect(entry.textWasGenerated)
        #expect(entry.awaitingText == false)
        #expect(entry.textEditedByUser == false)
    }

    @Test func generatedTextNeverOverwritesUserTyping() {
        let entry = Entry(source: .voice, awaitingText: true, audioData: Data([1]))
        entry.text = "I typed this myself"
        entry.userDidEditText()

        #expect(entry.applyGeneratedText("from speech") == false)
        #expect(entry.text == "I typed this myself")
        #expect(entry.textWasGenerated == false)
    }

    @Test func generatedTextIsNotAppliedTwice() {
        let entry = Entry(source: .voice, awaitingText: true, audioData: Data([1]))
        entry.applyGeneratedText("first result")

        #expect(entry.applyGeneratedText("second result") == false)
        #expect(entry.text == "first result")
    }

    @Test func typingIntoATypedEntryIsNotMarkedAsEditingGeneratedText() {
        let entry = Entry(text: "hello")
        entry.text = "hello there"
        entry.userDidEditText()

        #expect(entry.textEditedByUser == false)
        #expect(entry.awaitingText == false)
    }

    @Test func typingWhileAwaitingClearsTheFlagWithoutMarkingAnEdit() {
        let entry = Entry(source: .voice, awaitingText: true, audioData: Data([1]))
        entry.text = "t"
        entry.userDidEditText()

        #expect(entry.awaitingText == false)
        #expect(entry.textEditedByUser == false)

        entry.text = "typed"
        entry.userDidEditText()
        #expect(entry.textEditedByUser == false)
    }

    @Test func editingGeneratedTextIsRecorded() {
        let entry = Entry(source: .voice, awaitingText: true, audioData: Data([1]))
        entry.applyGeneratedText("i went to the see")
        entry.text = "I went to the sea"
        entry.userDidEditText()

        #expect(entry.textEditedByUser)
    }

    @Test func removeAudioClearsBothFields() {
        let entry = Entry(source: .voice, audioData: Data([1, 2]), audioDuration: 3)
        entry.removeAudio()

        #expect(entry.audioData == nil)
        #expect(entry.audioDuration == nil)
    }

    @Test func audioIsDiscardedOnCloseOnlyWhenNotKeptAndTextWasGenerated() {
        let generated = Entry(source: .voice, awaitingText: true, audioData: Data([1]), audioDuration: 2)
        generated.applyGeneratedText("hello")

        generated.discardAudioIfNotKept(keepAudio: true)
        #expect(generated.audioData != nil)

        generated.discardAudioIfNotKept(keepAudio: false)
        #expect(generated.audioData == nil)
        #expect(generated.audioDuration == nil)
    }

    @Test func audioIsKeptWhenTextWasTypedOrStillPending() {
        let pending = Entry(source: .voice, awaitingText: true, audioData: Data([1]))
        pending.discardAudioIfNotKept(keepAudio: false)
        #expect(pending.audioData != nil)

        let typedInstead = Entry(source: .voice, awaitingText: true, audioData: Data([1]))
        typedInstead.text = "typed"
        typedInstead.userDidEditText()
        typedInstead.discardAudioIfNotKept(keepAudio: false)
        #expect(typedInstead.audioData != nil)
    }

    @Test func blankMeansNoTextAndNoAudio() {
        #expect(Entry().isBlank)
        #expect(Entry(text: " ").isBlank == false)
        #expect(Entry(source: .voice, awaitingText: true, audioData: Data([1])).isBlank == false)
    }
}
