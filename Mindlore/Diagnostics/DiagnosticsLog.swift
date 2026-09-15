import Foundation
import Synchronization

nonisolated enum DiagnosticValue: Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    static func id(_ id: UUID) -> DiagnosticValue { .string(id.uuidString) }

    // Only for errors from audio and speech frameworks. Save errors go through `errorCode`,
    // because SwiftData validation errors can embed model values, including entry text.
    static func error(_ error: any Error) -> DiagnosticValue { .string(String(describing: error)) }

    static func errorCode(_ error: any Error) -> DiagnosticValue {
        let nsError = error as NSError
        return .string("\(nsError.domain) \(nsError.code)")
    }

    var jsonValue: Any {
        switch self {
        case .string(let value): value
        case .int(let value): value
        case .double(let value): value
        case .bool(let value): value
        }
    }
}

nonisolated extension DiagnosticValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral {
    init(stringLiteral value: String) { self = .string(value) }
    init(integerLiteral value: Int) { self = .int(value) }
    init(floatLiteral value: Double) { self = .double(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
}

// Debug-build event log for device smoke tests. One JSON object per line, written synchronously
// so events leading up to a force-quit or crash are on disk. Never log entry text.
nonisolated final class DiagnosticsLog: Sendable {
    static let shared = DiagnosticsLog.makeShared()
    static let disabled = DiagnosticsLog(fileURL: nil)
    static let defaultFileURL = URL.libraryDirectory
        .appendingPathComponent("Logs/Mindlore", isDirectory: true)
        .appendingPathComponent("diagnostics.jsonl")
    static let consolePrefix = "MINDLORE "

    let session: String
    private let fileURL: URL?
    private let mirrorToStandardError: Bool
    private let maxBytes: Int
    private let handle = Mutex<FileHandle?>(nil)

    init(fileURL: URL?, mirrorToStandardError: Bool = false, maxBytes: Int = 5_000_000, session: String = String(UUID().uuidString.prefix(8))) {
        self.fileURL = fileURL
        self.mirrorToStandardError = mirrorToStandardError
        self.maxBytes = maxBytes
        self.session = session
    }

    var isEnabled: Bool { fileURL != nil }

    func record(_ event: String, _ fields: [String: DiagnosticValue] = [:]) {
        guard let fileURL else { return }
        var object: [String: Any] = [
            "t": Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted)),
            "session": session,
            "event": event,
        ]
        for (key, value) in fields {
            object[key] = value.jsonValue
        }
        guard var line = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else { return }
        line.append(0x0A)

        handle.withLock { handle in
            if handle == nil {
                handle = Self.openForAppending(fileURL, maxBytes: maxBytes)
            }
            try? handle?.write(contentsOf: line)
        }
        if mirrorToStandardError {
            FileHandle.standardError.write(Data(Self.consolePrefix.utf8) + line)
        }
    }

    private static func openForAppending(_ url: URL, maxBytes: Int) -> FileHandle? {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maxBytes {
            let rotated = url.deletingPathExtension().appendingPathExtension("1.jsonl")
            try? fileManager.removeItem(at: rotated)
            try? fileManager.moveItem(at: url, to: rotated)
        }
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        let handle = try? FileHandle(forWritingTo: url)
        _ = try? handle?.seekToEnd()
        return handle
    }

    private static func makeShared() -> DiagnosticsLog {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return .disabled
        }
        return DiagnosticsLog(fileURL: defaultFileURL, mirrorToStandardError: true)
        #else
        return .disabled
        #endif
    }
}
