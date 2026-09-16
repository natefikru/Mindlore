import AVFoundation
import Foundation

// Splits long recordings for providers with a per-request duration limit, cutting at the quietest
// moment near each boundary so words aren't cut in half.
nonisolated enum AudioChunker {
    static let windowSeconds = 0.05

    struct Chunk: Sendable {
        let url: URL
        let start: Double
        let duration: Double
    }

    enum ChunkError: Error {
        case unreadableAudio
        case exportFailed
    }

    // Cut times in seconds. `levels` holds the RMS of consecutive windows of `windowSeconds`.
    static func boundaries(levels: [Float], duration: Double, targetSeconds: Double, searchSeconds: Double) -> [Double] {
        guard duration > targetSeconds else { return [] }
        var cuts: [Double] = []
        var chunkStart = 0.0
        while duration - chunkStart > targetSeconds {
            let target = chunkStart + targetSeconds
            let lower = max(chunkStart + windowSeconds, target - searchSeconds)
            let upper = min(duration - windowSeconds, target + searchSeconds)
            let lowerIndex = max(0, Int(lower / windowSeconds))
            let upperIndex = min(levels.count - 1, Int(upper / windowSeconds))
            var best = Int(target / windowSeconds)
            if lowerIndex <= upperIndex {
                best = lowerIndex
                for index in lowerIndex...upperIndex where levels[index] < levels[best] {
                    best = index
                }
            }
            let cut = min(max((Double(best) + 0.5) * windowSeconds, chunkStart + windowSeconds), duration)
            cuts.append(cut)
            chunkStart = cut
        }
        return cuts
    }

    static func levels(of url: URL) throws -> (levels: [Float], duration: Double) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let duration = Double(file.length) / format.sampleRate
        let windowFrames = AVAudioFrameCount(max(1, (format.sampleRate * windowSeconds).rounded()))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: windowFrames) else { throw ChunkError.unreadableAudio }
        var levels: [Float] = []
        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: windowFrames)
            guard buffer.frameLength > 0, let channel = buffer.floatChannelData?[0] else { break }
            var sum: Float = 0
            for index in 0..<Int(buffer.frameLength) {
                sum += channel[index] * channel[index]
            }
            levels.append((sum / Float(buffer.frameLength)).squareRoot())
        }
        return (levels, duration)
    }

    // Returns the source as a single chunk when it's short enough.
    @concurrent
    static func split(_ url: URL, targetSeconds: Double, searchSeconds: Double, outputDirectory: URL) async throws -> [Chunk] {
        let (levels, duration) = try levels(of: url)
        let cuts = boundaries(levels: levels, duration: duration, targetSeconds: targetSeconds, searchSeconds: searchSeconds)
        guard !cuts.isEmpty else { return [Chunk(url: url, start: 0, duration: duration)] }

        let asset = AVURLAsset(url: url)
        let edges = [0] + cuts + [duration]
        var chunks: [Chunk] = []
        for index in 0..<(edges.count - 1) {
            let start = edges[index]
            let end = edges[index + 1]
            let output = outputDirectory.appendingPathComponent("chunk-\(UUID().uuidString).m4a")
            guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { throw ChunkError.exportFailed }
            session.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))
            do {
                try await session.export(to: output, as: .m4a)
            } catch {
                chunks.forEach { try? FileManager.default.removeItem(at: $0.url) }
                throw ChunkError.exportFailed
            }
            chunks.append(Chunk(url: output, start: start, duration: end - start))
        }
        return chunks
    }
}
