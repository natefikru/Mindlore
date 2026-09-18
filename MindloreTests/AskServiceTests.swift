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

    private func service(kind: AskProviderKind = .openAI, failure: AIJobFailure? = nil, voice: PromptVoice = .default) -> AskService {
        AskService(
            resolve: { [generator] in
                if let failure { return .failure(failure) }
                return .success(AskProvider(generator: generator, model: "m", label: "openai:m", kind: kind))
            },
            promptVoice: { voice },
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

    // Only what this request carried may be cited: a handle the prompt didn't hand out points at
    // something the model never read.
    @Test func citationsAreLimitedToTheHandlesThisRequestSent() async throws {
        entry("Paddled the river.", daysAgo: 400)
        entry("Sarah brought the kayak.", daysAgo: 1)
        let ask = service()
        generator.results = [answer("Both.", citing: ["E1", "E2"]), answer("Only the kayak.", citing: ["E1", "E9"])]

        await ask.send("river kayak", in: context)
        let firstRequest = try #require(generator.requests.last)
        let offered = try #require(citationHandles(in: firstRequest))
        // Exactly the entries this prompt carried, no more.
        #expect(offered.count == ask.turns.last?.sentEntryIDs.count)

        await ask.send("kayak", in: context)
        let secondRequest = try #require(generator.requests.last)
        let enumerated = try #require(citationHandles(in: secondRequest))
        #expect(enumerated.contains("E9") == false, "a handle this prompt never used isn't offered")
        #expect(ask.turns.last?.citedEntryIDs.count == 1, "and a citation naming it is dropped")
    }

    // The conversation's own entries come back, from their own slice. The model can see it said
    // something about the river; without this it cannot re-read the entry it said it from, so it
    // either hedges or fills the gap.
    @Test func anEntryTheLastAnswerCitedIsSentAgainEvenWhenTheFollowUpDoesNotMatchIt() async throws {
        let river = entry("Paddled the river.", daysAgo: 400)
        entry("Sarah brought the kayak.", daysAgo: 1)
        let ask = service()
        generator.results = [answer("The river.", citing: ["E1"]), answer("Because of the weather.", citing: ["E1"])]

        await ask.send("river", in: context)
        #expect(ask.turns.last?.sentEntryIDs == [river.id])

        // Nothing in this question matches the river entry, and it still goes out.
        await ask.send("why do you think that was?", in: context)
        #expect(ask.turns.last?.sentEntryIDs.contains(river.id) == true)
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

    // MARK: - Owning up to what the answer is written from

    @Test func aCutSetIsSaidOutLoudInThePrompt() async throws {
        // Thirty entries about the deadline, fifteen of which fit. Without this line the model
        // describes the whole year from whatever twelve entries it can see, confidently.
        for index in 0..<30 {
            entry("The deadline moved again, week \(index).", daysAgo: Double(index + 1))
        }
        let ask = service()
        generator.results = [answer("It moved a lot.", citing: ["E1"])]

        await ask.send("What happened with the deadline?", in: context)
        let request = try #require(generator.requests.last)

        #expect(request.user.contains("that match at all"))
        #expect(ask.turns.last?.wasCut == true)
        #expect(ask.turns.last?.matchedCount == 30)
    }

    @Test func aSetThatWentWholeSaysNothingAboutBeingCut() async throws {
        entry("The deadline moved.")
        let ask = service()
        generator.results = [answer("It moved.", citing: ["E1"])]

        await ask.send("What happened with the deadline?", in: context)
        let request = try #require(generator.requests.last)
        #expect(request.user.contains("that match at all") == false)
        #expect(ask.turns.last?.wasCut == false)
    }

    @Test func thePromptSaysWhichDaysTheEntriesCameFrom() async throws {
        entry("An ordinary day.", daysAgo: 2)
        let ask = service()
        generator.results = [answer("Not much.", citing: ["E1"])]

        await ask.send("What did I do last week?", in: context)
        let request = try #require(generator.requests.last)
        // Said for an inherited range too, which is what makes an inheritance the person did not
        // intend visible in the answer rather than silent.
        #expect(request.user.contains("These entries are from"))
    }

    // An inherited range never filtered anything: entries outside it are in the prompt. Stating it
    // as fact made the model refuse or mis-date them, and nothing tested it.
    @Test func anInheritedRangeIsDescribedAsTheQuestionBeforeRatherThanAsAFact() async throws {
        entry("Walked the river.", daysAgo: 2)
        entry("Walked the river again.", daysAgo: 300)
        let ask = service()
        generator.results = [answer("Not much.", citing: ["E1"]), answer("The river.", citing: ["E1"])]

        await ask.send("What did I do last week?", in: context)
        await ask.send("And the river?", in: context)

        let request = try #require(generator.requests.last)
        #expect(request.user.contains("The question before this one was about"))
        #expect(request.user.contains("not limited to it"))
        #expect(request.user.contains("These entries are from") == false)
    }

    @Test func aQuestionMatchingNothingSaysSoRatherThanPretending() async throws {
        entry("The deadline moved.")
        let ask = service()
        generator.results = [answer("Nothing about that.", citing: [])]

        await ask.send("ayahuasca", in: context)
        let request = try #require(generator.requests.last)
        #expect(request.user.contains("Nothing in the journal matches this question"))
        // And it still sends the newest entries rather than failing, which is what A7 did.
        #expect(ask.turns.last?.sentEntryIDs.isEmpty == false)
        // Nothing else may describe them as being about the question or about a period.
        #expect(request.user.contains("that match at all") == false)
        #expect(request.user.contains("These entries are from") == false)
    }

    @Test func theSummaryRuleGoesInOnlyWhenASummaryDoes() async throws {
        for index in 0..<60 {
            entry("An ordinary day at work, number \(index).", daysAgo: Double(index + 1))
        }
        let ask = service()
        generator.results = [answer("Often.", citing: ["E1"]), answer("Once.", citing: ["E1"])]

        await ask.send("How often did I write about work?", in: context)
        let aggregate = try #require(generator.requests.last)
        #expect(aggregate.system.contains("not of the entries quoted below it"))
        #expect(ask.turns.last?.rollupMonthCount ?? 0 > 0)

        await ask.newConversation()
        await ask.send("What happened on the ninth day?", in: context)
        let ordinary = try #require(generator.requests.last)
        #expect(ordinary.system.contains("not of the entries quoted below it") == false)
    }

    // MARK: - Voice

    @Test func askAdoptsTheJournalsVoice() async throws {
        entry("Paddled the river.")
        let ask = service(voice: PromptVoice(voice: .second, name: ""))
        generator.results = [answer("You paddled.", citing: ["E1"])]

        await ask.send("What did I do?", in: context)
        let request = try #require(generator.requests.last)
        #expect(request.system.contains("second person"))
        // A7's prompt said "one person's private journal" and "the journal is theirs", which made
        // every answer read like a report about a stranger.
        #expect(request.system.contains("the author"))
    }

    @Test func theOwnersNameReachesAProviderOnlyUnderTheNameVoice() async throws {
        entry("Paddled the river.")
        let named = service(voice: PromptVoice(voice: .name, name: "Nate"))
        generator.results = [answer("Nate paddled.", citing: ["E1"])]
        await named.send("What did I do?", in: context)
        #expect(try #require(generator.requests.last).system.contains("Nate"))

        let first = service(voice: PromptVoice(voice: .first, name: "Nate"))
        generator.results = [answer("I paddled.", citing: ["E1"])]
        await first.send("What did I do?", in: context)
        #expect(try #require(generator.requests.last).system.contains("Nate") == false)
    }

    // MARK: - What a reopened turn still knows

    @Test func theCountsSurviveAReopen() async throws {
        for index in 0..<30 {
            entry("The deadline moved again, week \(index).", daysAgo: Double(index + 1))
        }
        let ask = service()
        generator.results = [answer("It moved a lot.", citing: ["E1"])]
        await ask.send("What happened with the deadline?", in: context)
        let matched = try #require(ask.turns.last?.matchedCount)

        // The index this was answered against is gone by the time a conversation is reopened, so
        // these two cannot be worked out again and have to be stored.
        let conversation = try #require(AskConversation.all(in: context).first)
        let reopened = service()
        reopened.open(conversation, in: context)
        #expect(reopened.turns.last?.matchedCount == matched)
        #expect(reopened.turns.last?.wasCut == true)
    }
}
