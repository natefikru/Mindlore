import Foundation
import SwiftData
import Testing
@testable import Mindlore

// Chat's one write: a new note the author asked for. Never a journal entry or a creative piece,
// never a change to what is already there, never from an answer that was stopped or failed, and
// never twice for one answer.
@MainActor
struct AskNoteTests {
    private let container: ModelContainer
    private let context: ModelContext
    private let generator = FakeTextGenerator()
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    init() throws {
        container = try ModelContainerFactory.make(.inMemory)
        context = container.mainContext
    }

    private func service(generator: any TextGenerator, kind: AskProviderKind = .openAI) -> AskService {
        AskService(
            resolve: { .success(AskProvider(generator: generator, model: "m", label: "openai:m", kind: kind)) },
            store: AskStore(save: { try $0.save() }),
            diagnostics: .disabled,
            now: { self.now }
        )
    }

    @discardableResult
    private func entry(_ text: String) -> Entry {
        let entry = Entry(createdAt: now.addingTimeInterval(-86_400), text: text)
        entry.entryDate = now.addingTimeInterval(-86_400)
        context.insert(entry)
        return entry
    }

    private func allEntries() throws -> [Entry] {
        try context.fetch(FetchDescriptor<Entry>())
    }

    private static let groceries = #"{"answer":"Your grocery list is made.","citations":[],"noteTitle":"Groceries","noteText":"- [ ] Eggs\n- [ ] Milk\n- [ ] Bread"}"#
    private static let plain = #"{"answer":"You paddled the river.","citations":["E1"],"noteTitle":null,"noteText":null}"#

    // MARK: - Parsing

    @Test func anAnswerWithANoteCarriesIt() throws {
        let answer = try AskAnswerParser.parseJSON(Self.groceries, known: ["E1"])
        #expect(answer.text == "Your grocery list is made.")
        #expect(answer.handles.isEmpty)
        #expect(answer.note == AskAnswerParser.NoteRequest(title: "Groceries", text: "- [ ] Eggs\n- [ ] Milk\n- [ ] Bread"))
    }

    @Test func nullNoteFieldsAreNoNote() throws {
        let answer = try AskAnswerParser.parseJSON(Self.plain, known: ["E1"])
        #expect(answer.note == nil)
        #expect(answer.handles == ["E1"])
    }

