import AVFoundation
import Foundation
import Observation
import SwiftData
import UIKit

// Works through voice entries that are waiting for text, one at a time. Results are written only
// if the entry still exists and the user hasn't typed into it in the meantime. Attempts and
// failures are stored on the entry, so a relaunch never re-sends a recording without limit.
@Observable
final class TranscriptionCoordinator {
    enum Activity: Equatable {
        case transcribing
        case failed(String)
        case unsupported(String)
    }

    private(set) var activity: [PersistentIdentifier: Activity] = [:]
    // Set after a cloud request fails with no connection; cleared when the network returns.
    private(set) var pausedForOffline = false

    @ObservationIgnored var onTextReady: ((PersistentIdentifier) -> Void)?
    @ObservationIgnored private let route: (Entry, Bool) -> TranscriptionRoute
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private let temporaryDirectory: URL
    @ObservationIgnored private let save: (ModelContext) throws -> Void
    @ObservationIgnored private let diagnostics: DiagnosticsLog
    @ObservationIgnored private let chunkSearchSeconds: Double
    @ObservationIgnored private let beginBackgroundTask: (String) -> () -> Void
    @ObservationIgnored private var manualRetries: Set<PersistentIdentifier> = []
    @ObservationIgnored private var isProcessing = false
    @ObservationIgnored private var needsAnotherPass = false

    init(
        route: @escaping (Entry, Bool) -> TranscriptionRoute,
        locale: Locale = .current,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        save: @escaping (ModelContext) throws -> Void = { try $0.saveStampingEntries() },
        diagnostics: DiagnosticsLog = .shared,
        chunkSearchSeconds: Double = 15,
        beginBackgroundTask: @escaping (String) -> () -> Void = TranscriptionCoordinator.systemBackgroundTask
    ) {
        self.route = route
        self.locale = locale
        self.temporaryDirectory = temporaryDirectory
        self.save = save
        self.diagnostics = diagnostics
        self.chunkSearchSeconds = chunkSearchSeconds
        self.beginBackgroundTask = beginBackgroundTask
    }

    convenience init(
        transcriber: any Transcriber = SpeechAnalyzerTranscriber(),
        locale: Locale = .current,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        save: @escaping (ModelContext) throws -> Void = { try $0.saveStampingEntries() },
        diagnostics: DiagnosticsLog = .shared
    ) {
        self.init(route: { _, _ in .onDevice(transcriber) }, locale: locale, temporaryDirectory: temporaryDirectory, save: save, diagnostics: diagnostics)
    }

