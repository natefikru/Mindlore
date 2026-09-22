import Foundation
import SwiftData

nonisolated enum LooseEndStatus: String, CaseIterable, Sendable {
    case open, resolved, faded, dismissed
}

// Something an entry left unsettled that a later entry may settle: waiting on someone, a
// decision not yet made, an event coming up. Created by insights, closed by a later entry's
// insights or by the user, and faded when nobody mentions it for long enough. Every date is a
// journal date (the entry's entryDate), never the clock, so a backdated page behaves like the
// day it describes. Follows the same CloudKit schema rules as Entry.
@Model
final class LooseEnd {
    var id: UUID = UUID()
    var text: String = ""
    var createdAt: Date = Date.distantPast
    var sourceEntryID: UUID?
    var sourceEntryDate: Date = Date.distantPast
    // As resolved when written. Readers walk mergedIntoID, so a merge never rewrites these.
    var entityIDs: [UUID] = []
    var dueDate: Date?
    var statusRaw: String = LooseEndStatus.open.rawValue
    var resolvedByEntryID: UUID?
    var statusChangedAt: Date?
    var lastMentionedAt: Date = Date.distantPast
    var promptedAt: Date?
    // Marked done or let go by hand. Regenerating or deleting an entry never overrides that.
    var userTouched: Bool = false

    init(text: String, sourceEntryID: UUID, sourceEntryDate: Date, entityIDs: [UUID] = [], dueDate: Date? = nil) {
        self.text = text
        self.sourceEntryID = sourceEntryID
        self.sourceEntryDate = sourceEntryDate
        self.createdAt = sourceEntryDate
        self.lastMentionedAt = sourceEntryDate
        self.entityIDs = entityIDs
        self.dueDate = dueDate
    }

    var status: LooseEndStatus {
        get { LooseEndStatus(rawValue: statusRaw) ?? .open }
        set { statusRaw = newValue.rawValue }
    }

    var isOpen: Bool { status == .open }

    func setStatus(_ status: LooseEndStatus, at date: Date, resolvedBy entryID: UUID? = nil) {
        self.status = status
        statusChangedAt = date
        resolvedByEntryID = status == .resolved ? entryID : nil
    }

    // The user's own call: done or let go. Reopening hands it back to the journal, so a later
    // entry can settle it again, and counts as a fresh mention so it doesn't fade on the spot.
    func setByUser(_ status: LooseEndStatus, at date: Date = .now) {
        setStatus(status, at: date)
        userTouched = status != .open
        if status == .open {
            lastMentionedAt = max(lastMentionedAt, date)
        }
    }
}

// When an open loose end fades if nothing touches it first. One rule, read by the sweep that
// fades it and by the card that says when it will, so the two can never disagree. A dated one
// waits for its day however quiet it is, then gets a week; an undated one fades six weeks after
// it was last written about, which is why writing about it moves the date.
nonisolated enum LooseEndFading {
    static let afterSilence: TimeInterval = 42 * 86_400
    static let afterDue: TimeInterval = 7 * 86_400

    static func date(dueDate: Date?, lastMentionedAt: Date) -> Date {
        dueDate.map { $0.addingTimeInterval(afterDue) } ?? lastMentionedAt.addingTimeInterval(afterSilence)
    }
}

extension LooseEnd {
    static let fadesAfterSilence = LooseEndFading.afterSilence
    static let fadesAfterDue = LooseEndFading.afterDue

    static func all(in context: ModelContext) -> [LooseEnd] {
        ((try? context.fetch(FetchDescriptor<LooseEnd>())) ?? []).filter { !$0.isDeleted }
    }

