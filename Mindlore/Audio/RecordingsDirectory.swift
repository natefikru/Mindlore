import Foundation

// In-flight recordings live in active/, finished ones wait in finished/ until they become entries.
// A file left in active/ after launch means the app died mid-recording.
nonisolated struct RecordingsDirectory: Sendable {
    static let fileExtension = "caf"
    static let standard = RecordingsDirectory(root: URL.applicationSupportDirectory.appendingPathComponent("Recordings", isDirectory: true))

    let root: URL

    var active: URL { root.appendingPathComponent("active", isDirectory: true) }
    var finished: URL { root.appendingPathComponent("finished", isDirectory: true) }

    func prepare() throws {
        let fileManager = FileManager.default
        for directory in [root, active, finished] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        // Converted audio is stored in the database, which is backed up; raw PCM would only bloat backups.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var rootURL = root
        try rootURL.setResourceValues(values)
    }

    func newActiveFileURL(id: UUID = UUID()) throws -> URL {
        try prepare()
        return active.appendingPathComponent(id.uuidString).appendingPathExtension(Self.fileExtension)
    }

    func moveToFinished(_ url: URL) throws -> URL {
        try prepare()
        let destination = finished.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }

    // Only call at launch, before any recording can start, or it would move a file that is still being written.
    @discardableResult
    func recoverInterruptedRecordings() throws -> [URL] {
        try prepare()
        return try audioFiles(in: active).map(moveToFinished)
    }

    func finishedFiles() throws -> [URL] {
        try prepare()
        return try audioFiles(in: finished)
    }

    private func audioFiles(in directory: URL) throws -> [URL] {
        try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])
            .filter { $0.pathExtension == Self.fileExtension }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
