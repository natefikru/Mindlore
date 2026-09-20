import Foundation
import SwiftData

// The half of Today that touches the store. It fetches, walks merges, drops what the user hid or
// muted, and hands plain facts to TodayComposer. Nothing is held across an await: every refresh
// re-derives from a fresh fetch, the way KeepCard does.
@MainActor
enum TodaySource {
    static func today(
        in context: ModelContext,
        settings: SettingsStore,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Today {
        let directory = EntityDirectory(in: context)
        return TodayComposer.compose(TodayInput(
            entries: entries(in: context, now: now, calendar: calendar),
            looseEnds: looseEnds(in: context, directory: directory),
            entities: entities(in: context, directory: directory),
            now: now,
            calendar: calendar,
            dismissed: settings.dismissedTodayCards(on: TodayDismissal.stamp(now, calendar: calendar)),
            resurfacingEnabled: settings.resurfacingEnabled,
            name: settings.userName
        ))
    }

    // MARK: - Entries

    // Three small fetches rather than the whole journal: the newest entry, this week, and one day
    // per anniversary the journal could have. Every one of them filters entryDate <= now itself.
    // Without that the newest row could be an entry dated next year, and it would arrive at the
    // composer already labelled "the latest" for the composer's own future filter to miss.
    private static func entries(in context: ModelContext, now: Date, calendar: Calendar) -> [EntryFacts] {
        var found: [UUID: EntryFacts] = [:]

        for entry in newest(in: context, now: now) {
            found[entry.id] = facts(entry)
        }
        let weekStart = calendar.date(byAdding: .day, value: -(TodayComposer.weekLength - 1), to: calendar.startOfDay(for: now))
        if let weekStart {
            for entry in between(weekStart, and: now, in: context) {
                found[entry.id] = facts(entry)
            }
        }
        for day in anniversaryDays(in: context, now: now, calendar: calendar) {
            guard let end = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
            for entry in between(day, and: min(end, now), in: context) {
                found[entry.id] = facts(entry)
            }
        }
        return Array(found.values)
    }

    private static func newest(in context: ModelContext, now: Date) -> [Entry] {
        var descriptor = FetchDescriptor<Entry>(
            predicate: #Predicate { $0.entryDate <= now },
            sortBy: [SortDescriptor(\Entry.entryDate, order: .reverse), SortDescriptor(\Entry.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func between(_ start: Date, and end: Date, in context: ModelContext) -> [Entry] {
        guard start <= end else { return [] }
        let descriptor = FetchDescriptor<Entry>(
            predicate: #Predicate { $0.entryDate >= start && $0.entryDate <= end },
            sortBy: [SortDescriptor(\Entry.entryDate, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // The days an anniversary could fall on: this day in every year the journal covers, a month
    // ago, and six months ago. A leap-day entry is caught by also asking for the 29th when today
    // is the 28th of February.
    private static func anniversaryDays(in context: ModelContext, now: Date, calendar: Calendar) -> [Date] {
        var days: [Date] = []
        if let monthAgo = calendar.date(byAdding: .month, value: -1, to: now) {
            days.append(calendar.startOfDay(for: monthAgo))
        }
        if let halfYearAgo = calendar.date(byAdding: .month, value: -6, to: now) {
            days.append(calendar.startOfDay(for: halfYearAgo))
        }

        guard let earliest = earliest(in: context) else { return days }
        let firstYear = calendar.component(.year, from: earliest)
        let thisYear = calendar.component(.year, from: now)
        guard firstYear < thisYear else { return days }

        let today = calendar.dateComponents([.month, .day], from: now)
        let leapDayInstead = today.month == 2 && today.day == 28
        for year in firstYear..<thisYear {
            var parts = DateComponents(year: year, month: today.month, day: today.day)
            if let day = calendar.date(from: parts) {
                days.append(calendar.startOfDay(for: day))
            }
            if leapDayInstead {
                parts.day = 29
                if let leapDay = calendar.date(from: parts),
                   calendar.component(.month, from: leapDay) == 2 {
                    days.append(calendar.startOfDay(for: leapDay))
                }
            }
        }
        return days
    }

    private static func earliest(in context: ModelContext) -> Date? {
        var descriptor = FetchDescriptor<Entry>(sortBy: [SortDescriptor(\Entry.entryDate, order: .forward)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.entryDate
    }

    private static func facts(_ entry: Entry) -> EntryFacts {
        EntryFacts(
            id: entry.id,
            entryDate: entry.entryDate,
            entryDateIsDayOnly: entry.entryDateIsDayOnly,
            title: entry.displayTitle,
            summary: entry.insights?.summary,
            areas: entry.insights?.areas ?? []
        )
    }

    // MARK: - Loose ends and entities

    // The first place a loose end's entities are resolved and filtered together: the insights
    // sheet shows them raw. A loose end names everyone it is about in one sentence, so a single
    // hidden or muted subject suppresses the whole card. Privacy over completeness.
    private static func looseEnds(in context: ModelContext, directory: EntityDirectory) -> [LooseEndFacts] {
        LooseEnd.all(in: context).compactMap { end in
            let subjects = Set(end.entityIDs.map(directory.root(of:)))
            let concealed = subjects.contains { id in
                guard let entity = directory.entity(id) else { return false }
                return entity.hidden || entity.resurfacingMuted
            }
            guard !concealed else { return nil }
            return LooseEndFacts(
                id: end.id,
                text: end.text,
                status: end.status,
                sourceEntryDate: end.sourceEntryDate,
                dueDate: end.dueDate,
                resolvedByEntryID: end.resolvedByEntryID
            )
        }
    }

    private static func entities(in context: ModelContext, directory: EntityDirectory) -> [EntityFacts] {
        let all = (try? context.fetch(FetchDescriptor<Entity>())) ?? []
        return all.compactMap { entity in
            guard !entity.isDeleted, entity.isBrowsable, !entity.resurfacingMuted, entity.kind.isAName else { return nil }
            return EntityFacts(
                id: entity.id,
                name: entity.name,
                kind: entity.kind,
                linkCount: entity.linkCount,
                lastLinkedAt: entity.lastLinkedAt
            )
        }
    }
}
