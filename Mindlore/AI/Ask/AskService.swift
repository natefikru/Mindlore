import Foundation
import Observation
import SwiftData

// Who answers, and how the request has to be shaped for them.
nonisolated enum AskProviderKind: String, Sendable {
    case openAI
    case onDevice
}

nonisolated struct AskProvider: Sendable {
    let generator: any TextGenerator
    let model: String
    let label: String
    let kind: AskProviderKind
}

// One turn on screen, mirroring the AskMessage it is saved as.
nonisolated struct AskTurn: Identifiable, Equatable, Sendable {
    let id: UUID
    let role: AskRole
    var text: String
    var citedEntryIDs: [UUID] = []
    var providerLabel: String = ""
    var sentEntryIDs: [UUID] = []
    var sentCharacters: Int = 0
    var matchedCount = 0
    var rollupMonthCount = 0
    // Of sentEntryIDs, how many went as one line. The rest went whole.
    var digestEntryCount = 0
    var failureRaw: String?

    // Whether the answer was written from a sample of a larger set, which is what "What was sent"
    // has to say out loud. A digest counts: the model saw the day, in a line.
    var wasCut: Bool { matchedCount > sentEntryIDs.count }
    var fullEntryCount: Int { sentEntryIDs.count - digestEntryCount }

    var failure: AIJobFailure? { failureRaw.map(AIJobFailure.init(raw:)) }
    // "Nothing to go on" is a note about the journal, not something to offer a Retry for.
    var canRetry: Bool { failureRaw != nil && failureRaw != AskFailureText.noEntries }
}

// Saving a conversation. Like GraphServices, it flushes the entry saver first and saves through
// saveStampingEntries, so a pending editor edit is never written without its stamp.
@MainActor
struct AskStore {
    let flush: () -> Void
    let save: (ModelContext) throws -> Void

    // nonisolated so it can be a default argument of the service's own initializer.
    nonisolated init(flush: @escaping () -> Void = {}, save: @escaping (ModelContext) throws -> Void = { try $0.saveStampingEntries() }) {
        self.flush = flush
        self.save = save
    }

    func conversations(in context: ModelContext) -> [AskConversation] {
        AskConversation.all(in: context).sorted { $0.updatedAt > $1.updatedAt }
    }

    func write(_ body: () -> Void, in context: ModelContext) {
        flush()
        body()
        try? save(context)
    }

    func delete(_ conversation: AskConversation, in context: ModelContext) {
        write({
            for message in AskMessage.all(forConversation: conversation.id, in: context) {
                context.delete(message)
            }
            context.delete(conversation)
        }, in: context)
    }
}

// Ask's conversation: what is on screen, what goes out, and what comes back. A conversation
// lives in memory until its first answer arrives, successful or failed, so an abandoned question
// never shows up in history.
@Observable
@MainActor
final class AskService {
    private(set) var conversationID = UUID()
    private(set) var turns: [AskTurn] = []
    private(set) var handles: [String: UUID] = [:]
    private(set) var isRunning = false
    // Kept while the user is on another tab, so a half-typed question survives a look at Mind.
    var draftQuestion = ""

    @ObservationIgnored private let resolve: () -> Result<AskProvider, AIJobFailure>
    @ObservationIgnored private let indexStore: AskIndexStore
    // Read through a closure rather than held, so the service owes nothing to EntrySaver or
    // GraphServices and tests can move either counter by hand.
    @ObservationIgnored private let revisions: () -> AskIndexStore.Revisions
    // How the app writes about the journal's owner, the same closure shape InsightsCoordinator and
    // GraphServices take. The name reaches a provider only under the name voice, which
    // PromptVoice.init enforces by construction.
    @ObservationIgnored private let promptVoice: () -> PromptVoice
    @ObservationIgnored private let store: AskStore
    @ObservationIgnored private let diagnostics: DiagnosticsLog
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar
    // Set once the conversation has been written, so a reopen and a delete both find it.
    @ObservationIgnored private var isSaved = false

    static let maxHistoryTurns = 6

    init(
        resolve: @escaping () -> Result<AskProvider, AIJobFailure>,
        index: AskIndexStore = AskIndexStore(),
        revisions: @escaping () -> AskIndexStore.Revisions = { .init() },
        promptVoice: @escaping () -> PromptVoice = { .default },
        store: AskStore = AskStore(),
        diagnostics: DiagnosticsLog = .shared,
        now: @escaping () -> Date = { .now },
        calendar: Calendar = .current
    ) {
        self.resolve = resolve
        self.indexStore = index
        self.revisions = revisions
        self.promptVoice = promptVoice
        self.store = store
        self.diagnostics = diagnostics
        self.now = now
        self.calendar = calendar
    }

