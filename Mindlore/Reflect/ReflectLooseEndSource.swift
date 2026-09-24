import Foundation
import SwiftData

// The half of Reflect's Loose ends tab that touches the store: it fetches every loose end, walks
// merges, drops what names a hidden entity, and applies the three actions the tab offers.
@MainActor
enum ReflectLooseEndSource {
    // Every loose end, whatever its status. One whose subjects include a hidden name is left out
    // whole, as Today leaves it out: its text is a sentence about that person, so dropping just the
    // name would still show them. A muted name stays: muting stops Today bringing a name back
    // unasked, and this list is only ever opened on purpose.
    static func items(in context: ModelContext) -> [ReflectLooseEnds.Item] {
        let directory = EntityDirectory(in: context)
        return LooseEnd.all(in: context).compactMap { end in
            var roots: [UUID] = []
            for id in end.entityIDs {
                let root = directory.root(of: id)
                if !roots.contains(root) { roots.append(root) }
            }
            let subjects = roots.compactMap { directory.entity($0) }
            guard !subjects.contains(where: { $0.hidden }) else { return nil }
            return ReflectLooseEnds.Item(
                id: end.id,
                text: end.text,
                status: end.status,
                raisedOn: end.sourceEntryDate,
                dueDate: end.dueDate,
                statusChangedAt: end.statusChangedAt,
                userTouched: end.userTouched,
                sourceEntryID: end.sourceEntryID,
                subjects: subjects.map(\.name).filter { !$0.isEmpty }
            )
        }
    }

    enum Action: String, Sendable {
        case done, letGo, reopen

        var status: LooseEndStatus {
            switch self {
            case .done: .resolved
            case .letGo: .dismissed
            case .reopen: .open
            }
        }
    }

    // Done and Let go are what Today's thread card does; Reopen is `setByUser(.open)`, the same
    // rule the insights sheet's and entity page's Reopen use. Saved through saveStampingEntries so
    // JournalSaves.revision moves and Today, Ask, and Reflect see it. False when the loose end is
    // gone or the action doesn't fit its status (Done on one already closed).
    @discardableResult
    static func apply(
        _ action: Action,
        to id: UUID,
        in context: ModelContext,
        now: Date = .now,
        diagnostics: DiagnosticsLog = .shared
    ) -> Bool {
        guard let looseEnd = LooseEnd.fetch(id, in: context) else { return false }
        let from = looseEnd.status
        guard (action == .reopen) != looseEnd.isOpen else { return false }
        looseEnd.setByUser(action.status, at: now)
        do {
            try context.saveStampingEntries(at: now)
        } catch {
            diagnostics.record("reflect.looseEnd", ["action": .string(action.rawValue), "from": .string(from.rawValue), "error": .errorCode(error)])
            return false
        }
        diagnostics.record("reflect.looseEnd", ["action": .string(action.rawValue), "from": .string(from.rawValue)])
        return true
    }

    // Whether the entry that raised it is still there to open.
    static func entryExists(_ id: UUID, in context: ModelContext) -> Bool {
        let count = (try? context.fetchCount(FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id }))) ?? 0
        return count > 0
    }
}
