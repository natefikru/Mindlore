import Foundation
import Observation
import SwiftData

// Transcribes confirmed photo entries page by page. Each page's text is saved as it arrives, so a
// failure resends only the pages still missing, and the finished text waits for the user's review.
@Observable
final class PageTranscriptionCoordinator {
    struct Transcription {
        let transcriber: any PageTranscriber
        let label: String
    }

    enum Activity: Equatable {
        case transcribing(page: Int, of: Int)
        case failed(String)
    }

    // Beyond the pages themselves, a few repeats are allowed for failures before automatic runs stop.
    nonisolated static let extraRequestsAllowed = 3
    nonisolated static let requestCapFailure = AIJobFailure(raw: "pages.requestCap")

    private(set) var activity: [UUID: Activity] = [:]
    private(set) var pausedForOffline = false

    @ObservationIgnored private let resolve: () -> Result<Transcription, AIJobFailure>
    @ObservationIgnored private let suggestEntryDates: () -> Bool
    @ObservationIgnored private let autoApplyEntryDate: () -> Bool
    @ObservationIgnored private let save: (ModelContext) throws -> Void
    @ObservationIgnored private let diagnostics: DiagnosticsLog
    @ObservationIgnored private let beginBackgroundTask: (String) -> () -> Void
    @ObservationIgnored private let prepareUpload: @Sendable (Data) async throws -> Data
    @ObservationIgnored private var manualRuns: Set<UUID> = []
    @ObservationIgnored private var isProcessing = false
    @ObservationIgnored private var needsAnotherPass = false

    init(
        resolve: @escaping () -> Result<Transcription, AIJobFailure>,
        suggestEntryDates: @escaping () -> Bool = { true },
        autoApplyEntryDate: @escaping () -> Bool = { false },
        save: @escaping (ModelContext) throws -> Void = { try $0.saveStampingEntries() },
        diagnostics: DiagnosticsLog = .shared,
        beginBackgroundTask: @escaping (String) -> () -> Void = TranscriptionCoordinator.systemBackgroundTask,
        prepareUpload: @escaping @Sendable (Data) async throws -> Data = PageTranscriptionCoordinator.uploadJPEG
    ) {
        self.resolve = resolve
        self.suggestEntryDates = suggestEntryDates
        self.autoApplyEntryDate = autoApplyEntryDate
        self.save = save
        self.diagnostics = diagnostics
        self.beginBackgroundTask = beginBackgroundTask
        self.prepareUpload = prepareUpload
    }

    @concurrent
    nonisolated static func uploadJPEG(_ stored: Data) async throws -> Data {
        try PageImageProcessor.uploadJPEG(from: stored)
    }