    var isAvailable: Bool { resolve().isSuccess }

    var unavailableFailure: AIJobFailure? {
        if case .failure(let failure) = resolve() { return failure }
        return nil
    }

    // MARK: - Moving between conversations

    func newConversation() {
        conversationID = UUID()
        turns = []
        handles = [:]
        draftQuestion = ""
        isSaved = false
    }

    func open(_ conversation: AskConversation, in context: ModelContext) {
        conversationID = conversation.id
        handles = conversation.handleMap
        isSaved = true
        draftQuestion = ""
        turns = AskMessage.all(forConversation: conversation.id, in: context).map {
            AskTurn(
                id: $0.id,
                role: $0.role,
                text: $0.text,
                citedEntryIDs: $0.citedEntryIDs,
                providerLabel: $0.providerLabel,
                sentEntryIDs: $0.sentEntryIDs,
                sentCharacters: $0.sentCharacters,
                matchedCount: $0.matchedCount,
                rollupMonthCount: $0.rollupMonthCount,
                digestEntryCount: $0.digestEntryCount,
                failureRaw: $0.failureRaw
            )
        }
    }

    func conversations(in context: ModelContext) -> [AskConversation] {
        store.conversations(in: context)
    }

    func delete(_ conversation: AskConversation, in context: ModelContext) {
        let wasOpen = conversation.id == conversationID
        store.delete(conversation, in: context)
        diagnostics.record("ask.conversationDeleted", [:])
        if wasOpen { newConversation() }
    }

    // MARK: - Asking

