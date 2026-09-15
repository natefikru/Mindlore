import AVFoundation
import Foundation
import SwiftData
import Testing
@testable import Mindlore

@MainActor
enum AudioFixtures {
    // Writes 24 kHz mono 16-bit PCM CAF, the format AudioRecorder produces.
    static func writePCM(to url: URL, seconds: Double, close: Bool = true) throws -> AVAudioFile {
        let file = try AVAudioFile(forWriting: url, settings: AudioRecorder.recordingSettings, commonFormat: .pcmFormatInt16, interleaved: true)
        let frames = AVAudioFrameCount(seconds * 24_000)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames)!
        buffer.frameLength = frames
        for index in 0..<Int(frames) {
            buffer.int16ChannelData![0][index] = Int16(sin(Double(index) / 8) * 6_000)
        }
        try file.write(from: buffer)
        if close { file.close() }
        return file
    }
}

@MainActor
final class IngestHarness {
    let root: URL
    let directory: RecordingsDirectory
    let container: ModelContainer
    var failSaves = false
    private(set) var ingestor: RecordingIngestor!

    var context: ModelContext { container.mainContext }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("RecordingIngestorTests-\(UUID().uuidString)", isDirectory: true)
        directory = RecordingsDirectory(root: root)
        try directory.prepare()
        container = try ModelContainerFactory.make(.inMemory)
        ingestor = RecordingIngestor(save: { [unowned self] context in
            if self.failSaves { throw SaveFailure() }
            try context.save()
        })
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func finishedFile(id: UUID = UUID(), seconds: Double = 0.5) throws -> URL {
        let url = directory.finished.appendingPathComponent(id.uuidString).appendingPathExtension("caf")
        _ = try AudioFixtures.writePCM(to: url, seconds: seconds)
        return url
    }

    func entries() throws -> [Entry] {
        try context.fetch(FetchDescriptor<Entry>())
    }
}

@MainActor
struct RecordingIngestorTests {
    @Test func ingestCreatesAVoiceEntryWithCompressedAudioAndRemovesTheFile() async throws {
        let harness = try IngestHarness()
        let id = UUID()
        // Long enough that the m4a container's fixed ~33 KB overhead doesn't hide the compression ratio.
        let file = try harness.finishedFile(id: id, seconds: 10.0)
        let pcmSize = try Data(contentsOf: file).count

        let entry = try #require(await harness.ingestor.ingest(file, context: harness.context))

        #expect(entry.id == id)
        #expect(entry.source == .voice)
        #expect(entry.awaitingText)
        #expect(entry.text.isEmpty)
        let audio = try #require(entry.audioData)
        #expect(String(decoding: audio[4..<8], as: UTF8.self) == "ftyp")
        #expect(audio.count < pcmSize / 4)
        #expect(abs((entry.audioDuration ?? 0) - 10.0) < 0.01)
        #expect(FileManager.default.fileExists(atPath: file.path) == false)
        #expect(try harness.entries().count == 1)
    }

    @Test func convertedAudioIsPlayable() async throws {
        let harness = try IngestHarness()
        let entry = try #require(await harness.ingestor.ingest(try harness.finishedFile(seconds: 0.5), context: harness.context))

        let player = try AVAudioPlayer(data: try #require(entry.audioData))
        #expect(abs(player.duration - 0.5) < 0.1)
    }

    @Test func entryTakesTheRecordingsCreationDate() async throws {
        let harness = try IngestHarness()
        let file = try harness.finishedFile()
        let recordedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.creationDate: recordedAt], ofItemAtPath: file.path)

        let entry = try #require(await harness.ingestor.ingest(file, context: harness.context))

