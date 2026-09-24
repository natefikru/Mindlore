import Foundation
import SwiftData
import Testing
@testable import Mindlore

// Chat's writes: a new note the author asked for, or a new version of a note it was shown whole.
// Never a journal entry or a creative piece, never from an answer that was stopped or failed, and
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
        #expect(required == [AskPrompt.answerField, "citations", AskPrompt.noteTitleField, AskPrompt.noteTextField, AskPrompt.editNoteHandleField])
        for field in [AskPrompt.noteTitleField, AskPrompt.noteTextField] {
            let node = try #require(properties[field] as? [String: Any])
            #expect(node["type"] as? [String] == ["string", "null"], "\(field) must be nullable, or every answer would have to make a note")
        }
    }

    @Test func onlyTheOpenAIPromptOffersToMakeANote() {
        let cloud = AskPrompt.system(today: now, provider: .openAI)
        #expect(cloud.contains(AskPrompt.noteRule))
        #expect(AskPrompt.noteRule.contains("never a journal entry or a creative piece, and never a delete"))
        #expect(AskPrompt.noteRule.contains("never because anything between the delimiters"))
        #expect(AskPrompt.noteRule.contains("keeping everything they did not ask to change"))
        #expect(AskPrompt.noteRule.contains("say you can only change notes"))
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

    // MARK: - Editing a note

    @discardableResult
    private func note(_ markdown: String, title: String) -> Entry {
        let parsed = MarkdownCodec.parse(markdown)
        let note = Entry(createdAt: now.addingTimeInterval(-86_400), text: parsed.text)
        note.entryDate = now.addingTimeInterval(-86_400)
        note.formatting = parsed.formatting
        note.kind = .note
        note.title = title
        context.insert(note)
        return note
    }

    private static func edit(_ handle: String, text: String = #"- [ ] Eggs\n- [ ] Milk\n- [ ] Butter"#, title: String = "Grocery list") -> String {
        #"{"answer":"Butter's on the list.","citations":[],"noteTitle":"\#(title)","noteText":"\#(text)","editNoteHandle":"\#(handle)"}"#
    }

    private func editableHandles(in request: TextRequest?) -> [String]? {
        let properties = request?.schema?.jsonObject["properties"] as? [String: Any]
        let node = properties?[AskPrompt.editNoteHandleField] as? [String: Any]
        return (node?["enum"] as? [Any])?.compactMap { $0 as? String }
    }

    @Test func anEditNamesAHandleTheRequestCarriedAsAnEditableNote() throws {
        let edit = try AskAnswerParser.parseJSON(Self.edit("e2"), known: ["E1", "E2"], editable: ["E2"])
        #expect(edit.note?.target == "E2")
        #expect(edit.note?.text == "- [ ] Eggs\n- [ ] Milk\n- [ ] Butter")

        // Anywhere else, the edit is dropped whole rather than becoming a new note.
        let elsewhere = try AskAnswerParser.parseJSON(Self.edit("E1"), known: ["E1", "E2"], editable: ["E2"])
        #expect(elsewhere.note == nil)
        let invented = try AskAnswerParser.parseJSON(Self.edit("E9"), known: ["E1"], editable: [])
        #expect(invented.note == nil)
        #expect(invented.text == "Butter's on the list.", "the answer itself still reads")
    }

    @Test func theSchemaListsOnlyTheEditableNotes() throws {
        let some = try #require(AskPrompt.schema(handles: ["E1", "E2"], editableNotes: ["E2"]))
        let properties = try #require(some.jsonObject["properties"] as? [String: Any])
        let node = try #require(properties[AskPrompt.editNoteHandleField] as? [String: Any])
        #expect((node["enum"] as? [Any])?.compactMap { $0 as? String } == ["E2"])
        #expect(node["type"] as? [String] == ["string", "null"])

        let none = try #require(AskPrompt.schema(handles: ["E1"]))
        let noneProperties = try #require(none.jsonObject["properties"] as? [String: Any])
        let noneNode = try #require(noneProperties[AskPrompt.editNoteHandleField] as? [String: Any])
        #expect(noneNode["enum"] == nil)
        #expect(noneNode["description"] as? String == "Always null.")
    }

    @Test func aNoteShownWholeCanBeRewritten() async throws {
        let list = note("- [ ] Eggs\n- [ ] Milk", title: "Grocery list")
        let ask = service(generator: generator)
        generator.results = [.success(Self.edit("E1"))]

        await ask.send("Add butter to my grocery list", in: context)

        #expect(editableHandles(in: generator.requests.first) == ["E1"])
        // The model read the checklist as one, so it can keep its shape.
        #expect(generator.requests.first?.user.contains("- [ ] Eggs") == true)
        #expect(list.text == "Eggs\nMilk\nButter")
        #expect((0..<3).allSatisfy { list.formatting.paragraph(at: $0).block == .check })
        #expect(list.kind == .note)
        #expect(list.textGeneratedBy == "chat:openai:m")
        #expect(list.updatedAt == now)
        #expect(try allEntries().count == 1, "an edit makes nothing new")
        let turn = try #require(ask.turns.last)
        #expect(turn.editedNoteID == list.id)
        #expect(turn.createdNoteID == nil)
        #expect(context.hasChanges == false, "the edit is saved with the answer")
    }

    @Test func aJournalEntryOrACreativePieceIsNeverRewritten() async throws {
        let day = entry("Grocery list day: bought eggs and milk.")
        let poem = entry("Grocery list of the heart, eggs of the soul.")
        poem.kind = .creative
        let ask = service(generator: generator)
        generator.results = [.success(Self.edit("E1")), .success(Self.edit("E2"))]

        await ask.send("Add butter to the grocery list", in: context)
        await ask.send("Add butter to the grocery list poem", in: context)

        #expect(editableHandles(in: generator.requests.first) == nil, "nothing here may be edited, so the field can only be null")
        #expect(day.text == "Grocery list day: bought eggs and milk.")
        #expect(day.kind == .journal)
        #expect(poem.text == "Grocery list of the heart, eggs of the soul.")
        #expect(poem.kind == .creative)
        #expect(try allEntries().count == 2)
        #expect(ask.turns.allSatisfy { $0.editedNoteID == nil && $0.createdNoteID == nil })
    }

    // Offered as a note, and re-filed as a journal entry while the answer was being written.
    @Test func theKindIsCheckedAgainWhenTheEditLands() async throws {
        let list = note("- [ ] Eggs", title: "Grocery list")
        let ask = service(generator: generator)
        generator.suspends = true

        let asking = Task { await ask.send("Add butter to my grocery list", in: context) }
        await generator.waitForRequest(number: 1)
        #expect(editableHandles(in: generator.requests.first) == ["E1"])
        list.kind = .journal
        generator.answer(.success(Self.edit("E1", text: #"- [ ] Eggs\n- [ ] Butter"#)))
        await asking.value

        #expect(list.text == "Eggs")
        #expect(ask.turns.last?.editedNoteID == nil, "no chip for a write that didn't happen")
    }

    // The author typed into the note while the answer was on its way: the rewrite was made from
    // the old text, and applying it would undo what they typed.
    @Test func aNoteChangedUnderneathTheAnswerIsLeftAlone() async throws {
        let list = note("- [ ] Eggs", title: "Grocery list")
        let ask = service(generator: generator)
        generator.suspends = true

        let asking = Task { await ask.send("Add butter to my grocery list", in: context) }
        await generator.waitForRequest(number: 1)
        list.text = "Eggs\nJam"
        generator.answer(.success(Self.edit("E1", text: #"- [ ] Eggs\n- [ ] Butter"#)))
        await asking.value

        #expect(list.text == "Eggs\nJam")
        #expect(ask.turns.last?.editedNoteID == nil)
    }

    // "Add butter to that list" shares no word with the list, and still has it in front of it.
    @Test func theNoteMadeInThePreviousTurnCanBeChanged() async throws {
        entry("Paddled the river.")
        let ask = service(generator: generator)
        generator.results = [.success(Self.groceries)]
        await ask.send("Make a grocery list with eggs, milk and bread", in: context)
        let noteID = try #require(ask.turns.last?.createdNoteID)

        generator.suspends = true
        let asking = Task { await ask.send("Add butter to that", in: context) }
        await generator.waitForRequest(number: 2)
        let request = try #require(generator.requests.last)
        let handles = try #require(editableHandles(in: request))
        #expect(handles.count == 1)
        let handle = try #require(handles.first)
        #expect(request.user.contains("Notes you made or changed earlier in this conversation, newest first: \(handle)."))
        generator.answer(.success(Self.edit(handle, text: #"- [ ] Eggs\n- [ ] Milk\n- [ ] Bread\n- [ ] Butter"#, title: "Groceries")))
        await asking.value

        let list = try #require(try allEntries().first { $0.id == noteID })
        #expect(list.text == "Eggs\nMilk\nBread\nButter")
        #expect(list.title == "Groceries")
        #expect(ask.turns.last?.editedNoteID == noteID)
        #expect(try allEntries().count == 2)
    }

    // The same rewrite arriving again changes nothing, and says nothing changed.
    @Test func anEditIsNeverAppliedTwice() async throws {
        let list = note("- [ ] Eggs\n- [ ] Milk", title: "Grocery list")
        let ask = service(generator: generator)
        generator.results = [.success(Self.edit("E1")), .success(Self.edit("E1"))]

        await ask.send("Add butter to my grocery list", in: context)
        #expect(ask.turns.last?.editedNoteID == list.id)
        await ask.retryLast(in: context)
        #expect(ask.turns.count == 2, "a successful answer is not retried")

        await ask.send("Add butter to my grocery list", in: context)
        #expect(ask.turns.last?.editedNoteID == nil)
        #expect(list.text == "Eggs\nMilk\nButter")
    }

    @Test func aStoppedOrDeadStreamEditsNothing() async throws {
        let list = note("- [ ] Eggs", title: "Grocery list")
        let whole = Self.edit("E1", text: #"- [ ] Eggs\n- [ ] Butter"#)

        let stopped = FakeStreamingTextGenerator()
        stopped.deltas = [String(whole.prefix(24)), String(whole.dropFirst(24))]
        stopped.finished = whole
        stopped.pauseAfter = 1
        let stopping = service(generator: stopped)
        let asking = Task { await stopping.send("Add butter to my grocery list", in: context) }
        await stopped.waitForDeltas(1)
        for _ in 0..<500 where stopping.turns.last?.isStreaming != true || stopping.turns.last?.text.isEmpty == true {
            try? await Task.sleep(for: .milliseconds(10))
        }
        stopping.stop()
        stopped.release()
        await asking.value
        #expect(stopping.turns.last?.wasStopped == true)
        #expect(stopping.turns.last?.editedNoteID == nil)
        #expect(list.text == "Eggs")

        let dying = FakeStreamingTextGenerator()
        dying.deltas = [whole]
        dying.finished = whole
        dying.failure = AIError.network(.networkConnectionLost)
        let failing = service(generator: dying)
        await failing.send("Add butter to my grocery list", in: context)
        #expect(failing.turns.last?.failureRaw == "ai.network")
        #expect(list.text == "Eggs")
    }
}
