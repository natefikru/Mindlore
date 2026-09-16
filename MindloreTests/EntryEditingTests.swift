import Foundation
import SwiftData
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

    @Test func clearingGeneratedTextKeepsTheRecordingEvenWhenRecordingsAreNotKept() {
        let entry = Entry(source: .voice, awaitingText: true, audioData: Data([1]))
        entry.applyGeneratedText("bad transcription")
        entry.text = ""
        entry.userDidEditText()

        entry.discardAudioIfNotKept(keepAudio: false)

        #expect(entry.audioData != nil)
    }

    @Test func closingKeepsAVoiceEntryWhoseGeneratedTextWasCleared() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let entry = Entry(source: .voice, awaitingText: true, audioData: Data([1]))
        container.mainContext.insert(entry)
        entry.applyGeneratedText("bad transcription")
        entry.text = ""
        entry.userDidEditText()

        let deleted = Entry.editorDidClose(entry, keepAudio: false, in: container.mainContext)
        try container.mainContext.save()

        #expect(deleted == false)
        #expect(try container.mainContext.fetch(FetchDescriptor<Entry>()).count == 1)
        #expect(entry.audioData != nil)
    }

    @Test func closingRemovesAudioButKeepsTheEntryWhenGeneratedTextRemains() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let entry = Entry(source: .voice, awaitingText: true, audioData: Data([1]))
        container.mainContext.insert(entry)
        entry.applyGeneratedText("kept text")

        let deleted = Entry.editorDidClose(entry, keepAudio: false, in: container.mainContext)

        #expect(deleted == false)
        #expect(entry.audioData == nil)
        #expect(entry.text == "kept text")
    }

    @Test func closingDeletesOnlyBlankEntries() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let blankTyped = Entry(text: "")
        let written = Entry(text: "hello")
        let waiting = Entry(source: .voice, awaitingText: true, audioData: Data([1]))
        [blankTyped, written, waiting].forEach(context.insert)
        try context.save()

        #expect(Entry.editorDidClose(blankTyped, keepAudio: false, in: context))
        #expect(Entry.editorDidClose(written, keepAudio: false, in: context) == false)
        #expect(Entry.editorDidClose(waiting, keepAudio: false, in: context) == false)
        try context.save()

        #expect(Set(try context.fetch(FetchDescriptor<Entry>()).map(\.id)) == [written.id, waiting.id])
    }

    @Test func blankMeansNoTitleTextAudioOrPages() throws {
        #expect(Entry().isBlank)
        #expect(Entry(text: " ").isBlank == false)
        #expect(Entry(source: .voice, awaitingText: true, audioData: Data([1])).isBlank == false)

        let titled = Entry()
        titled.title = "Just a title"
        #expect(titled.isBlank == false)

        let container = try ModelContainerFactory.make(.inMemory)
        let photo = Entry(source: .photo)
        container.mainContext.insert(photo)
        let page = EntryPage(index: 0, imageData: Data([1]), thumbnailData: nil, pixelWidth: 1, pixelHeight: 1, origin: .camera)
        page.entry = photo
        #expect(photo.isBlank == false)
    }

    @Test func closingKeepsATitleOnlyEntry() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let titled = Entry()
        titled.title = "Groceries"
        context.insert(titled)

        #expect(Entry.editorDidClose(titled, keepAudio: true, in: context) == false)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Entry>()) == 1)
    }
}
