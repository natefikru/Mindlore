import Foundation
import Observation
import SwiftData

// Generates titles for entries flagged by the automatic pass or Run AI, one at a time.
@Observable
final class TitleCoordinator {
    struct Generator {
        let generator: any TextGenerator
        let model: String
        let label: String
    }

    static let maxInputCharacters = 4_000

    static let systemPrompt = """
    You write titles for entries in a personal journal. Reply with only the title: three to eight words \
    naming what the entry is about, in the author's language, with no quotation marks and no ending punctuation.
    """

    private(set) var running: Set<UUID> = []
    // Set by an offline failure so a queue of entries doesn't fire one doomed request each.
    private(set) var pausedForOffline = false

    @ObservationIgnored private let resolve: () -> Result<Generator, AIJobFailure>
    @ObservationIgnored private let presence: EditorPresence
    @ObservationIgnored private let save: (ModelContext) throws -> Void
    @ObservationIgnored private let diagnostics: DiagnosticsLog
    @ObservationIgnored private var failedThisSession: Set<UUID> = []
    // Titles that finished while their entry was open; applied once it closes, so the editor
    // never changes under the user's cursor.
    @ObservationIgnored private var heldTitles: [UUID: (title: String, revision: Int)] = [:]
    @ObservationIgnored private var isProcessing = false
    @ObservationIgnored private var needsAnotherPass = false

    init(
        resolve: @escaping () -> Result<Generator, AIJobFailure>,
        presence: EditorPresence,
        save: @escaping (ModelContext) throws -> Void = { try $0.saveStampingEntries() },
        diagnostics: DiagnosticsLog = .shared
    ) {
        self.resolve = resolve
        self.presence = presence
        self.save = save
        self.diagnostics = diagnostics
    }

    func processQueue(context: ModelContext) async {
        guard !isProcessing else {
            needsAnotherPass = true
            return
        }
        isProcessing = true
        defer { isProcessing = false }

        repeat {
            needsAnotherPass = false
            applyHeldTitles(context: context)
            let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.titlePending }, sortBy: [SortDescriptor(\.createdAt)])
            for entry in (try? context.fetch(descriptor)) ?? [] {
                guard !failedThisSession.contains(entry.id), !presence.isOpen(entry.id) else { continue }
                guard AIJobPolicy.canRunAutomatically(.title, entry), !pausedForOffline else { continue }
                // Only the phone that made an entry runs its jobs by itself (`LocalOrigin`); the
                // pending flag syncs. Run AI claims the entry, so it passes here.
                guard LocalOrigin.isLocal(entry) else { continue }
                await generate(entry.persistentModelID, context: context)
            }
        } while needsAnotherPass
    }

    // Run AI: start the title job over, unless the user typed a title.
    func runAI(for entry: Entry, context: ModelContext) async {
        guard !running.contains(entry.id), entry.title.isEmpty || entry.titleWasGenerated else { return }
        AIJobPolicy.manualReset(.title, entry)
        LocalOrigin.claim(entry)
        failedThisSession.remove(entry.id)
        try? save(context)
        await processQueue(context: context)
    }

    // Work that stopped because the phone was offline picks up as soon as the network is back,
    // without waiting for the next launch. Stored failures still gate what may run.
    func networkBecameAvailable(context: ModelContext) async {
        guard pausedForOffline || !failedThisSession.isEmpty else { return }
        pausedForOffline = false
        failedThisSession = []
        await processQueue(context: context)
    }

    private func generate(_ id: PersistentIdentifier, context: ModelContext) async {
        guard let entry = Self.fetch(id, in: context), entry.titlePending else { return }
        let entryID = entry.id
        guard entry.title.isEmpty || entry.titleWasGenerated else {
            AIJobPolicy.recordSuccess(.title, entry)
            try? save(context)
            return
        }
        let generator: Generator
        switch resolve() {
        case .success(let resolved):
            generator = resolved
        case .failure(let failure):
            AIJobPolicy.recordFailure(.title, entry, failure)
            failedThisSession.insert(entryID)
            try? save(context)
            diagnostics.record("title.unavailable", ["id": .id(entryID), "error": .string(failure.raw)])
            return
        }

        let revision = entry.contentRevision
        let input = String(entry.text.prefix(Self.maxInputCharacters))
        AIJobPolicy.recordAttempt(.title, entry)
        try? save(context)
        running.insert(entryID)
        diagnostics.record("title.started", ["id": .id(entryID), "model": .string(generator.label), "attempt": .int(entry.titleAttempts)])
        defer { running.remove(entryID) }

        let title: String
        do {
            let result = try await generator.generator.generate(TextRequest(model: generator.model, system: Self.systemPrompt, user: input, maxOutputTokens: 60))
            title = Self.clean(result.text)
            guard !title.isEmpty else { throw AIError.invalidResponse }
        } catch {
            let failure = AIJobFailure(any: error)
            if failure.isOffline {
                if !pausedForOffline { diagnostics.record("ai.offline", ["capability": "title"]) }
                pausedForOffline = true
            }
            if let current = Self.fetch(id, in: context) {
                AIJobPolicy.recordFailure(.title, current, failure)
                try? save(context)
            }
            failedThisSession.insert(entryID)
            diagnostics.record("title.failed", ["id": .id(entryID), "error": .string(failure.raw)])
            return
        }

        guard let current = Self.fetch(id, in: context), current.contentRevision == revision else {
            diagnostics.record("title.discarded", ["id": .id(entryID), "reason": "changed"])
            return
        }
        if presence.isOpen(entryID) {
            // Left pending on purpose: if the app dies before the entry closes, the title is
            // regenerated rather than silently lost.
            heldTitles[entryID] = (title, revision)
            diagnostics.record("title.held", ["id": .id(entryID)])
            return
        }
        AIJobPolicy.recordSuccess(.title, current)
        let applied = current.applyGeneratedTitle(title)
        try? save(context)
        diagnostics.record(applied ? "title.completed" : "title.discarded", ["id": .id(entryID), "words": .int(title.split(separator: " ").count)])
    }

    private func applyHeldTitles(context: ModelContext) {
        for (entryID, held) in heldTitles where !presence.isOpen(entryID) {
            heldTitles[entryID] = nil
            var descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == entryID })
            descriptor.fetchLimit = 1
            guard let entry = try? context.fetch(descriptor).first, entry.contentRevision == held.revision else { continue }
            if entry.applyGeneratedTitle(held.title) {
                AIJobPolicy.recordSuccess(.title, entry)
                try? save(context)
                diagnostics.record("title.completed", ["id": .id(entryID), "words": .int(held.title.split(separator: " ").count), "held": true])
            }
        }
    }

    // Models sometimes wrap titles in quotes, add a label, or end with a period.
    nonisolated static func clean(_ raw: String) -> String {
        var title = raw.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        title = title.trimmingCharacters(in: .whitespaces)
        if title.lowercased().hasPrefix("title:") {
            title = String(title.dropFirst(6))
        }
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’*#").union(.whitespaces))
        while let last = title.last, ".!,;:".contains(last) {
            title.removeLast()
        }
        return String(title.prefix(80)).trimmingCharacters(in: .whitespaces)
    }

    private static func fetch(_ id: PersistentIdentifier, in context: ModelContext) -> Entry? {
        var descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.persistentModelID == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
