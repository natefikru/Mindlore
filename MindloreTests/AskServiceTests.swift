import Foundation
import SwiftData
import Testing
@testable import Mindlore

@MainActor
struct AskServiceTests {
    private let container: ModelContainer
    private let context: ModelContext
    private let generator = FakeTextGenerator()
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    init() throws {
        container = try ModelContainerFactory.make(.inMemory)
        context = container.mainContext
    }

    private func service(
        kind: AskProviderKind = .openAI,
        failure: AIJobFailure? = nil,
        includesOlder: Bool = false,
        aiEnabledAt: Date? = nil
    ) -> AskService {
        AskService(
            resolve: { [generator] in
                if let failure { return .failure(failure) }
                return .success(AskProvider(generator: generator, model: "m", label: "openai:m", kind: kind))
            },
            includesOlderEntries: { includesOlder },
            aiEnabledAt: { aiEnabledAt },
            store: AskStore(save: { try $0.save() }),
            diagnostics: .disabled,
            now: { self.now }
        )
    }

    @discardableResult
    private func entry(_ text: String, daysAgo: Double = 1, createdAt: Date? = nil) -> Entry {
        let entry = Entry(createdAt: createdAt ?? now.addingTimeInterval(-daysAgo * 86_400), text: text)
        entry.entryDate = now.addingTimeInterval(-daysAgo * 86_400)
        context.insert(entry)
        return entry
    }

