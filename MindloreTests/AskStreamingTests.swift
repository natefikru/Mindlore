import Foundation
import SwiftData
import Testing
@testable import Mindlore

// A generator that hands the answer over in pieces, and can be held mid-answer so a test can do
// something to the conversation while it is still arriving.
@MainActor
final class FakeStreamingTextGenerator: StreamingTextGenerator {
    var requests: [TextRequest] = []
    var streamedRequests: [TextRequest] = []
    // The raw pieces, exactly as they would come off the wire.
    var deltas: [String] = []
    // The whole raw text, yielded as .finished. Nil with no failure means the stream just ends.
    var finished: String?
    var failure: (any Error)?
    // The stream waits here, after this many deltas, until release() is called. Counted across
    // every stream this generator serves, never reset: a reset would land inside the emitting
    // task, after a test had already read the old count and decided the stream was under way.
    var pauseAfter: Int?

    private var emitted = 0
    private var gate: CheckedContinuation<Void, Never>?
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    nonisolated func generate(_ request: TextRequest) async throws -> TextResult {
        try await MainActor.run {
            requests.append(request)
            if let failure { throw failure }
            return TextResult(text: finished ?? "", model: request.model, inputTokens: 1, outputTokens: 2)
        }
    }

    nonisolated func stream(_ request: TextRequest) -> AsyncThrowingStream<TextStreamEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                streamedRequests.append(request)
                for delta in deltas {
                    continuation.yield(.delta(delta))
                    emitted += 1
                    notify()
                    if emitted == pauseAfter { await withCheckedContinuation { gate = $0 } }
                    if Task.isCancelled { break }
                }
                if let failure {
                    continuation.finish(throwing: failure)
                    return
                }
                if let finished {
                    continuation.yield(.finished(TextResult(text: finished, model: request.model, inputTokens: 1, outputTokens: 2)))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func waitForDeltas(_ count: Int) async {
        while emitted < count {
            await withCheckedContinuation { waiters.append((count, $0)) }
        }
    }

    func release() {
        gate?.resume()
        gate = nil
    }

    private func notify() {
        let ready = waiters.filter { emitted >= $0.count }
        waiters.removeAll { emitted >= $0.count }
        ready.forEach { $0.continuation.resume() }
    }
}

@MainActor
struct AskStreamingTests {
    private let container: ModelContainer
    private let context: ModelContext
    private let generator = FakeStreamingTextGenerator()
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    init() throws {
        container = try ModelContainerFactory.make(.inMemory)
        context = container.mainContext
    }

