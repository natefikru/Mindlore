import Foundation
import Observation
import OSLog
import SwiftData

// Works through entries that are waiting for text, one at a time. Results are written only
// if the entry still exists and the user hasn't typed into it in the meantime.
@Observable
final class TranscriptionCoordinator {
    enum Activity: Equatable {
        case transcribing
        case failed(String)
        case unsupported(String)
    }

    private(set) var activity: [PersistentIdentifier: Activity] = [:]

    @ObservationIgnored private let logger = Logger(subsystem: "com.natefikru.mindlore", category: "transcription")
    @ObservationIgnored private let transcriber: any Transcriber
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private let temporaryDirectory: URL
    @ObservationIgnored private let save: (ModelContext) throws -> Void
    @ObservationIgnored private var isProcessing = false
    @ObservationIgnored private var needsAnotherPass = false

    init(
        transcriber: any Transcriber = SpeechAnalyzerTranscriber(),
        locale: Locale = .current,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        save: @escaping (ModelContext) throws -> Void = { try $0.saveStampingEntries() }
    ) {
        self.transcriber = transcriber
        self.locale = locale
        self.temporaryDirectory = temporaryDirectory
        self.save = save
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
            let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.awaitingText }, sortBy: [SortDescriptor(\.createdAt)])
            let pending = ((try? context.fetch(descriptor)) ?? []).map(\.persistentModelID)
            // Entries that already failed this session wait for an explicit retry.
            for id in pending where activity[id] == nil {
                await transcribe(id, context: context)
            }
        } while needsAnotherPass
    }

    func retry(_ id: PersistentIdentifier, context: ModelContext) async {
        activity[id] = nil
        await processQueue(context: context)
    }

    private func transcribe(_ id: PersistentIdentifier, context: ModelContext) async {
        guard let entry = Self.fetch(id, in: context), entry.awaitingText, let audio = entry.audioData else { return }
        activity[id] = .transcribing

        let url = temporaryDirectory
            .appendingPathComponent("transcribe-\(UUID().uuidString)")
            .appendingPathExtension(Self.fileExtension(for: audio))
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            try audio.write(to: url)
            let text = try await transcriber.transcribe(audioFileURL: url, locale: locale)
            // Empty text would mark the entry done with nothing in it; keep it waiting so the user can type.
            guard !text.isEmpty else { throw TranscriptionError.noSpeechDetected }
            activity[id] = nil
            // The await gave the user time to type into or delete the entry; re-fetch before touching it.
            guard let current = Self.fetch(id, in: context), current.applyGeneratedText(text) else { return }
            try save(context)
        } catch {
            // Error descriptions come from the frameworks and never include entry text.
            logger.error("Transcription failed: \(String(describing: error), privacy: .public)")
            if let error = error as? TranscriptionError {
                activity[id] = error.isPermanent ? .unsupported(error.userMessage) : .failed(error.userMessage)
            } else {
                activity[id] = .failed(TranscriptionError.analysisFailed(String(describing: error)).userMessage)
            }
        }
    }

    private static func fetch(_ id: PersistentIdentifier, in context: ModelContext) -> Entry? {
        var descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.persistentModelID == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // Converted audio is M4A; audio that couldn't be converted at ingest is still the recorded CAF.
    nonisolated static func fileExtension(for audio: Data) -> String {
        audio.count >= 8 && audio[audio.startIndex + 4..<audio.startIndex + 8] == Data("ftyp".utf8) ? "m4a" : "caf"
    }
}