    private func answer(_ text: String, citing handles: [String]) -> Result<String, any Error> {
        let citations = handles.map { "\"\($0)\"" }.joined(separator: ",")
        return .success(#"{"answer":"\#(text)","citations":[\#(citations)]}"#)
    }

    @Test func aConversationIsSavedOnlyAfterItsFirstAnswer() async throws {
        entry("Paddled the river with Sarah.")
        let ask = service()
        generator.results = [answer("You paddled the river.", citing: ["E1"])]

        #expect(AskConversation.all(in: context).isEmpty)
        await ask.send("What did I do on the river?", in: context)

        let conversations = AskConversation.all(in: context)
        #expect(conversations.count == 1)
        #expect(conversations.first?.title == "What did I do on the river?")
        #expect(AskMessage.all(forConversation: ask.conversationID, in: context).map(\.role) == [.user, .assistant])
        #expect(ask.turns.last?.citedEntryIDs.count == 1)
    }

    @Test func aFailedFirstAnswerStillSavesWithItsFailure() async throws {
        entry("Paddled the river.")
        let ask = service()
        generator.results = [.failure(AIError.serverError(status: 500))]

        await ask.send("river?", in: context)

        #expect(AskConversation.all(in: context).count == 1)
        #expect(ask.turns.last?.failureRaw == "ai.serverError")
        #expect(ask.turns.last?.canRetry == true)
    }

    @Test func retryReusesTheHandlesAndReplacesTheFailedAnswer() async throws {
        entry("Paddled the river.")
        let ask = service()
        generator.results = [.failure(AIError.serverError(status: 500)), answer("You paddled.", citing: ["E1"])]

        await ask.send("river?", in: context)
        let handles = ask.handles
        await ask.retryLast(in: context)

        #expect(ask.handles == handles)
        #expect(ask.turns.count == 2, "the failed answer was replaced, not stacked on")
        #expect(ask.turns.last?.failureRaw == nil)
        #expect(AskMessage.all(forConversation: ask.conversationID, in: context).count == 2)
    }

    @Test func anEmptyJournalSendsNoRequest() async throws {
        let ask = service()

        await ask.send("What did I do last week?", in: context)

        #expect(generator.requests.isEmpty)
        #expect(ask.turns.last?.failureRaw == AskFailureText.noEntries)
        #expect(ask.turns.last?.canRetry == false)
        #expect(AskConversation.all(in: context).count == 1, "even a question with nothing to go on is history")
    }

    // On device the whole session is 6,000 characters, so a question long enough to fill it
    // leaves no room for a single block, and there is nothing worth asking with.
    // A journal held back by the pre-AI boundary is not an empty one: the answer points at the
    // switch that would open it, instead of reading as a dead end.
    @Test func entriesHeldBackByTheAIBoundarySayWhyAndWhereTheSwitchIs() async throws {
        let enabledAt = now
        entry("Paddled the river.", createdAt: now.addingTimeInterval(-86_400))
        let ask = service(aiEnabledAt: enabledAt)

        await ask.send("river?", in: context)

        #expect(generator.requests.isEmpty)
        #expect(ask.turns.last?.failureRaw == AskFailureText.onlyOlderEntries)
        #expect(ask.turns.last?.text.contains("Include entries from before AI was on") == true)

        // With the switch on, the same question goes out.
        let including = service(includesOlder: true, aiEnabledAt: enabledAt)
        generator.results = [answer("You paddled.", citing: ["E1"])]
        await including.send("river?", in: context)
        #expect(generator.requests.count == 1)
    }

    @Test func aQuestionThatLeavesNoRoomForABlockSendsNoRequest() async throws {
        entry("The river was high.")
        let ask = AskService(
            resolve: { [generator] in .success(AskProvider(generator: generator, model: "m", label: "l", kind: .onDevice)) },
            store: AskStore(save: { try $0.save() }),
            diagnostics: .disabled,
            now: { self.now }
        )

        await ask.send(String(repeating: "what about the river ", count: 250), in: context)

        #expect(generator.requests.isEmpty)
        #expect(ask.turns.last?.failureRaw == AskFailureText.noEntries)
    }

    @Test func theProviderKindDecidesTheEncodingAndTheLabel() async throws {
        entry("Paddled the river with Sarah.")
        let onDevice = AskService(
            resolve: { [generator] in .success(AskProvider(generator: generator, model: "", label: "apple:foundation", kind: .onDevice)) },
            store: AskStore(save: { try $0.save() }),
            diagnostics: .disabled,
            now: { self.now }
        )
        generator.results = [.success("You paddled the river [E1].")]

        await onDevice.send("river?", in: context)

        #expect(generator.requests.first?.schema == nil, "the on-device model ignores schemas")
        #expect(generator.requests.first?.messages.isEmpty == true)
        #expect(onDevice.turns.last?.text == "You paddled the river.")
        #expect(onDevice.turns.last?.providerLabel == "apple:foundation")
        #expect(onDevice.turns.last?.citedEntryIDs.count == 1)
    }

    @Test func anUnavailableProviderSaysSoWithoutSending() async throws {
        entry("Paddled the river.")
        let ask = service(failure: AIJobFailure(raw: "settings.off"))

        #expect(ask.isAvailable == false)
        await ask.send("river?", in: context)

        #expect(generator.requests.isEmpty)
        #expect(ask.turns.last?.text == "Turn on AI in Settings to ask questions.")
    }

    // Only what this request carried may be cited: an entry from an earlier turn isn't in this
    // prompt, so a citation naming it would point at something the model never read.
    @Test func citationsAreLimitedToTheHandlesThisRequestSent() async throws {
        entry("Paddled the river.", daysAgo: 400)
        entry("Sarah brought the kayak.", daysAgo: 1)
        let ask = service()
        generator.results = [answer("Both.", citing: ["E1", "E2"]), answer("Only the kayak.", citing: ["E1", "E2"])]

        await ask.send("river kayak", in: context)
        #expect(ask.turns.last?.citedEntryIDs.count == 2)

        await ask.send("kayak", in: context)
        let second = try #require(generator.requests.last)
        let enumerated = try #require(citationHandles(in: second))
        #expect(enumerated.count == 1, "the earlier turn's entry is not in this prompt")
        #expect(ask.turns.last?.citedEntryIDs.count == 1, "and a citation naming it is dropped")
    }

    private func citationHandles(in request: TextRequest) -> [String]? {
        guard let schema = request.schema, case .object(let properties, _, _) = schema,
              let citations = properties.first(where: { $0.name == "citations" })?.schema,
              case .array(let items, _, _) = citations,
              case .enumeration(let values, _, _) = items else { return nil }
        return values
    }

    @Test func historyIsCappedAtSixTurnsAndCarriesNoBlocks() async throws {
        entry("Paddled the river.")
        let ask = service()
        generator.results = (0..<8).map { answer("Answer \($0)", citing: []) }

        for index in 0..<8 {
            await ask.send("Question \(index) about the river", in: context)
        }

        let last = try #require(generator.requests.last)
        #expect(last.messages.count == AskService.maxHistoryTurns * 2)
        #expect(last.messages.first?.content == "Question 1 about the river", "the oldest turns fall off")
        #expect(last.messages.allSatisfy { !$0.content.contains(AskContextBuilder.openDelimiter) })
    }

    @Test func aFoldedTurnGoesIntoTheOnDevicePrompt() async throws {
        entry("Paddled the river.")
        let ask = AskService(
            resolve: { [generator] in .success(AskProvider(generator: generator, model: "", label: "apple:foundation", kind: .onDevice)) },
            store: AskStore(save: { try $0.save() }),
            diagnostics: .disabled,
            now: { self.now }
        )
        generator.results = [.success("You paddled."), .success("On Tuesday.")]

        await ask.send("river?", in: context)
        await ask.send("when?", in: context)

        let second = try #require(generator.requests.last)
        #expect(second.user.contains("Earlier you were asked: river?"))
        #expect(second.user.contains("You answered: You paddled."))
    }

    @Test func contextTooLongGetsItsOwnWording() async throws {
        entry("Paddled the river.")
        let ask = service()
        generator.results = [.failure(AIError.contextTooLong)]

        await ask.send("river?", in: context)

        #expect(ask.turns.last?.text == "That was too much to send at once. Try a narrower question.")
        #expect(AskFailureText.message(for: AIJobFailure(AIError.requestTooLarge)) == ask.turns.last?.text)
    }

    @Test func aConversationDeletedMidRequestDropsTheAnswer() async throws {
        entry("Paddled the river.")
        let ask = service()
        generator.results = [answer("First.", citing: [])]
        await ask.send("river?", in: context)
        let first = try #require(AskConversation.all(in: context).first)

        generator.suspends = true
        let sending = Task { await ask.send("and then?", in: context) }
        await generator.waitForRequest(number: 2)
        ask.delete(first, in: context)
        generator.answer(answer("Second.", citing: []))
        await sending.value

        #expect(ask.turns.isEmpty, "the deleted conversation was the open one, so the screen is new and empty")
        #expect(AskConversation.all(in: context).isEmpty)
        #expect(AskMessage.all(forConversation: first.id, in: context).isEmpty)
    }

    @Test func anAnswerArrivingAfterNewConversationIsDropped() async throws {
        entry("Paddled the river.")
        let ask = service()
        generator.suspends = true
        let sending = Task { await ask.send("river?", in: context) }
        await generator.waitForRequest(number: 1)
        ask.newConversation()
        generator.answer(answer("Too late.", citing: []))
        await sending.value

        #expect(ask.turns.isEmpty)
        #expect(AskConversation.all(in: context).isEmpty)
    }

    @Test func aCitedEntryDeletedLaterStillReadsBackAsAnID() async throws {
        let entry = entry("Paddled the river.")
        let ask = service()
        generator.results = [answer("You paddled.", citing: ["E1"])]
        await ask.send("river?", in: context)
        let citedID = try #require(ask.turns.last?.citedEntryIDs.first)
        #expect(citedID == entry.id)

        context.delete(entry)
        try context.save()

        let message = try #require(AskMessage.all(forConversation: ask.conversationID, in: context).last)
        #expect(message.citedEntryIDs == [citedID])
        let stillThere = ((try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.id == citedID }))) ?? []).filter { !$0.isDeleted }
        #expect(stillThere.isEmpty, "the chip has nothing to open, so it reads as deleted")
    }

    @Test func reopeningAConversationRestoresItsTurnsAndHandles() async throws {
        entry("Paddled the river.")
        let ask = service()
        generator.results = [answer("You paddled.", citing: ["E1"])]
        await ask.send("river?", in: context)
        let saved = try #require(AskConversation.all(in: context).first)
        let handles = ask.handles

        ask.newConversation()
        #expect(ask.turns.isEmpty)
        ask.open(saved, in: context)

        #expect(ask.turns.count == 2)
        #expect(ask.handles == handles)
        #expect(ask.conversations(in: context).map(\.id) == [saved.id])
    }
}
