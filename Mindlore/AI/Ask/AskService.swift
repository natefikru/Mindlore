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
    var failureRaw: String?

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
    @ObservationIgnored private let includesOlderEntries: () -> Bool
    @ObservationIgnored private let aiEnabledAt: () -> Date?
    @ObservationIgnored private let store: AskStore
    @ObservationIgnored private let diagnostics: DiagnosticsLog
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar
    // Set once the conversation has been written, so a reopen and a delete both find it.
    @ObservationIgnored private var isSaved = false

    static let maxHistoryTurns = 6

    init(
        resolve: @escaping () -> Result<AskProvider, AIJobFailure>,
        includesOlderEntries: @escaping () -> Bool = { false },
        aiEnabledAt: @escaping () -> Date? = { nil },
        store: AskStore = AskStore(),
        diagnostics: DiagnosticsLog = .shared,
        now: @escaping () -> Date = { .now },
        calendar: Calendar = .current
    ) {
        self.resolve = resolve
        self.includesOlderEntries = includesOlderEntries
        self.aiEnabledAt = aiEnabledAt
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

    // What sending this question would cost, for the line under the field and "What was sent".
    func estimate(for question: String, in context: ModelContext) -> (entries: Int, characters: Int) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, case .success(let provider) = resolve() else { return (0, 0) }
        let built = buildContext(for: trimmed, provider: provider, in: context)
        return (built.entryIDs.count, built.characters)
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

        let journal = journal(for: provider, in: context)
        let built = build(question: question, from: journal, provider: provider)
        guard !built.isEmpty else {
            // A journal held back by the pre-AI boundary is not an empty one, and the difference
            // is the difference between a dead end and a switch to turn on.
            let raw = journal.entries.isEmpty && journal.heldBackAsOlder > 0
                ? AskFailureText.onlyOlderEntries
                : AskFailureText.noEntries
            let failure = AIJobFailure(raw: raw)
            diagnostics.record("ask.failed", [
                "error": .string(failure.raw),
                "turn": .int(turnIndex),
                "eligible": .int(journal.entries.count),
                "heldBackAsOlder": .int(journal.heldBackAsOlder),
                "includesOlder": .bool(includesOlderEntries()),
            ])
            finish(question: question, turn: failureTurn(failure), in: context)
            return
        }

        let known = built.handlesSent
        var request = TextRequest(
            model: provider.model,
            system: AskPrompt.system(today: now(), calendar: calendar),
            user: AskPrompt.user(context: built, question: question),
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
            sentCharacters: built.characters
        )
        diagnostics.record("ask.answered", [
            "entries": .int(built.entryIDs.count),
            "citations": .int(answer.handles.count),
            "characters": .int(built.characters),
            "durationMilliseconds": .int(Int(now().timeIntervalSince(startedAt) * 1000)),
            "provider": .string(provider.kind.rawValue),
            "turn": .int(turnIndex),
            "includesOlder": .bool(includesOlderEntries()),
            "eligible": .int(journal.entries.count),
            "heldBackAsOlder": .int(journal.heldBackAsOlder),
        ])
        finish(question: question, turn: turn, context: built, in: context)
    }

    // MARK: - Pieces

    private func journal(for provider: AskProvider, in context: ModelContext) -> AskSources.Journal {
        AskSources.journal(
            in: context,
            appliesAIEnabledAt: provider.kind == .openAI,
            aiEnabledAt: aiEnabledAt(),
            includesOlderEntries: includesOlderEntries()
        )
    }

    private func buildContext(for question: String, provider: AskProvider, in context: ModelContext) -> AskContextBuilder.Context {
        build(question: question, from: journal(for: provider, in: context), provider: provider)
    }

    private func build(question: String, from journal: AskSources.Journal, provider: AskProvider) -> AskContextBuilder.Context {
        AskContextBuilder.build(
            question: question,
            entries: journal.entries,
            entities: journal.entities,
            handles: handles,
            now: now(),
            calendar: calendar,
            budget: budget(for: provider, question: question)
        )
    }

    // OpenAI's budget covers the blocks alone. On device the 6,000 is the whole session, so the
    // system prompt, the folded turn, and room for the answer come out of it first.
    private func budget(for provider: AskProvider, question: String) -> Int {
        switch provider.kind {
        case .openAI:
            return AskContextBuilder.openAIBudget
        case .onDevice:
            let fixed = AskPrompt.system(today: now(), calendar: calendar).count
                + AskPrompt.folded(previous: previousTurn(), into: "").count
                + question.count
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
                    failureRaw: turn.failureRaw
                )
                context.insert(message)
                index += 1
            }
        }, in: context)
    }
}