    private func service(kind: AskProviderKind = .openAI) -> AskService {
        AskService(
            resolve: { [generator] in
                .success(AskProvider(generator: generator, model: "m", label: "openai:m", kind: kind))
            },
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

    private static let whole = #"{"answer":"You paddled the river.","citations":["E1"]}"#

    private func script(pauseAfter: Int? = nil) {
        generator.deltas = [
            #"{"answer":"You paddl"#,
            #"ed the river.","citat"#,
            #"ions":["E1"]}"#,
        ]
        generator.finished = Self.whole
        generator.pauseAfter = pauseAfter
    }

    @Test func theAnswerIsOnScreenBeforeTheObjectCloses() async throws {
        entry("Paddled the river with Sarah.")
        let ask = service()
        script(pauseAfter: 1)

        let asking = Task { await ask.send("What did I do on the river?", in: context) }
        await generator.waitForDeltas(1)

        // Half an object, and a whole readable sentence out of it.
        #expect(ask.turns.last?.text == "You paddl")
        #expect(ask.turns.last?.isStreaming == true)
        #expect(ask.turns.last?.citedEntryIDs.isEmpty == true, "the handles are not in the object yet")
        #expect(ask.isRunning)
        #expect(ask.canStop)

        generator.release()
        await asking.value

        #expect(ask.turns.last?.text == "You paddled the river.")
        #expect(ask.turns.last?.isStreaming == false)
        #expect(ask.turns.last?.citedEntryIDs.count == 1)
        #expect(ask.turns.count == 2, "the turn that was streaming is the turn that was answered")
        #expect(!ask.isRunning)
    }

    @Test func aStreamedAnswerIsSavedOnceAndWhole() async throws {
        entry("Paddled the river.")
        let ask = service()
        script()

        await ask.send("river?", in: context)

        let saved = AskMessage.all(forConversation: ask.conversationID, in: context)
        #expect(saved.map(\.role) == [.user, .assistant])
        #expect(saved.last?.text == "You paddled the river.")
        #expect(saved.last?.citedEntryIDs.count == 1)
        #expect(saved.last?.wasStopped == false)
    }

    @Test func stopKeepsWhatArrived() async throws {
        entry("Paddled the river.")
        let ask = service()
        script(pauseAfter: 1)

        let asking = Task { await ask.send("river?", in: context) }
        await generator.waitForDeltas(1)
        ask.stop()
        generator.release()
        await asking.value

        let turn = try #require(ask.turns.last)
        #expect(turn.text == "You paddl")
        #expect(turn.wasStopped)
        #expect(turn.isStreaming == false)
        #expect(turn.failureRaw == nil, "stopping is not a failure")
        #expect(turn.canRetry == false)
        #expect(turn.citedEntryIDs.isEmpty)
        #expect(!ask.isRunning)
        #expect(!ask.canStop)

        // It survives a reopen, because a stopped answer is still an answer.
        let conversation = try #require(AskConversation.fetch(ask.conversationID, in: context))
        ask.newConversation()
        ask.open(conversation, in: context)
        #expect(ask.turns.last?.text == "You paddl")
        #expect(ask.turns.last?.wasStopped == true)
    }

    // Stop and the last frame can land in the same instant. The answer arrived, so it is the
    // answer, chips and all: a thumb a millisecond early must not cost the citations.
    @Test func stopRacingAFinishedStreamKeepsTheWholeAnswer() async throws {
        entry("Paddled the river.")
        let ask = service()
        script()

        let asking = Task { await ask.send("river?", in: context) }
        await generator.waitForDeltas(3)
        ask.stop()
        await asking.value

        let turn = try #require(ask.turns.last)
        #expect(turn.text == "You paddled the river.")
        #expect(turn.wasStopped == false)
        #expect(turn.citedEntryIDs.count == 1)
    }

    // The answer belongs to a conversation nobody is looking at any more. Without the cancel the
    // reader runs on and isRunning stays true, which reads as a send button that stopped working.
    @Test func leavingTheConversationMidAnswerFreesTheNextOne() async throws {
        entry("Paddled the river.")
        let ask = service()
        script(pauseAfter: 1)

        let asking = Task { await ask.send("river?", in: context) }
        await generator.waitForDeltas(1)
        ask.newConversation()
        await asking.value

        #expect(!ask.isRunning, "the new conversation can be asked a question")
        #expect(ask.turns.isEmpty)
        #expect(AskConversation.all(in: context).isEmpty)

        generator.pauseAfter = nil
        generator.release()
        await ask.send("and now?", in: context)
        #expect(ask.turns.last?.text == "You paddled the river.")
    }

    @Test func aStreamThatDiesMidAnswerDiscardsThePartialAndOffersRetry() async throws {
        entry("Paddled the river.")
        let ask = service()
        script()
        generator.failure = AIError.network(.networkConnectionLost)

        await ask.send("river?", in: context)

        let turn = try #require(ask.turns.last)
        #expect(turn.failureRaw == "ai.network")
        #expect(turn.canRetry)
        #expect(turn.wasStopped == false)
        #expect(!turn.text.contains("paddl"), "a dropped request leaves no half answer behind")
        #expect(ask.turns.count == 2, "the streaming turn went with it")
    }

    @Test func aConversationReplacedMidAnswerKeepsNothing() async throws {
        entry("Paddled the river.")
        let ask = service()
        script(pauseAfter: 1)

        let asking = Task { await ask.send("river?", in: context) }
        await generator.waitForDeltas(1)
        ask.newConversation()
        generator.release()
        await asking.value

        #expect(ask.turns.isEmpty)
        #expect(AskConversation.all(in: context).isEmpty)
    }

    @Test func theOnDeviceProviderIsStillAwaitedWhole() async throws {
        entry("Paddled the river.")
        let ask = service(kind: .onDevice)
        generator.deltas = ["never used"]
        generator.finished = "You paddled the river. [E1]"

        await ask.send("river?", in: context)

        #expect(generator.streamedRequests.isEmpty, "the on-device model has no stream to read")
        #expect(generator.requests.count == 1)
        #expect(ask.turns.last?.text == "You paddled the river.")
        #expect(ask.turns.last?.citedEntryIDs.count == 1)
    }

    @Test func aStreamThatEndsWithoutItsResultIsAFailure() async throws {
        entry("Paddled the river.")
        let ask = service()
        generator.deltas = [#"{"answer":"half"#]
        generator.finished = nil

        await ask.send("river?", in: context)

        #expect(ask.turns.last?.failureRaw == "ai.invalidResponse")
        #expect(ask.turns.count == 2)
    }

    @Test func retryAfterAStoppedAnswerIsNotOfferedButANewQuestionWorks() async throws {
        entry("Paddled the river.")
        let ask = service()
        script(pauseAfter: 1)

        let asking = Task { await ask.send("river?", in: context) }
        await generator.waitForDeltas(1)
        ask.stop()
        generator.release()
        await asking.value

        await ask.retryLast(in: context)
        #expect(ask.turns.count == 2, "a stopped answer is not retried")

        generator.pauseAfter = nil
        await ask.send("and then?", in: context)
        #expect(ask.turns.count == 4)
        #expect(ask.turns.last?.text == "You paddled the river.")
    }
}