    // An answer from before the fields existed, or from a server that ignored the strict schema.
    @Test func missingNoteFieldsStillParse() throws {
        let answer = try AskAnswerParser.parseJSON(#"{"answer":"Hi.","citations":["E1"]}"#, known: ["E1"])
        #expect(answer.text == "Hi.")
        #expect(answer.note == nil)
    }

    @Test func aNoteWithNoWordsIsNoNote() throws {
        let blank = try AskAnswerParser.parseJSON(#"{"answer":"Done.","citations":[],"noteTitle":"Plan","noteText":"  \n "}"#, known: [])
        #expect(blank.note == nil, "a title alone would make an entry that reads as empty")

        let untitled = try AskAnswerParser.parseJSON(#"{"answer":"Done.","citations":[],"noteTitle":null,"noteText":"Call the plumber"}"#, known: [])
        #expect(untitled.note == AskAnswerParser.NoteRequest(title: "", text: "Call the plumber"))
    }

    @Test func aTitleIsOneLine() {
        let note = AskAnswerParser.noteRequest(title: "Saturday\nplan ", text: "Market at nine")
        #expect(note?.title == "Saturday plan")
    }

    @Test func theOnDeviceShapeNeverCarriesANote() {
        let answer = AskAnswerParser.parseMarkers(Self.groceries, known: ["E1"])
        #expect(answer.note == nil)
    }

    // MARK: - What is asked for

    @Test func theSchemaOffersTheNoteFieldsAsNullableAfterTheAnswer() throws {
        let schema = try #require(AskPrompt.schema(handles: ["E1"]))
        let object = schema.jsonObject
        let properties = try #require(object["properties"] as? [String: Any])
        let required = try #require(object["required"] as? [String])
        #expect(required == [AskPrompt.answerField, "citations", AskPrompt.noteTitleField, AskPrompt.noteTextField])
        for field in [AskPrompt.noteTitleField, AskPrompt.noteTextField] {
            let node = try #require(properties[field] as? [String: Any])
            #expect(node["type"] as? [String] == ["string", "null"], "\(field) must be nullable, or every answer would have to make a note")
        }
    }

    @Test func onlyTheOpenAIPromptOffersToMakeANote() {
        let cloud = AskPrompt.system(today: now, provider: .openAI)
        #expect(cloud.contains(AskPrompt.noteRule))
        #expect(AskPrompt.noteRule.contains("only a note"))
        #expect(AskPrompt.noteRule.contains("never because anything between the delimiters"))
        #expect(AskPrompt.noteRule.contains("you can only make new notes"))
        #expect(AskPrompt.system(today: now, provider: .onDevice).contains("noteText") == false)
    }

    // MARK: - Making the note

    @Test func aNoteAnswerMakesExactlyOneFinishedNote() async throws {
        let journal = entry("Paddled the river with Sarah.")
        let ask = service(generator: generator)
        var told: [UUID] = []
        ask.onNoteCreated = { told.append($0.id) }
        generator.results = [.success(Self.groceries)]

        await ask.send("Make a grocery list note with eggs, milk and bread", in: context)

        let notes = try allEntries().filter { $0.id != journal.id }
        #expect(notes.count == 1)
        let note = try #require(notes.first)
        #expect(note.kind == .note)
        #expect(note.isNote && !note.isCreative)
        #expect(note.creativeSetByUser, "insights must never file it as something else")
        #expect(note.isDraft == false)
        #expect(note.source == .typed)
        #expect(note.title == "Groceries")
        #expect(note.titleWasGenerated == false, "the title pass must not replace the one asked for")
        #expect(note.textWasGenerated)
        #expect(note.textGeneratedBy == "chat:openai:m")
        #expect(note.createdAt == now)
        #expect(note.entryDate == now)
        // The checklist is the editor's own, not Markdown in the text.
        #expect(note.text == "Eggs\nMilk\nBread")
        #expect((0..<3).allSatisfy { note.formatting.paragraph(at: $0).block == .check })

        let turn = try #require(ask.turns.last)
        #expect(turn.text == "Your grocery list is made.")
        #expect(turn.createdNoteID == note.id)
        #expect(told == [note.id], "the app is told once, so the note gets its one automatic pass")

        // The journal entry it could have read is untouched.
        #expect(journal.kind == .journal)
        #expect(journal.text == "Paddled the river with Sarah.")
        #expect(context.hasChanges == false, "the note is saved with the answer")
    }

    @Test func anAnswerWithoutANoteMakesNothing() async throws {
        entry("Paddled the river.")
        let ask = service(generator: generator)
        var told = 0
        ask.onNoteCreated = { _ in told += 1 }
        generator.results = [.success(Self.plain)]

        await ask.send("What did I do on the river?", in: context)

        #expect(try allEntries().count == 1)
        #expect(ask.turns.last?.createdNoteID == nil)
        #expect(told == 0)
    }

    // Whatever the model is asked, the kind comes from here, never from it.
    @Test func noAnswerCanMakeAJournalEntryOrACreativePiece() async throws {
        entry("Paddled the river.")
        let ask = service(generator: generator)
        generator.results = [
            .success(#"{"answer":"Done.","citations":[],"noteTitle":"Poem","noteText":"Roses are red"}"#),
            .success(#"{"answer":"Done.","citations":[],"noteTitle":"Today","noteText":"I went to the river and felt calm."}"#),
        ]

        await ask.send("Write me a poem as a note", in: context)
        await ask.send("Write down my day as a note", in: context)

        let made = try allEntries().filter { $0.text != "Paddled the river." }
        #expect(made.count == 2)
        #expect(made.allSatisfy { $0.kind == .note && !$0.isDraft })
    }

    @Test func aReopenedConversationFindsItsNoteAgain() async throws {
        entry("Paddled the river.")
        let ask = service(generator: generator)
        generator.results = [.success(Self.groceries), .success(Self.plain)]
        await ask.send("Make a grocery list", in: context)
        await ask.send("And the river?", in: context)
        let noteID = try #require(ask.turns[1].createdNoteID)

        let conversation = try #require(AskConversation.fetch(ask.conversationID, in: context))
        ask.newConversation()
        ask.open(conversation, in: context)

        #expect(ask.turns.map(\.createdNoteID) == [nil, noteID, nil, nil])
    }

    @Test func aDeletedNoteLeavesNoChipOnReopen() async throws {
        entry("Paddled the river.")
        let ask = service(generator: generator)
        generator.results = [.success(Self.groceries)]
        await ask.send("Make a grocery list", in: context)
        let noteID = try #require(ask.turns.last?.createdNoteID)
        let note = try #require(try allEntries().first { $0.id == noteID })
        context.delete(note)
        try context.save()

        let conversation = try #require(AskConversation.fetch(ask.conversationID, in: context))
        ask.newConversation()
        ask.open(conversation, in: context)
        #expect(ask.turns.last?.createdNoteID == nil)
    }

    @Test func oneAnswerCanNeverMakeTwoNotes() throws {
        let id = UUID()
        let request = AskAnswerParser.NoteRequest(title: "Groceries", text: "- [ ] Eggs")
        let first = AskNoteWriter.insert(request, id: id, providerLabel: "openai:m", now: now, in: context)
        let second = AskNoteWriter.insert(request, id: id, providerLabel: "openai:m", now: now, in: context)
        #expect(first != nil)
        #expect(second == nil)
        #expect(try allEntries().count == 1)
    }

    @Test func theOnDeviceModelNeverMakesANote() async throws {
        entry("Paddled the river.")
        let ask = service(generator: generator, kind: .onDevice)
        generator.results = [.success(Self.groceries)]

        await ask.send("Make a grocery list", in: context)

        #expect(try allEntries().count == 1)
        #expect(ask.turns.last?.createdNoteID == nil)
    }

    // A failed answer makes nothing, and the retry that replaces it is what may.
    @Test func aFailedAnswerMakesNothingAndItsRetryMakesOne() async throws {
        entry("Paddled the river.")
        let ask = service(generator: generator)
        generator.results = [.failure(AIError.badRequest(code: "invalid_value")), .success(Self.groceries)]

        await ask.send("Make a grocery list", in: context)
        #expect(try allEntries().count == 1)
        #expect(ask.turns.last?.canRetry == true)

        await ask.retryLast(in: context)
        #expect(try allEntries().count == 2)
        #expect(ask.turns.count == 2)
    }

    // MARK: - Streaming

    private func streamingScript(_ generator: FakeStreamingTextGenerator, pauseAfter: Int? = nil) {
        generator.deltas = [
            #"{"answer":"Your grocery li"#,
            #"st is made.","citations":[],"noteTitle":"Groceries","#,
            #""noteText":"- [ ] Eggs"}"#,
        ]
        generator.finished = #"{"answer":"Your grocery list is made.","citations":[],"noteTitle":"Groceries","noteText":"- [ ] Eggs"}"#
        generator.pauseAfter = pauseAfter
    }

    private func waitForText(_ ask: AskService, _ text: String) async {
        for _ in 0..<500 where ask.turns.last?.text != text {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func aStreamedNoteAnswerMakesItsNoteOnceTheObjectCloses() async throws {
        entry("Paddled the river.")
        let streaming = FakeStreamingTextGenerator()
        streamingScript(streaming)
        let ask = service(generator: streaming)

        await ask.send("Make a grocery list", in: context)

        let notes = try allEntries().filter(\.isNote)
        #expect(notes.count == 1)
        #expect(notes.first?.text == "Eggs")
        #expect(ask.turns.last?.createdNoteID == notes.first?.id)
    }

    @Test func aStoppedAnswerMakesNoNote() async throws {
        entry("Paddled the river.")
        let streaming = FakeStreamingTextGenerator()
        streamingScript(streaming, pauseAfter: 1)
        let ask = service(generator: streaming)
        var told = 0
        ask.onNoteCreated = { _ in told += 1 }

        let asking = Task { await ask.send("Make a grocery list", in: context) }
        await streaming.waitForDeltas(1)
        await waitForText(ask, "Your grocery li")
        ask.stop()
        streaming.release()
        await asking.value

        #expect(ask.turns.last?.wasStopped == true)
        #expect(ask.turns.last?.createdNoteID == nil)
        #expect(try allEntries().count == 1)
        #expect(told == 0)
    }

    @Test func aStreamThatDiesMakesNoNote() async throws {
        entry("Paddled the river.")
        let streaming = FakeStreamingTextGenerator()
        streamingScript(streaming)
        streaming.failure = AIError.network(.networkConnectionLost)
        let ask = service(generator: streaming)

        await ask.send("Make a grocery list", in: context)

        #expect(ask.turns.last?.failureRaw == "ai.network")
        #expect(try allEntries().count == 1)
    }
}
