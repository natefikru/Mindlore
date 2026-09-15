import Foundation
import SwiftData
import Testing
@testable import Mindlore

@MainActor
struct EntryTests {
    @Test func freshEntryHasDefaults() {
        let entry = Entry()

        #expect(entry.source == .typed)
        #expect(entry.text.isEmpty)
        #expect(entry.textEditedByUser == false)
        #expect(entry.awaitingText == false)
        #expect(entry.audioData == nil)
        #expect(entry.audioDuration == nil)
        #expect(entry.updatedAt == entry.createdAt)
    }

    @Test func initStoresValues() {
        let id = UUID()
        let created = Date(timeIntervalSince1970: 1_000)
        let audio = Data([1, 2, 3])

        let entry = Entry(id: id, createdAt: created, source: .voice, text: "hello", awaitingText: true, audioData: audio, audioDuration: 4.5)

        #expect(entry.id == id)
        #expect(entry.createdAt == created)
        #expect(entry.updatedAt == created)
        #expect(entry.source == .voice)
        #expect(entry.sourceRaw == "voice")
        #expect(entry.text == "hello")
        #expect(entry.awaitingText)
        #expect(entry.audioData == audio)
        #expect(entry.audioDuration == 4.5)
    }

    @Test(arguments: EntrySource.allCases)
    func sourceRoundTripsThroughRawValue(source: EntrySource) {
        let entry = Entry()
        entry.source = source

        #expect(entry.sourceRaw == source.rawValue)
        #expect(entry.source == source)
    }

    @Test func unknownSourceRawValueFallsBackToTyped() {
        let entry = Entry(source: .voice)
        entry.sourceRaw = "handwritten-from-a-future-version"

        #expect(entry.source == .typed)
    }

    @Test func insertFetchSortedAndDelete() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let older = Entry(createdAt: Date(timeIntervalSince1970: 100), text: "older")
        let newer = Entry(createdAt: Date(timeIntervalSince1970: 200), text: "newer")
        context.insert(older)
        context.insert(newer)
        try context.save()

        let sorted = FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        #expect(try context.fetch(sorted).map(\.text) == ["newer", "older"])

        context.delete(older)
        try context.save()
        #expect(try context.fetch(sorted).map(\.text) == ["newer"])
    }

    @Test func voiceEntriesCanBeFilteredWithPredicate() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        context.insert(Entry(source: .typed, text: "typed"))
        context.insert(Entry(source: .voice, text: "spoken"))
        try context.save()

        let voiceRaw = EntrySource.voice.rawValue
        let voiceOnly = FetchDescriptor<Entry>(predicate: #Predicate { $0.sourceRaw == voiceRaw })
        #expect(try context.fetch(voiceOnly).map(\.text) == ["spoken"])
    }
}
