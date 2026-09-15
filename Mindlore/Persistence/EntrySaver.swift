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
    @ObservationIgnored private(set) var scheduledSave: Task<Void, Never>?

    init(
        context: ModelContext,
        interval: Duration = .seconds(1),
        now: @escaping () -> Date = Date.init,
        save: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.context = context
        self.interval = interval
        self.now = now
        self.save = save
        context.autosaveEnabled = false
    }

    func noteChange() {
        guard scheduledSave == nil else { return }
        scheduledSave = Task { [weak self, interval] in
            do { try await Task.sleep(for: interval) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.scheduledSave = nil
            self.saveNow()
        }
    }

    func flush() {
        scheduledSave?.cancel()
        scheduledSave = nil
        saveNow()
    }

    private func saveNow() {
        guard context.hasChanges else { return }
        context.stampChangedEntries(at: now())
        do {
            try save(context)
            lastError = nil
        } catch {
            lastError = error
        }
    }
}