    static func systemBackgroundTask(_ name: String) -> () -> Void {
        let id = UIApplication.shared.beginBackgroundTask(withName: name)
        return { UIApplication.shared.endBackgroundTask(id) }
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
            let voice = EntrySource.voice.rawValue
            let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.awaitingText && $0.sourceRaw == voice }, sortBy: [SortDescriptor(\.createdAt)])
            let pending = (try? context.fetch(descriptor)) ?? []
            for entry in pending {
                let id = entry.persistentModelID
                let manual = manualRetries.contains(id)
                // Entries that already failed this session wait for an explicit retry.
                guard activity[id] == nil || manual else { continue }
                guard manual || AIJobPolicy.canRunAutomatically(.text, entry) else { continue }
                await transcribe(id, context: context)
            }
        } while needsAnotherPass
    }

    func retry(_ id: PersistentIdentifier, context: ModelContext) async {
        if let entry = Self.fetch(id, in: context) {
            AIJobPolicy.manualReset(.text, entry)
            try? save(context)
        }
        activity[id] = nil
        manualRetries.insert(id)
        await processQueue(context: context)
    }

    func networkBecameAvailable(context: ModelContext) async {
        guard pausedForOffline else { return }
        pausedForOffline = false
        activity = activity.filter { _, value in value == .transcribing }
        await processQueue(context: context)
    }

    private func transcribe(_ id: PersistentIdentifier, context: ModelContext) async {
        guard let entry = Self.fetch(id, in: context), entry.awaitingText, let audio = entry.audioData else { return }
        let manual = manualRetries.remove(id) != nil
        let route = route(entry, manual)
        // While offline, cloud-only work waits for the network instead of failing again.
        if route.cloud != nil, !route.fallBackToOnDevice, pausedForOffline { return }

        let entryID: DiagnosticValue = .id(entry.id)
        AIJobPolicy.recordAttempt(.text, entry)
        try? save(context)
        activity[id] = .transcribing
        diagnostics.record("transcription.started", [
            "id": entryID,
            "audioBytes": .int(audio.count),
            "locale": .string(locale.identifier),
            "engine": .string(route.cloud?.label ?? route.onDeviceLabel),
            "attempt": .int(entry.textAttempts),
        ])
        let started = ContinuousClock.now

        let url = temporaryDirectory
            .appendingPathComponent("transcribe-\(UUID().uuidString)")
            .appendingPathExtension(Self.fileExtension(for: audio))
        defer { try? FileManager.default.removeItem(at: url) }

        let text: String
        let generatedBy: String
        var fallbackReason: AIError?
        do {
            try audio.write(to: url)
            if let cloud = route.cloud {
                do {
                    text = try await transcribeInCloud(cloud, url: url, entryID: entryID)
                    generatedBy = cloud.label
                } catch {
                    let failure = AIJobFailure(any: error)
                    guard route.fallBackToOnDevice, let aiError = failure.aiError else { throw error }
                    diagnostics.record("transcription.fallback", ["id": entryID, "reason": .string(aiError.caseName)])
                    text = try await transcribeOnDevice(route.onDevice, url: url)
                    generatedBy = route.onDeviceLabel
                    fallbackReason = aiError
                }
            } else {
                text = try await transcribeOnDevice(route.onDevice, url: url)
                generatedBy = route.onDeviceLabel
            }
        } catch {
            recordFailure(error, id: id, entryID: entryID, context: context)
            return
        }
        activity[id] = nil

        // The await gave the user time to type into or delete the entry; re-fetch before touching it.
        guard let current = Self.fetch(id, in: context) else {
            diagnostics.record("transcription.discarded", ["id": entryID, "reason": "deleted"])
            return
        }
        guard current.applyGeneratedText(text, generatedBy: generatedBy) else {
            AIJobPolicy.recordSuccess(.text, current)
            try? save(context)
            diagnostics.record("transcription.discarded", ["id": entryID, "reason": "userTyped"])
            return
        }
        current.textFallbackReasonRaw = fallbackReason.map { AIJobFailure($0).raw }
        AIJobPolicy.recordSuccess(.text, current)
        let elapsed = started.duration(to: .now)
        do {
            try save(context)
            diagnostics.record("transcription.completed", [
                "id": entryID,
                "characters": .int(text.count),
                "engine": .string(generatedBy),
                "seconds": .double(Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18),
            ])
        } catch {
            // The text stays applied in memory and is written by the next save.
            diagnostics.record("transcription.saveFailed", ["id": entryID, "error": .errorCode(error)])
        }
        onTextReady?(id)
    }

    private func transcribeOnDevice(_ transcriber: any Transcriber, url: URL) async throws -> String {
        let text = try await transcriber.transcribe(audioFileURL: url, locale: locale)
        // Empty text would mark the entry done with nothing in it; keep it waiting so the user can type.
        guard !text.isEmpty else { throw TranscriptionError.noSpeechDetected }
        return text
    }

    private func transcribeInCloud(_ cloud: TranscriptionRoute.Cloud, url: URL, entryID: DiagnosticValue) async throws -> String {
        let endBackgroundTask = beginBackgroundTask("transcription")
        defer { endBackgroundTask() }

        let chunkDirectory = temporaryDirectory.appendingPathComponent("chunks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: chunkDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: chunkDirectory) }

        // OpenAI can't read CAF, and the chunker needs a file AVFoundation can split.
        let source: URL
        if url.pathExtension == "m4a" {
            source = url
        } else {
            source = chunkDirectory.appendingPathComponent("source.m4a")
            try OpenAICompatibleTranscriber.m4aData(for: url).write(to: source)
        }
        let bytes = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let duration = (try? AVAudioFile(forReading: source)).map { Double($0.length) / $0.fileFormat.sampleRate } ?? 0
        let byteTarget = Double(cloud.maxUploadBytes) * 0.9
        // Size limits are converted to seconds so one chunk plan satisfies both.
        let target = bytes > 0 && Double(bytes) > byteTarget && duration > 0
            ? min(cloud.chunkTargetSeconds, duration * byteTarget / Double(bytes))
            : cloud.chunkTargetSeconds

        let chunks = duration > target
            ? try await AudioChunker.split(source, targetSeconds: target, searchSeconds: min(chunkSearchSeconds, target / 4), outputDirectory: chunkDirectory)
            : [AudioChunker.Chunk(url: source, start: 0, duration: duration)]
        if chunks.count > 1 {
            diagnostics.record("transcription.chunks", ["id": entryID, "count": .int(chunks.count), "seconds": .string(chunks.map { String(format: "%.1f", $0.duration) }.joined(separator: ","))])
        }

        var texts: [String] = []
        for chunk in chunks {
            let prompt = texts.last.map { String($0.suffix(200)) }
            let requestStarted = ContinuousClock.now
            do {
                let text = try await cloud.makeTranscriber(prompt).transcribe(audioFileURL: chunk.url, locale: locale)
                diagnostics.record("ai.request", ["capability": "speech", "model": .string(cloud.label), "ok": true, "milliseconds": .int(Self.milliseconds(since: requestStarted))])
                texts.append(text)
            } catch TranscriptionError.noSpeechDetected where chunks.count > 1 {
                // A silent stretch of a long recording isn't a failure of the whole entry.
                continue
            } catch {
                let failure = AIJobFailure(any: error)
                diagnostics.record("ai.error", ["capability": "speech", "model": .string(cloud.label), "error": .string(failure.raw), "milliseconds": .int(Self.milliseconds(since: requestStarted))])
                throw error
            }
        }
        let joined = texts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !joined.isEmpty else { throw TranscriptionError.noSpeechDetected }
        return joined
    }

    private func recordFailure(_ error: any Error, id: PersistentIdentifier, entryID: DiagnosticValue, context: ModelContext) {
        let failure = AIJobFailure(any: error)
        if let current = Self.fetch(id, in: context) {
            AIJobPolicy.recordFailure(.text, current, failure)
            try? save(context)
        }
        let transcriptionError = failure.transcriptionError ?? .analysisFailed("")
        activity[id] = transcriptionError.isPermanent ? .unsupported(transcriptionError.userMessage) : .failed(transcriptionError.userMessage)
        if failure.isOffline {
            if !pausedForOffline {
                diagnostics.record("ai.offline", ["capability": "speech"])
            }
            pausedForOffline = true
        }
        // Stored failure names only: provider errors can quote the request.
        diagnostics.record("transcription.failed", ["id": entryID, "error": .string(failure.raw), "permanent": .bool(!failure.isRetryable)])
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        let elapsed = start.duration(to: .now)
        return Int(elapsed.components.seconds * 1_000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
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
