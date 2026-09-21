import Foundation
import SwiftData

// The totals Settings shows under About. Counts only, per phase B's rule for any number on screen:
// no averages, no streaks, nothing that could read as a grade, and nothing that can fall because of
// something the user didn't do.
//
// That last clause is why "hours spoken" was planned and left out. `Entry.removeAudio()` clears
// `audioDuration` along with the audio when Keep recordings is off, so a total built on it would
// quietly shrink every time an entry closed. Counting it honestly would mean keeping the duration
// after the audio goes, which is a model change this sprint has no business making.
struct JournalTotals: Equatable {
    var entries = 0
    var names = 0

    static func count(in context: ModelContext) -> JournalTotals {
        // Drafts are unfinished typing, not entries yet: the rest of the app treats them the same way.
        let entries = FetchDescriptor<Entry>(predicate: #Predicate { !$0.isDraft })
        // People, places and the rest, as Mind would show them: a merged loser is the winner's alias,
        // a hidden one was asked to go away, and a tag is a label rather than a name.
        let tag = EntityKind.tag.rawValue
        let names = FetchDescriptor<Entity>(predicate: #Predicate {
            !$0.hidden && $0.mergedIntoID == nil && $0.kindRaw != tag
        })
        return JournalTotals(
            entries: (try? context.fetchCount(entries)) ?? 0,
            names: (try? context.fetchCount(names)) ?? 0
        )
    }
}
