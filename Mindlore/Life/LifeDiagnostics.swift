import Foundation

// Life's diagnostics: counts, windows, and durations only, never an area's custom name, a tag, or
// a sentence.
@MainActor
enum LifeDiagnostics {
    static func rendered(reading: LifeSignals.Reading?, progress: LifeSignals.Progress, started: Date, diagnostics: DiagnosticsLog = .shared) {
        var fields: [String: DiagnosticValue] = [
            "entries": .int(progress.entries),
            "days": .int(progress.days),
            "ready": .bool(reading != nil),
            "milliseconds": .int(Int(Date.now.timeIntervalSince(started) * 1000)),
        ]
        if let reading {
            fields["window"] = .string(reading.window.rawValue)
            fields["windowEntries"] = .int(reading.entries)
            fields["areas"] = .int(reading.areas.count)
            fields["recurring"] = .int(reading.recurring.count)
            fields["quiet"] = .int(reading.quiet.count)
            fields["changes"] = .int(reading.changes.count)
            fields["followThrough"] = .int(reading.followThrough.count)
        }
        diagnostics.record("life.rendered", fields)
    }

    static func areaOpened(_ area: LifeArea, window: MindWindow, diagnostics: DiagnosticsLog = .shared) {
        diagnostics.record("life.areaOpened", ["area": .string(area.rawValue), "window": .string(window.rawValue)])
    }
}
