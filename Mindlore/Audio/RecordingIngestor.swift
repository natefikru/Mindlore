import AVFoundation
import Foundation
import SwiftData

nonisolated struct PreparedRecording: Sendable {
    let id: UUID
    let createdAt: Date
    let audioData: Data
    let duration: Double?
}

// Turns finished recording files into voice entries. The file's UUID becomes the entry's id,
// so ingesting the same file twice never creates a duplicate, and a file is only deleted
// once its entry is safely saved.
@Observable
final class RecordingIngestor {
    @ObservationIgnored private let save: (ModelContext) throws -> Void
    @ObservationIgnored private var inFlight: Set<URL> = []

    init(save: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.save = save
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

    func ingest(_ fileURL: URL, context: ModelContext) async -> Entry? {
        guard !inFlight.contains(fileURL) else { return nil }
        inFlight.insert(fileURL)
        defer { inFlight.remove(fileURL) }

        guard let prepared = await Self.prepare(fileURL: fileURL) else {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }

        let id = prepared.id
        if let existing = try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id })).first {
            try? FileManager.default.removeItem(at: fileURL)
            return existing
        }

        let entry = Entry(
            id: prepared.id,
            createdAt: prepared.createdAt,
            source: .voice,
            awaitingText: true,
            audioData: prepared.audioData,
            audioDuration: prepared.duration
        )
        context.insert(entry)
        do {
            try save(context)
        } catch {
            // Remove only this insert; rolling back the context would also drop unsaved typing elsewhere.
            context.delete(entry)
            return nil
        }
        try? FileManager.default.removeItem(at: fileURL)
        return entry
    }

    // Returns nil for an empty file, which holds no audio worth keeping.
    @concurrent
    nonisolated static func prepare(fileURL: URL) async -> PreparedRecording? {
        guard let raw = try? Data(contentsOf: fileURL), !raw.isEmpty else { return nil }
        let id = UUID(uuidString: fileURL.deletingPathExtension().lastPathComponent) ?? UUID()
        let createdAt = (try? fileURL.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()

        if let converted = try? AudioConverter.convertToAAC(fileURL) {
            return PreparedRecording(id: id, createdAt: createdAt, audioData: converted.data, duration: converted.duration)
        }
        // Keep audio we can't decode rather than delete something the user recorded.
        return PreparedRecording(id: id, createdAt: createdAt, audioData: raw, duration: nil)
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
