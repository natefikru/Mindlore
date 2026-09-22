#if DEBUG
import Foundation
import SwiftData

// Teo's year (`-seedStoryJournal`): 200 hand-written entries from 23 September 2025 to 22 September 2026, with a cast
// that recurs, a plot (meeting Maya, losing the job, therapy, the affair, the breakup, the new job,
// the half marathon), and loose ends that open in one entry and close in a later one. The story
// bible, with every name and date, is docs/demo-story.md.
//
// The entries live as JSON inside the `chapterN` strings (DemoStory+Chapter*.swift), which keeps
// 200 of them out of the type checker. Each carries the insights the app would have written for it,
// so seeding needs no AI. Dates move forward by whole days to end on the day it's seeded, so the
// last entry is always recent and the seasons stay near where they were written.
enum DemoStory {
    struct StoryEntry: Decodable, Equatable {
        struct StoryMention: Decodable, Equatable {
            let name: String
            let kind: MentionKind
        }

        struct Opened: Decodable, Equatable {
            let id: String
            let text: String
            var about: [String] = []
            var due: String?

            private enum CodingKeys: String, CodingKey { case id, text, about, due }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                id = try container.decode(String.self, forKey: .id)
                text = try container.decode(String.self, forKey: .text)
                about = try container.decodeIfPresent([String].self, forKey: .about) ?? []
                due = try container.decodeIfPresent(String.self, forKey: .due)
            }
        }

        let date: String
        let title: String
        let text: String
        let summary: String
        let mood: Mood
        let secondaryMood: Mood?
        let areas: [LifeArea]
        let tags: [String]
        let mentions: [StoryMention]
        let opens: [Opened]
        let resolves: [String]
        let touches: [String]

        private enum CodingKeys: String, CodingKey {
            case date, title, text, summary, mood, secondaryMood, areas, tags, mentions, opens, resolves, touches
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            date = try container.decode(String.self, forKey: .date)
            title = try container.decode(String.self, forKey: .title)
            text = try container.decode(String.self, forKey: .text)
            summary = try container.decode(String.self, forKey: .summary)
            mood = try container.decode(Mood.self, forKey: .mood)
            secondaryMood = try container.decodeIfPresent(Mood.self, forKey: .secondaryMood)
            areas = try container.decode([LifeArea].self, forKey: .areas)
            tags = try container.decode([String].self, forKey: .tags)
            mentions = try container.decode([StoryMention].self, forKey: .mentions)
            opens = try container.decodeIfPresent([Opened].self, forKey: .opens) ?? []
            resolves = try container.decodeIfPresent([String].self, forKey: .resolves) ?? []
            touches = try container.decodeIfPresent([String].self, forKey: .touches) ?? []
        }
    }

    static let chapters = [chapter1, chapter2, chapter3, chapter4, chapter5]

    // The day the story was written to end on.
    static let anchorDay = DateComponents(year: 2026, month: 9, day: 22)

    static func entries() throws -> [StoryEntry] {
        try chapters.flatMap { try JSONDecoder().decode([StoryEntry].self, from: Data($0.utf8)) }
    }

    // Written wall-clock dates, moved forward by whole days so the last one lands on `now`'s day,
    // or the day before if its time of day hasn't come yet.
    static func dates(for entries: [StoryEntry], now: Date, calendar: Calendar = .current) -> [Date] {
        let written = entries.map { Self.written(from: $0.date, calendar: calendar) ?? now }
        guard let anchor = calendar.date(from: anchorDay) else { return written }
        var days = calendar.dateComponents([.day], from: calendar.startOfDay(for: anchor), to: calendar.startOfDay(for: now)).day ?? 0
        func shifted(_ date: Date) -> Date { calendar.date(byAdding: .day, value: days, to: date) ?? date }
        while let last = written.last, shifted(last) > now { days -= 1 }
        return written.map(shifted)
    }

    static func written(from string: String, calendar: Calendar = .current) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = string.count == 10 ? "yyyy-MM-dd" : "yyyy-MM-dd'T'HH:mm"
        return formatter.date(from: string)
    }

    @discardableResult
    static func seedIfEmpty(in context: ModelContext, now: Date = .now, calendar: Calendar = .current) throws -> Int {
        guard try context.fetchCount(FetchDescriptor<Entry>()) == 0 else { return 0 }
        let started = Date.now
        let story = try entries()
        let dates = Self.dates(for: story, now: now, calendar: calendar)
        let shift = dates.last.flatMap { last in story.last.flatMap { written(from: $0.date, calendar: calendar) }.map { last.timeIntervalSince($0) } } ?? 0

        let inserted = zip(story, dates).map { entry, date in
            DemoJournal.insert(DemoJournal.Draft(
                date: date,
                title: entry.title,
                text: entry.text,
                summary: entry.summary,
                primaryMood: entry.mood,
                secondaryMood: entry.secondaryMood,
                areas: entry.areas,
                tags: entry.tags,
                mentions: entry.mentions.map { Mention(name: $0.name, kindRaw: $0.kind.rawValue) }
            ), in: context)
        }
        try context.save()
        GraphIndexer().sweep(in: context)

        // In date order and dated as each entry, as if written that day, so a resolve always finds
        // the loose end an earlier entry opened still open. Then the launch sweep's fade, once, for
        // whatever has gone quiet since.
        var looseEnds: [String: UUID] = [:]
        for (entry, record) in zip(story, inserted) {
            var result = LooseEndResult()
            result.new = entry.opens.map { opened in
                .init(text: opened.text, about: opened.about, due: opened.due.flatMap { written(from: $0, calendar: calendar) }?.addingTimeInterval(shift))
            }
            result.resolved = entry.resolves.compactMap { looseEnds[$0] }
            result.mentioned = entry.touches.compactMap { looseEnds[$0] }
            guard !result.isEmpty else { continue }
            LooseEndWriter.apply(result, to: record, in: context, now: record.createdAt)
            let recordID = record.id
            let created = LooseEnd.all(in: context).filter { $0.sourceEntryID == recordID }
            for opened in entry.opens {
                looseEnds[opened.id] = created.first { $0.text == opened.text }?.id
            }
        }
        LooseEnd.fade(in: context, now: now)
        try context.save()
        DiagnosticsLog.shared.record("demo.seeded", [
            "entries": .int(inserted.count),
            "milliseconds": .int(Int(Date.now.timeIntervalSince(started) * 1000)),
        ])
        return inserted.count
    }
}
#endif