        #expect(entry.createdAt == recordedAt)
    }

    @Test func existingEntryWithTheSameIDIsNotDuplicated() async throws {
        let harness = try IngestHarness()
        let id = UUID()
        harness.context.insert(Entry(id: id, source: .voice, text: "already here"))
        try harness.context.save()
        let file = try harness.finishedFile(id: id)

        let entry = await harness.ingestor.ingest(file, context: harness.context)

        #expect(entry?.text == "already here")
        #expect(try harness.entries().count == 1)
        #expect(FileManager.default.fileExists(atPath: file.path) == false)
    }

    @Test func ingestingTheSameFileTwiceAtOnceCreatesOneEntry() async throws {
        let harness = try IngestHarness()
        let file = try harness.finishedFile()

        let first = Task { _ = await harness.ingestor.ingest(file, context: harness.context) }
        let second = Task { _ = await harness.ingestor.ingest(file, context: harness.context) }
        await first.value
        await second.value

        #expect(try harness.entries().count == 1)
    }

    @Test func emptyFileIsDeletedWithoutAnEntry() async throws {
        let harness = try IngestHarness()
        let file = harness.directory.finished.appendingPathComponent("\(UUID().uuidString).caf")
        FileManager.default.createFile(atPath: file.path, contents: Data())

        let entry = await harness.ingestor.ingest(file, context: harness.context)

        #expect(entry == nil)
        #expect(try harness.entries().isEmpty)
        #expect(FileManager.default.fileExists(atPath: file.path) == false)
    }

    @Test func undecodableAudioIsKeptRatherThanDeleted() async throws {
        let harness = try IngestHarness()
        let file = harness.directory.finished.appendingPathComponent("\(UUID().uuidString).caf")
        let garbage = Data((0..<2_000).map { UInt8($0 % 251) })
        FileManager.default.createFile(atPath: file.path, contents: garbage)

        let entry = try #require(await harness.ingestor.ingest(file, context: harness.context))

        #expect(entry.audioData == garbage)
        #expect(entry.audioDuration == nil)
        #expect(entry.awaitingText)
    }

    @Test func failedSaveKeepsTheFileForTheNextLaunch() async throws {
        let harness = try IngestHarness()
        let file = try harness.finishedFile()
        harness.failSaves = true

        let entry = await harness.ingestor.ingest(file, context: harness.context)

        #expect(entry == nil)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(try harness.entries().isEmpty)

        harness.failSaves = false
        #expect(await harness.ingestor.ingest(file, context: harness.context) != nil)
        #expect(FileManager.default.fileExists(atPath: file.path) == false)
    }

    @Test func failedSaveDoesNotDiscardOtherUnsavedEdits() async throws {
        let harness = try IngestHarness()
        let typed = Entry(text: "saved once")
        harness.context.insert(typed)
        try harness.context.save()
        typed.text = "unsaved typing"
        harness.failSaves = true

        _ = await harness.ingestor.ingest(try harness.finishedFile(), context: harness.context)

        #expect(typed.text == "unsaved typing")
    }

    // A file copied while still being written is exactly what a killed app leaves behind.
    @Test func recordingInterruptedMidWriteIsRecoveredWithItsAudio() async throws {
        let harness = try IngestHarness()
        let id = UUID()
        let live = harness.root.appendingPathComponent("live.caf")
        let stillOpen = try AudioFixtures.writePCM(to: live, seconds: 2.0, close: false)
        let orphan = harness.directory.active.appendingPathComponent(id.uuidString).appendingPathExtension("caf")
        try FileManager.default.copyItem(at: live, to: orphan)
        stillOpen.close()

        try harness.directory.recoverInterruptedRecordings()
        let entries = await harness.ingestor.ingestAll(in: harness.directory, context: harness.context)

        #expect(entries.map(\.id) == [id])
        #expect(abs((entries.first?.audioDuration ?? 0) - 2.0) < 0.01)
        #expect(try harness.directory.finishedFiles().isEmpty)
    }

    @Test func ingestAllProcessesEveryFinishedFile() async throws {
        let harness = try IngestHarness()
        let ids = [UUID(), UUID(), UUID()]
        for id in ids { _ = try harness.finishedFile(id: id, seconds: 0.2) }

        let entries = await harness.ingestor.ingestAll(in: harness.directory, context: harness.context)

        #expect(Set(entries.map(\.id)) == Set(ids))
        #expect(try harness.directory.finishedFiles().isEmpty)
    }
}

@MainActor
struct RecordingsDirectoryTests {
    private func makeDirectory() -> RecordingsDirectory {
        RecordingsDirectory(root: FileManager.default.temporaryDirectory.appendingPathComponent("RecordingsDirectoryTests-\(UUID().uuidString)", isDirectory: true))
    }

    @Test func prepareCreatesFoldersExcludedFromBackup() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory.root) }

        try directory.prepare()

        #expect(FileManager.default.fileExists(atPath: directory.active.path))
        #expect(FileManager.default.fileExists(atPath: directory.finished.path))
        #expect(try directory.root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test func newActiveFilesUseTheGivenIDAndCAF() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory.root) }
        let id = UUID()

        let url = try directory.newActiveFileURL(id: id)

        #expect(url.deletingLastPathComponent().standardizedFileURL == directory.active.standardizedFileURL)
        #expect(url.lastPathComponent == "\(id.uuidString).caf")
    }

    @Test func recoverMovesEveryActiveRecordingToFinished() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory.root) }
        let first = try directory.newActiveFileURL()
        let second = try directory.newActiveFileURL()
        FileManager.default.createFile(atPath: first.path, contents: Data([1]))
        FileManager.default.createFile(atPath: second.path, contents: Data([2]))

        let moved = try directory.recoverInterruptedRecordings()

        #expect(moved.count == 2)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.active.path).isEmpty)
        #expect(Set(try directory.finishedFiles().map(\.lastPathComponent)) == Set([first.lastPathComponent, second.lastPathComponent]))
    }

    @Test func finishedFilesIgnoresOtherFileTypes() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory.root) }
        try directory.prepare()
        FileManager.default.createFile(atPath: directory.finished.appendingPathComponent("notes.txt").path, contents: Data([1]))
        FileManager.default.createFile(atPath: directory.finished.appendingPathComponent("\(UUID().uuidString).caf").path, contents: Data([1]))

        #expect(try directory.finishedFiles().count == 1)
    }
}

struct AudioRecorderLevelTests {
    @Test(arguments: [
        (Float(-160), Float(0)),
        (Float(-50), Float(0)),
        (Float(-25), Float(0.5)),
        (Float(0), Float(1)),
        (Float(6), Float(1)),
        (Float.nan, Float(0)),
    ])
    @MainActor
    func decibelsMapToZeroToOne(decibels: Float, expected: Float) {
        #expect(abs(AudioRecorder.normalizedLevel(decibels: decibels) - expected) < 0.001)
    }
}
