import Foundation
import SwiftData

// Every save that stamps entries bumps this. Anything holding a derived copy of the journal reads
// it to tell whether that copy is stale, and putting it here means a new save path is covered by
// construction rather than by whoever adds it remembering to say so. Ask's index went blind to a
// recording's transcribed text exactly because three coordinators save straight through here,
// touching neither EntrySaver nor GraphServices.
//
// Monotonic, never a date: a clock that steps back must not be able to hide a change, which is why
// Entry.graphIndexedAt is an exact-equality stamp too.
enum JournalSaves {
    private(set) static var revision = 0

    static func recordSave() {
        revision += 1
    }
}

extension ModelContext {
    // A save writes every pending change in the context, including edits made elsewhere,
    // so every save path must stamp them or updatedAt falls behind the real last edit.
    // Entries in `unstamped` are skipped: writing AI insights marks the entry changed through
    // the relationship, but it isn't an edit to the entry itself.
    func stampChangedEntries(at date: Date, except unstamped: Set<PersistentIdentifier> = []) {
        for case let entry as Entry in changedModelsArray where !unstamped.contains(entry.persistentModelID) {
            entry.updatedAt = date
        }
    }

    func saveStampingEntries(at date: Date = .now, except unstamped: Set<PersistentIdentifier> = []) throws {
        stampChangedEntries(at: date, except: unstamped)
        // Read before the save, which clears them.
        let touchedJournal = touchesJournal
        let backups = EntryBackups.pending(in: self)
        let made = LocalOrigin.inserted(in: self)
        try save()
        EntryBackups.of(self)?.apply(backups)
        LocalOrigin.claimInserted(made, in: self)
        if touchedJournal { JournalSaves.recordSave() }
    }

    // Whether this save changes anything a derived copy of the journal would have to be rebuilt for.
    //
    // Asking a question saves the conversation through here, which bumped the counter, which made
    // Ask's own index stale: on the phone every question was followed by a 565ms rebuild that
    // produced a byte-identical index, three hundred documents and nine thousand postings, while the
    // next question was being typed.
    //
    // Inverted on purpose. It is not a list of what counts; it is a list of what doesn't, so a model
    // type added later counts as journal content until someone says otherwise. A derived copy can
    // then only ever be rebuilt more often than it needs to be, never left stale, which is the
    // failure this counter exists to prevent.
    private var touchesJournal: Bool {
        let pending = insertedModelsArray + changedModelsArray + deletedModelsArray
        return pending.contains { !($0 is AskConversation || $0 is AskMessage) }
    }
}