    func send(_ question: String, in context: ModelContext) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isRunning else { return }
        isRunning = true
        draftQuestion = ""
        turns.append(AskTurn(id: UUID(), role: .user, text: trimmed))
        await answer(trimmed, in: context)
    }

    // The same question, the same handles: a failed answer is replaced, never stacked on.
    func retryLast(in context: ModelContext) async {
        guard !isRunning, let last = turns.last, last.role == .assistant, last.canRetry,
              let question = turns.dropLast().last, question.role == .user else { return }
        isRunning = true
        turns.removeLast()
        if isSaved, let message = AskMessage.all(forConversation: conversationID, in: context).first(where: { $0.id == last.id }) {
            store.write({ context.delete(message) }, in: context)
        }
        await answer(question.text, in: context)
    }

    // Called when Ask appears and before a question goes out. Cheap when nothing changed: five
    // counters and a comparison, against the whole-journal read this replaces.
    // The snapshot the search panel ranks against, so the panel and the prompt read one index.
    var index: AskIndex { indexStore.index }

    func refreshIndex(in context: ModelContext) async {
        await indexStore.refreshIfNeeded(revisions: revisions(), in: context)
    }

    // Entered with isRunning already true, set by the caller before its first await, so two
    // taps can never both get past the guard.
    private func answer(_ question: String, in context: ModelContext) async {
        defer { isRunning = false }
        let provider: AskProvider
        switch resolve() {
        case .success(let resolved):
            provider = resolved
        case .failure(let failure):
            finish(question: question, turn: failureTurn(failure), in: context)
            return
        }

        await indexStore.refreshIfNeeded(revisions: revisions(), in: context)
        let retrieval = retrieval(for: question, asked: true, provider: provider)
        let selection = AskSources.blocks(for: retrieval.plan, in: context)
        let retrievalPlan = retrieval.plan
        // One block, counting the same set matchedCount describes.
        let summary = AskRollups.block(
            for: AskRollups.months(
                for: retrievalPlan.rollupMonths,
                matching: retrievalPlan.matchedEntryIDs,
                in: indexStore.index,
                calendar: calendar
            ),
            calendar: calendar
        )
        let built = AskContextBuilder.render(
            plan: retrievalPlan,
            selection: selection,
            rollups: [summary].compactMap { $0 },
            terms: retrieval.query.terms.map(\.text),
            handles: handles,
            budget: budget(for: provider, question: question)
        )
        let eligible = indexStore.index.documents.count { $0.isSendable }
        diagnostics.record("ask.retrieved", [
            "matched": .int(retrievalPlan.matchedCount),
            "ranked": .int(retrievalPlan.rankedEntryIDs.count),
            "digests": .int(retrievalPlan.digestEntryIDs.count),
            "excerpts": .int(retrievalPlan.excerptEntryIDs.count),
            "continuity": .int(retrievalPlan.continuityEntryIDs.count),
            "rollupMonths": .int(retrievalPlan.rollupMonths.count),
            "about": .int(retrievalPlan.aboutEntityIDs.count),
            "aggregate": .bool(retrievalPlan.isAggregate),
            "rangeInherited": .bool(retrievalPlan.rangeWasInherited),
            "turn": .int(turnIndex),
        ])
        guard !built.isEmpty else {
            let failure = AIJobFailure(raw: AskFailureText.noEntries)
            diagnostics.record("ask.failed", [
                "error": .string(failure.raw),
                "turn": .int(turnIndex),
                "eligible": .int(eligible),
            ])
            finish(question: question, turn: failureTurn(failure), in: context)
            return
        }

        let known = built.handlesSent
        var request = TextRequest(
            model: provider.model,
            system: AskPrompt.system(
                today: now(),
                calendar: calendar,
                voice: promptVoice(),
                hasSummaries: built.rollupMonthCount > 0,
                provider: provider.kind
            ),
            user: AskPrompt.user(
                context: built,
                question: question,
                notes: AskPrompt.notes(for: built, plan: retrievalPlan, calendar: calendar)
            ),
            schemaName: AskPrompt.schemaName
        )
        switch provider.kind {
        case .openAI:
            request.messages = history()
            request.schema = AskPrompt.schema(handles: Array(known))
        case .onDevice:
            request.user = AskPrompt.folded(previous: previousTurn(), into: request.user)
        }

        let askedIn = conversationID
        let startedAt = now()

        let answer: AskAnswerParser.Answer
        do {
            let result = try await provider.generator.generate(request)
            answer = switch provider.kind {
            case .openAI: try AskAnswerParser.parseJSON(result.text, known: known)
            case .onDevice: AskAnswerParser.parseMarkers(result.text, known: known)
            }
        } catch {
            let failure = AIJobFailure(any: error)
            guard stillOpen(askedIn, in: context) else { return }
            diagnostics.record("ask.failed", ["error": .string(failure.raw), "turn": .int(turnIndex)])
            var turn = failureTurn(failure)
            turn.providerLabel = provider.label
            turn.sentEntryIDs = built.entryIDs
            turn.sentCharacters = built.characters
            turn.matchedCount = built.matchedCount
            turn.rollupMonthCount = built.rollupMonthCount
            turn.digestEntryCount = built.digestEntryIDs.count
            finish(question: question, turn: turn, context: built, in: context)
            return
        }

        // The conversation may have been deleted, or "New conversation" tapped, while this ran.
        guard stillOpen(askedIn, in: context) else { return }
        let turn = AskTurn(
            id: UUID(),
            role: .assistant,
            text: answer.text,
            citedEntryIDs: answer.handles.compactMap { built.handles[$0] },
            providerLabel: provider.label,
            sentEntryIDs: built.entryIDs,
            sentCharacters: built.characters,
            matchedCount: built.matchedCount,
            rollupMonthCount: built.rollupMonthCount,
            digestEntryCount: built.digestEntryIDs.count
        )
        diagnostics.record("ask.answered", [
            "entries": .int(built.entryIDs.count),
            "digests": .int(built.digestEntryIDs.count),
            "citations": .int(answer.handles.count),
            "characters": .int(built.characters),
            "durationMilliseconds": .int(Int(now().timeIntervalSince(startedAt) * 1000)),
            "provider": .string(provider.kind.rawValue),
            "turn": .int(turnIndex),
            "eligible": .int(eligible),
            "matched": .int(built.matchedCount),
        ])
        finish(question: question, turn: turn, context: built, in: context)
    }

    // MARK: - Pieces

    // `asked` says whether this question is already the last turn, which it is once send() has
    // appended it and is not while the user is still typing.
    private func retrieval(for question: String, asked: Bool, provider: AskProvider) -> (query: AskRetrievalQuery, plan: AskRetrieval.Plan) {
        let questions = turns.filter { $0.role == .user }.map(\.text)
        let previous = Array((asked ? questions.dropLast() : questions[...]).reversed())
        let cited = turns
            .filter { $0.role == .assistant && $0.failureRaw == nil }
            .reversed()
            .map(\.citedEntryIDs)
        let query = AskRetrievalQuery.build(
            question: question,
            previousQuestions: previous,
            citedEntryIDs: cited,
            index: indexStore.index,
            now: now(),
            calendar: calendar
        )
        let plan = AskRetrieval.plan(
            query: query,
            index: indexStore.index,
            budget: budget(for: provider, question: question),
            provider: provider.kind,
            rollups: true,
            calendar: calendar
        )
        return (query, plan)
    }

    // OpenAI's budget covers the blocks alone. On device the 6,000 is the whole session, so the
    // system prompt, the folded turn, and room for the answer come out of it first.
    private func budget(for provider: AskProvider, question: String) -> Int {
        switch provider.kind {
        case .openAI:
            return AskContextBuilder.openAIBudget
        case .onDevice:
            let fixed = AskPrompt.system(today: now(), calendar: calendar, voice: promptVoice(), hasSummaries: false, provider: .onDevice).count
                + AskPrompt.folded(previous: previousTurn(), into: "").count
                + question.count
                + AskPrompt.onDeviceNotesHeadroom
                + AskContextBuilder.onDeviceAnswerHeadroom
            return max(0, AskContextBuilder.onDeviceBudget - fixed)
        }
    }

    // Question and answer text only, never the old context blocks, capped at the last six turns.
    private func history() -> [TextMessage] {
        var pairs: [(question: String, answer: String)] = []
        var pendingQuestion: String?
        for turn in turns {
            switch turn.role {
            case .user:
                pendingQuestion = turn.text
            case .assistant:
                // A failed turn holds an error message, not an answer, so neither half goes out.
                if let question = pendingQuestion, turn.failureRaw == nil {
                    pairs.append((question, turn.text))
                }
                pendingQuestion = nil
            }
        }
        return pairs.suffix(Self.maxHistoryTurns).flatMap {
            [TextMessage(role: .user, content: $0.question), TextMessage(role: .assistant, content: $0.answer)]
        }
    }

    private func previousTurn() -> (question: String, answer: String)? {
        let messages = history()
        guard messages.count >= 2 else { return nil }
        return (messages[messages.count - 2].content, messages[messages.count - 1].content)
    }

    private var turnIndex: Int {
        turns.filter { $0.role == .user }.count
    }

    private func failureTurn(_ failure: AIJobFailure) -> AskTurn {
        AskTurn(id: UUID(), role: .assistant, text: AskFailureText.message(for: failure), failureRaw: failure.raw)
    }

    // A conversation this session already saved has to still be there: a delete leaves a
    // tombstone behind, which fetches as a live object until the context forgets it.
    private func stillOpen(_ askedIn: UUID, in context: ModelContext) -> Bool {
        guard conversationID == askedIn else { return false }
        guard isSaved else { return true }
        return AskConversation.fetch(askedIn, in: context) != nil
    }

    // The answer is on screen and the conversation is written: both messages, the handle map it
    // was answered with, and the time it was last touched.
    private func finish(question: String, turn: AskTurn, context built: AskContextBuilder.Context? = nil, in context: ModelContext) {
        if let built { handles = built.handles }
        turns.append(turn)

        store.write({
            let conversation: AskConversation
            if isSaved, let existing = AskConversation.fetch(conversationID, in: context) {
                conversation = existing
            } else {
                conversation = AskConversation(id: conversationID, createdAt: now(), title: AskConversation.title(from: question))
                context.insert(conversation)
                isSaved = true
            }
            conversation.updatedAt = now()
            conversation.handleMap = handles

            let saved = AskMessage.all(forConversation: conversationID, in: context)
            let savedIDs = Set(saved.map(\.id))
            var index = saved.map(\.index).max().map { $0 + 1 } ?? 0
            for turn in turns where !savedIDs.contains(turn.id) {
                let message = AskMessage(
                    id: turn.id,
                    conversationID: conversationID,
                    index: index,
                    role: turn.role,
                    text: turn.text,
                    citedEntryIDs: turn.citedEntryIDs,
                    providerLabel: turn.providerLabel,
                    sentEntryIDs: turn.sentEntryIDs,
                    sentCharacters: turn.sentCharacters,
                    matchedCount: turn.matchedCount,
                    rollupMonthCount: turn.rollupMonthCount,
                    digestEntryCount: turn.digestEntryCount,
                    failureRaw: turn.failureRaw
                )
                context.insert(message)
                index += 1
            }
        }, in: context)
    }
}
