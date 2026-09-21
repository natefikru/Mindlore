import Foundation
import SwiftData

// The half of Ask's suggestions that touches the store. It applies Today's rules about what may be
// named on screen: no hidden or muted names, and no thread about anyone hidden or muted. None of
// this leaves the phone, so AskSources' rules about what may be sent don't come into it; the
// promise kept here is only that a name the user put away never shows up.
@MainActor
enum AskSuggestionSource {
    // How far back "lately" reaches for the area question.
    static let areaWindow: TimeInterval = 30 * 86_400
    // One entry filed under an area isn't a lean.
    static let areaMinimumEntries = 2

    static func suggestions(
        in context: ModelContext,
        settings: SettingsStore,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [AskSuggestion] {
        let directory = EntityDirectory(in: context)
        return AskSuggestions.suggestions(AskSuggestions.Input(
            names: names(in: context),
            threads: threads(in: context, directory: directory),
            area: area(in: context, settings: settings, now: now),
            now: now,
            calendar: calendar
        ))
    }

    private static func names(in context: ModelContext) -> [AskSuggestions.Name] {
        ((try? context.fetch(FetchDescriptor<Entity>())) ?? [])
            .filter { !$0.isDeleted && $0.isBrowsable && !$0.resurfacingMuted && $0.kind.isAName && $0.lastLinkedAt != nil }
            .sorted { ($0.lastLinkedAt ?? .distantPast, $0.name) > ($1.lastLinkedAt ?? .distantPast, $1.name) }
            .prefix(2)
            .map { AskSuggestions.Name(name: $0.name, kind: $0.kind) }
    }

    // Open threads only, oldest first. A thread names everyone it is about in one sentence, so a
    // single hidden or muted subject drops the whole thing, as it does on Today.
    private static func threads(in context: ModelContext, directory: EntityDirectory) -> [String] {
        LooseEnd.all(in: context)
            .filter { end in
                guard end.isOpen else { return false }
                return !end.entityIDs.map(directory.root(of:)).contains { id in
                    guard let entity = directory.entity(id) else { return false }
                    return entity.hidden || entity.resurfacingMuted
                }
            }
            .sorted { ($0.sourceEntryDate, $0.id.uuidString) < ($1.sourceEntryDate, $1.id.uuidString) }
            .map(\.text)
    }

    // The visible area most of the last month's entries were filed under. A bounded fetch by date,
    // never the whole journal. Ties go to the area listed first, so the answer is stable.
    private static func area(in context: ModelContext, settings: SettingsStore, now: Date) -> AskSuggestions.Area? {
        let start = now.addingTimeInterval(-areaWindow)
        let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.entryDate >= start && $0.entryDate <= now })
        let entries = ((try? context.fetch(descriptor)) ?? []).filter { !$0.isDeleted }

        var counts: [LifeArea: Int] = [:]
        for area in entries.flatMap({ $0.insights?.areas ?? [] }) where !settings.isHidden(area) {
            counts[area, default: 0] += 1
        }
        let best = LifeArea.allCases
            .filter { (counts[$0] ?? 0) >= areaMinimumEntries }
            .max { (counts[$0] ?? 0) < (counts[$1] ?? 0) }
        return best.map { AskSuggestions.Area(area: $0, name: settings.name(of: $0)) }
    }
}