    static func fetch(_ id: UUID, in context: ModelContext) -> LooseEnd? {
        let descriptor = FetchDescriptor<LooseEnd>(predicate: #Predicate { $0.id == id })
        return ((try? context.fetch(descriptor)) ?? []).first { !$0.isDeleted }
    }

    enum Rollback {
        // The entry is gone: everything it created goes, touched or not, since nothing could
        // show it any more.
        case entryDeleted
        // The insights are gone but the entry stays: only what is still open and untouched
        // goes. Settled and faded ones stay as history, and a rerun reuses them.
        case insightsRemoved
        // A new run is about to be applied. What it still means (`keeping`) stays, as does
        // anything another entry settled; the rest of what the entry created goes.
        case regenerating(keeping: Set<UUID>)
    }

    // Undoes what one entry's insights did to loose ends. Everything the entry settled opens
    // again, unless the user decided it.
    static func rollback(forEntryID entryID: UUID, _ mode: Rollback, in context: ModelContext) {
        for looseEnd in all(in: context) {
            if looseEnd.resolvedByEntryID == entryID, !looseEnd.userTouched {
                looseEnd.setStatus(.open, at: looseEnd.statusChangedAt ?? looseEnd.lastMentionedAt)
            }
            guard looseEnd.sourceEntryID == entryID else { continue }
            let deletes = switch mode {
            case .entryDeleted:
                true
            case .insightsRemoved:
                looseEnd.isOpen && !looseEnd.userTouched
            case .regenerating(let keeping):
                !looseEnd.userTouched && !keeping.contains(looseEnd.id)
                    && !(looseEnd.status == .resolved && looseEnd.resolvedByEntryID != entryID)
            }
            if deletes { context.delete(looseEnd) }
        }
    }

    // A journal date moved, so what the entry created moves with it.
    static func redate(forEntry entry: Entry, in context: ModelContext) {
        let entryID = entry.id
        for looseEnd in all(in: context) where looseEnd.sourceEntryID == entryID {
            if looseEnd.lastMentionedAt == looseEnd.sourceEntryDate {
                looseEnd.lastMentionedAt = entry.entryDate
            }
            looseEnd.sourceEntryDate = entry.entryDate
            looseEnd.createdAt = entry.entryDate
        }
    }

    static func hasAny(from entryID: UUID, in context: ModelContext) -> Bool {
        let id: UUID? = entryID
        let count = (try? context.fetchCount(FetchDescriptor<LooseEnd>(predicate: #Predicate { $0.sourceEntryID == id || $0.resolvedByEntryID == id }))) ?? 0
        return count > 0
    }

    // Open loose ends nobody has mentioned for six weeks, or a week past their date, fade.
    // Fading is a normal ending, not a failure, and nothing is deleted.
    @discardableResult
    static func fade(in context: ModelContext, now: Date = .now, diagnostics: DiagnosticsLog = .shared) -> Int {
        var faded = 0
        for looseEnd in all(in: context) where looseEnd.isOpen && shouldFade(looseEnd, now: now) {
            looseEnd.setStatus(.faded, at: now)
            faded += 1
        }
        if faded > 0 {
            diagnostics.record("looseEnds.faded", ["count": .int(faded)])
        }
        return faded
    }

    static func shouldFade(_ looseEnd: LooseEnd, now: Date) -> Bool {
        now > LooseEndFading.date(dueDate: looseEnd.dueDate, lastMentionedAt: looseEnd.lastMentionedAt)
    }
}

// Picks the one loose end the recorder asks about, if any.
enum LooseEndPrompter {
    static let quietPeriod: TimeInterval = 3 * 86_400

    static func next(in context: ModelContext, now: Date = .now) -> LooseEnd? {
        let open = LooseEnd.all(in: context).filter(\.isOpen)
        // A date that has passed and was never asked about comes first, earliest date first.
        if let due = open
            .filter({ $0.promptedAt == nil && ($0.dueDate.map { $0 <= now } ?? false) })
            .min(by: { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }) {
            return due
        }
        return open
            .filter { $0.promptedAt.map { now.timeIntervalSince($0) > quietPeriod } ?? true }
            .filter { $0.dueDate.map { $0 <= now } ?? true }
            .max { $0.lastMentionedAt < $1.lastMentionedAt }
    }

    static func markPrompted(_ looseEnd: LooseEnd, now: Date = .now) {
        looseEnd.promptedAt = now
    }
}
