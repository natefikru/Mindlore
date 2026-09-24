import Foundation
import SwiftData

// The totals Settings shows under About. Counts only, per phase B's rule for any number on screen:
// no averages, no streaks, nothing that could read as a grade, and nothing that can fall because of
// something the user didn't do. Whole-journal totals only: anything about a week or a month is
// Reflect's.
//
// That last clause is why "hours spoken" was planned and left out. `Entry.removeAudio()` clears
// `audioDuration` along with the audio when Keep recordings is off, so a total built on it would
// quietly shrink every time an entry closed. Counting it honestly would mean keeping the duration
// after the audio goes, which is a model change this sprint has no business making.
struct JournalTotals: Equatable {
    var entries = 0
    var names = 0
    // Distinct days by `entryDate`, the day an entry belongs to, not the day it reached the app.
    var days = 0
    var firstDay: Date?
    var words = 0
    var bySource: [EntrySource: Int] = [:]
    var pages = 0
    var byKind: [EntryKind: Int] = [:]
    // Names by kind, under the same rules as `names`.
    var namesByKind: [EntityKind: Int] = [:]
    var threadsClosed = 0
    var conversations = 0

    // What the Settings root shows beside About, re-read on every save while Settings is open, so a
    // count rather than the full pass below, which only About itself runs.
    static func entryCount(in context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<Entry>(predicate: #Predicate { !$0.isDraft }))) ?? 0
    }

    // Every save changes one of these, so a screen showing totals keys its refresh off them. Never a
    // count, which an add and a delete can return to where it was; `JournalSaves.revision` rides
    // along for the coordinators that save straight through `saveStampingEntries`.
    struct Fingerprint: Equatable {
        let saver: Int
        let graph: Int
        let stamped: Int
    }

    static func count(in context: ModelContext, calendar: Calendar = .current) -> JournalTotals {
        var totals = JournalTotals()

        // Drafts are unfinished typing, not entries yet: the rest of the app treats them the same way.
        let entries = (try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { !$0.isDraft }))) ?? []
        var days = Set<Date>()
        for entry in entries {
            totals.entries += 1
            days.insert(calendar.startOfDay(for: entry.entryDate))
            totals.firstDay = min(totals.firstDay ?? entry.entryDate, entry.entryDate)
            totals.words += wordCount(entry.text)
            totals.bySource[entry.source, default: 0] += 1
            totals.byKind[entry.kind, default: 0] += 1
        }
        totals.days = days.count
        // Counted, not walked: a page's thumbnail is stored inline, so faulting every page through
        // `entry.pages` would read every thumbnail to count them. A photo entry is never a draft.
        totals.pages = (try? context.fetchCount(FetchDescriptor<EntryPage>(predicate: #Predicate { $0.entry != nil }))) ?? 0

        // People, places and the rest, as Mind would show them: a merged loser is the winner's alias,
        // a hidden one was asked to go away, and a tag is a label rather than a name.
        let tag = EntityKind.tag.rawValue
        let names = (try? context.fetch(FetchDescriptor<Entity>(predicate: #Predicate {
            !$0.hidden && $0.mergedIntoID == nil && $0.kindRaw != tag
        }))) ?? []
        totals.names = names.count
        for entity in names {
            totals.namesByKind[entity.kind, default: 0] += 1
        }

        let resolved = LooseEndStatus.resolved.rawValue
        totals.threadsClosed = (try? context.fetchCount(FetchDescriptor<LooseEnd>(predicate: #Predicate { $0.statusRaw == resolved }))) ?? 0
        totals.conversations = (try? context.fetchCount(FetchDescriptor<AskConversation>())) ?? 0
        return totals
    }

    // A count, not linguistics: runs of anything that isn't whitespace.
    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }
}
