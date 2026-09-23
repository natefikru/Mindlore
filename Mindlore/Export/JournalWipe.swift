import Foundation
import SwiftData

// Settings' "Delete all data": every entry and everything made from them (insights, names, links,
// loose ends, Reflect summaries, Ask conversations) and the recordings waiting on disk. Settings and
// the API key stay, since they describe the phone rather than the journal. One model type at a time
// and one object at a time, rather than a batch delete, so SwiftData applies each relationship's
// rule instead of tripping over one.
@MainActor
enum JournalWipe {
    @discardableResult
    static func deleteEverything(in context: ModelContext, recordings: RecordingsDirectory = .standard, diagnostics: DiagnosticsLog = .shared) throws -> Int {
        let entries = (try? context.fetchCount(FetchDescriptor<Entry>())) ?? 0
        try deleteAll(AskMessage.self, in: context)
        try deleteAll(AskConversation.self, in: context)
        try deleteAll(ReflectSummary.self, in: context)
        try deleteAll(LooseEnd.self, in: context)
        try deleteAll(EntityLink.self, in: context)
        try deleteAll(Entity.self, in: context)
        try deleteAll(EntryInsights.self, in: context)
        try deleteAll(EntryPage.self, in: context)
        try deleteAll(Entry.self, in: context)
        try context.saveStampingEntries()
        // Deleting everything means the safety copy too, or a later restore would bring it back.
        EntryBackups.of(context)?.removeAll()

        // Finished recordings not yet made into entries. A recording still running is left alone:
        // the button is disabled while one is.
        for file in (try? recordings.finishedFiles()) ?? [] {
            try? FileManager.default.removeItem(at: file)
        }
        diagnostics.record("journal.wiped", ["entries": .int(entries)])
        return entries
    }

    private static func deleteAll<Model: PersistentModel>(_ type: Model.Type, in context: ModelContext) throws {
        for model in try context.fetch(FetchDescriptor<Model>()) {
            context.delete(model)
        }
    }
}