    func isRunning(_ entry: Entry) -> Bool {
        if case .transcribing = activity[entry.id] { true } else { false }
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
            let photo = EntrySource.photo.rawValue
            let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.awaitingText && $0.pagesConfirmed && $0.sourceRaw == photo }, sortBy: [SortDescriptor(\.createdAt)])
            for entry in (try? context.fetch(descriptor)) ?? [] {
                let manual = manualRuns.contains(entry.id)
                guard activity[entry.id] == nil || manual else { continue }
                guard manual || (AIJobPolicy.canRunAutomatically(.text, entry) && !pausedForOffline) else { continue }
                await transcribe(entry.persistentModelID, context: context)
            }
        } while needsAnotherPass
    }

    // Retry, or "Transcribe pages" on an entry whose pages were saved while AI was off.
    func transcribePages(for entry: Entry, context: ModelContext) async {
        guard entry.source == .photo, entry.pagesConfirmed, !isRunning(entry) else { return }
        // Only an empty entry takes the result directly; otherwise typed text would be overwritten.
        guard entry.awaitingText || entry.text.isEmpty else { return }
        AIJobPolicy.manualReset(.text, entry)
        entry.pageRequestCount = 0
        entry.awaitingText = true
        try? save(context)
        activity[entry.id] = nil
        manualRuns.insert(entry.id)
        await processQueue(context: context)
    }

    func networkBecameAvailable(context: ModelContext) async {
        guard pausedForOffline else { return }
        pausedForOffline = false
        activity = activity.filter { _, value in if case .transcribing = value { true } else { false } }
        await processQueue(context: context)
    }

    private func transcribe(_ id: PersistentIdentifier, context: ModelContext) async {
        guard let entry = Self.fetch(id, in: context), entry.awaitingText, entry.pagesConfirmed else { return }
        let entryID = entry.id
        manualRuns.remove(entryID)

        let transcription: Transcription
        switch resolve() {
        case .success(let resolved):
            transcription = resolved
        case .failure(let failure):
            // AI turned off or no key: the entry waits, and the editor explains why.
            activity[entryID] = .failed(failure.userMessage)
            diagnostics.record("pages.transcription.unavailable", ["id": .id(entryID), "error": .string(failure.raw)])
            return
        }

        let pageCount = entry.sortedPages.count
        guard entry.pageRequestCount < pageCount + Self.extraRequestsAllowed else {
            AIJobPolicy.recordFailure(.text, entry, Self.requestCapFailure)
            try? save(context)
            activity[entryID] = .failed(Self.requestCapFailure.userMessage)
            return
        }

        let revision = entry.contentRevision
        AIJobPolicy.recordAttempt(.text, entry)
        try? save(context)
        let endBackgroundTask = beginBackgroundTask("pages")
        defer { endBackgroundTask() }
        diagnostics.record("pages.transcription.started", ["id": .id(entryID), "pages": .int(pageCount), "attempt": .int(entry.textAttempts), "model": .string(transcription.label)])

        var savedAPage = false
        do {
            for position in 0..<pageCount {
                guard let current = Self.fetch(id, in: context), current.contentRevision == revision, current.pagesConfirmed else {
                    return drop(entryID, reason: "restarted")
                }
                let pages = current.sortedPages
                guard position < pages.count else { return drop(entryID, reason: "pagesChanged") }
                let page = pages[position]
                guard page.transcribedText == nil else { continue }
                guard let stored = page.imageData else { throw AIError.invalidResponse }
                guard current.pageRequestCount < pageCount + Self.extraRequestsAllowed else { throw Self.requestCapFailure }

                let pageID = page.persistentModelID
                let tail = position > 0 ? pages[position - 1].transcribedText.map(OpenAICompatiblePageTranscriber.tail(of:)) : nil
                activity[entryID] = .transcribing(page: position + 1, of: pageCount)
                let upload = try await prepareUpload(stored)
                current.pageRequestCount += 1
                try? save(context)

                let started = ContinuousClock.now
                let result = try await transcription.transcriber.transcribe(PageRequest(imageJPEG: upload, pageNumber: position + 1, pageCount: pageCount, previousPageTail: tail))

                // The user may have edited or restarted the pages while this page was out.
                guard let after = Self.fetch(id, in: context), after.contentRevision == revision, after.pagesConfirmed,
                      let samePage = after.sortedPages.first(where: { $0.persistentModelID == pageID }), samePage.index == position else {
                    return drop(entryID, reason: "restarted")
                }
                samePage.transcribedText = result.text
                samePage.writtenDate = result.writtenDate
                try? save(context)
                savedAPage = true
                diagnostics.record("pages.transcription.pageCompleted", [
                    "id": .id(entryID),
                    "page": .int(position + 1),
                    "uploadBytes": .int(upload.count),
                    "milliseconds": .int(Int(started.duration(to: .now).components.seconds * 1_000)),
                    "inputTokens": .int(result.inputTokens ?? -1),
                    "outputTokens": .int(result.outputTokens ?? -1),
                ])
            }
        } catch {
            let failure = error as? AIJobFailure ?? AIJobFailure(any: error)
            if let current = Self.fetch(id, in: context) {
                // A pass that finished pages made progress, so it doesn't use up an attempt.
                if savedAPage {
                    current.textAttempts = max(0, current.textAttempts - 1)
                }
                AIJobPolicy.recordFailure(.text, current, failure)
                try? save(context)
            }
            activity[entryID] = .failed(failure.userMessage)
            if failure.isOffline {
                if !pausedForOffline { diagnostics.record("ai.offline", ["capability": "pages"]) }
                pausedForOffline = true
            }
            diagnostics.record("pages.transcription.failed", ["id": .id(entryID), "error": .string(failure.raw)])
            return
        }

        activity[entryID] = nil
        pausedForOffline = false
        guard let finished = Self.fetch(id, in: context), finished.contentRevision == revision else {
            return drop(entryID, reason: "restarted")
        }
        // If the user typed meanwhile, their text stays; the pages keep theirs for "Replace".
        let applied = finished.applyGeneratedText(finished.joinedPageText, generatedBy: transcription.label)
        if applied {
            finished.textReviewPending = true
            if suggestEntryDates(), let written = finished.sortedPages.compactMap(\.writtenDate).first,
               finished.storeSuggestedEntryDate(written) {
                if autoApplyEntryDate() {
                    finished.acceptSuggestedEntryDate()
                    diagnostics.record("entryDate.changed", ["id": .id(entryID), "reason": "auto", "source": "page"])
                } else {
                    diagnostics.record("entryDate.suggested", ["id": .id(entryID), "source": "page"])
                }
            }
        }
        AIJobPolicy.recordSuccess(.text, finished)
        try? save(context)
        diagnostics.record("pages.transcription.completed", ["id": .id(entryID), "pages": .int(pageCount), "applied": .bool(applied)])
    }

    private func drop(_ entryID: UUID, reason: String) {
        activity[entryID] = nil
        diagnostics.record("pages.transcription.dropped", ["id": .id(entryID), "reason": .string(reason)])
    }

    private static func fetch(_ id: PersistentIdentifier, in context: ModelContext) -> Entry? {
        var descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.persistentModelID == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
