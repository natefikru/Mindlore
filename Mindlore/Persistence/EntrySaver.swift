import Foundation
import Observation
import SwiftData

// The only place that decides when the main context writes to disk. Changes are saved
// at most `interval` after they happen, including during continuous typing (a trailing
// throttle, not a debounce, which would never fire while the user keeps typing).
@Observable
final class EntrySaver {
    private(set) var lastError: (any Error)?

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let interval: Duration
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let save: (ModelContext) throws -> Void
    @ObservationIgnored private let diagnostics: DiagnosticsLog
    @ObservationIgnored private(set) var scheduledSave: Task<Void, Never>?

    init(
        context: ModelContext,
        interval: Duration = .seconds(1),
        now: @escaping () -> Date = Date.init,
        save: @escaping (ModelContext) throws -> Void = { try $0.save() },
        diagnostics: DiagnosticsLog = .shared
    ) {
        self.context = context
        self.interval = interval
        self.now = now
        self.save = save
        self.diagnostics = diagnostics
        context.autosaveEnabled = false
    }

    func noteChange() {
        guard scheduledSave == nil else { return }
        scheduledSave = Task { [weak self, interval] in
            do { try await Task.sleep(for: interval) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.scheduledSave = nil
            self.saveNow(trigger: "throttle")
        }
    }

    func flush() {
        scheduledSave?.cancel()
        scheduledSave = nil
        saveNow(trigger: "flush")
    }

    private func saveNow(trigger: String = "throttle") {
        guard context.hasChanges else { return }
        context.stampChangedEntries(at: now())
        let counts: [String: DiagnosticValue] = [
            "trigger": .string(trigger),
            "inserted": .int(context.insertedModelsArray.count),
            "changed": .int(context.changedModelsArray.count),
            "deleted": .int(context.deletedModelsArray.count),
        ]
        do {
            try save(context)
            lastError = nil
            diagnostics.record("save.completed", counts)
        } catch {
            lastError = error
            diagnostics.record("save.failed", counts.merging(["error": .errorCode(error)]) { $1 })
        }
    }
}
