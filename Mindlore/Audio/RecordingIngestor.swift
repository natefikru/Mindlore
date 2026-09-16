import AVFoundation
import Foundation
import SwiftData

nonisolated struct PreparedRecording: Sendable {
    let id: UUID
    let createdAt: Date
    let audioData: Data
    let duration: Double?
    let sourceBytes: Int
}

// Turns finished recording files into voice entries. The file's UUID becomes the entry's id,
// so ingesting the same file twice never creates a duplicate, and a file is only deleted
// once its entry is safely saved.
@Observable
final class RecordingIngestor {
    // Marks an entry whose text came from the live on-device session rather than a later pass.
    static let liveGeneratedBy = "apple.live"

    @ObservationIgnored private let save: (ModelContext) throws -> Void
    @ObservationIgnored private let diagnostics: DiagnosticsLog
    @ObservationIgnored private var inFlight: Set<URL> = []

    init(save: @escaping (ModelContext) throws -> Void = { try $0.saveStampingEntries() }, diagnostics: DiagnosticsLog = .shared) {
        self.save = save
        self.diagnostics = diagnostics
    }

    @discardableResult
    func ingestAll(in directory: RecordingsDirectory, context: ModelContext) async -> [Entry] {
        guard let files = try? directory.finishedFiles() else { return [] }
        var entries: [Entry] = []
        for file in files {
            if let entry = await ingest(file, context: context) {
                entries.append(entry)
            }
        }
        return entries
    }

    // `liveText` is text a live transcriber produced while the user was speaking. When it's
    // there the entry is already finished, so nothing queues it for transcription again.
    func ingest(_ fileURL: URL, context: ModelContext, liveText: String? = nil) async -> Entry? {
        let file: DiagnosticValue = .string(fileURL.lastPathComponent)
        guard !inFlight.contains(fileURL) else {
            diagnostics.record("ingest.skipped", ["file": file, "reason": "inFlight"])
            return nil
        }
        inFlight.insert(fileURL)
        defer { inFlight.remove(fileURL) }

        let prepared: PreparedRecording
        switch await Self.prepare(fileURL: fileURL) {
        case .empty:
            try? FileManager.default.removeItem(at: fileURL)
            diagnostics.record("ingest.skipped", ["file": file, "reason": "empty"])
            return nil
        case .unreadable:
            // Could be temporary (file protection before first unlock, an I/O error); try again next launch.
            diagnostics.record("ingest.skipped", ["file": file, "reason": "unreadable"])
            return nil
        case .ready(let recording):
            prepared = recording
        }

        let id = prepared.id
        if let existing = try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id })).first {
            try? FileManager.default.removeItem(at: fileURL)
            diagnostics.record("ingest.skipped", ["file": file, "reason": "duplicate", "id": .id(id)])
            return existing
        }

        let live = liveText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasLiveText = !(live ?? "").isEmpty
        let entry = Entry(
            id: prepared.id,
            createdAt: prepared.createdAt,
            source: .voice,
            text: live ?? "",
            awaitingText: !hasLiveText,
            audioData: prepared.audioData,
            audioDuration: prepared.duration
        )
        if hasLiveText {
            entry.textWasGenerated = true
            entry.textGeneratedBy = Self.liveGeneratedBy
        }
        context.insert(entry)
        do {
            try save(context)
        } catch {
            // Remove only this insert; rolling back the context would also drop unsaved typing elsewhere.
            context.delete(entry)
            diagnostics.record("ingest.saveFailed", ["file": file, "id": .id(id), "error": .errorCode(error)])
            return nil
        }
        try? FileManager.default.removeItem(at: fileURL)
        var fields: [String: DiagnosticValue] = [
            "id": .id(id),
            "sourceBytes": .int(prepared.sourceBytes),
            "audioBytes": .int(prepared.audioData.count),
            "converted": .bool(prepared.duration != nil),
            "liveText": .bool(hasLiveText),
        ]
        if let duration = prepared.duration { fields["seconds"] = .double(duration) }
        diagnostics.record("ingest.completed", fields)
        return entry
    }

    nonisolated enum PrepareOutcome: Sendable {
        case empty
        case unreadable
        case ready(PreparedRecording)
    }

    // Only a file that is known to be zero bytes is safe to throw away.
    @concurrent
    nonisolated static func prepare(fileURL: URL) async -> PrepareOutcome {
        let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
        if size == 0 { return .empty }
        guard let raw = try? Data(contentsOf: fileURL), !raw.isEmpty else { return .unreadable }
        let id = UUID(uuidString: fileURL.deletingPathExtension().lastPathComponent) ?? UUID()
        let createdAt = (try? fileURL.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()

        if let converted = try? AudioConverter.convertToAAC(fileURL) {
            return .ready(PreparedRecording(id: id, createdAt: createdAt, audioData: converted.data, duration: converted.duration, sourceBytes: raw.count))
        }
        // Keep audio we can't decode rather than delete something the user recorded.
        return .ready(PreparedRecording(id: id, createdAt: createdAt, audioData: raw, duration: nil, sourceBytes: raw.count))
    }
}

nonisolated enum AudioConverter {
    struct Converted {
        let data: Data
        let duration: Double
    }

    enum ConversionError: Error {
        case emptyAudio
    }

    static let aacSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 24_000,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 48_000,
    ]

    static func convertToAAC(_ sourceURL: URL) throws -> Converted {
        let source = try AVAudioFile(forReading: sourceURL)
        guard source.length > 0 else { throw ConversionError.emptyAudio }
        let duration = Double(source.length) / source.fileFormat.sampleRate

        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        defer { try? FileManager.default.removeItem(at: destinationURL) }

        let destination = try AVAudioFile(
            forWriting: destinationURL,
            settings: aacSettings,
            commonFormat: source.processingFormat.commonFormat,
            interleaved: source.processingFormat.isInterleaved
        )
        let chunkFrames: AVAudioFrameCount = 24_000
        guard let buffer = AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: chunkFrames) else {
            throw ConversionError.emptyAudio
        }
        while source.framePosition < source.length {
            try source.read(into: buffer, frameCount: chunkFrames)
            if buffer.frameLength == 0 { break }
            try destination.write(from: buffer)
        }
        destination.close()

        return Converted(data: try Data(contentsOf: destinationURL), duration: duration)
    }
}
