import Foundation
import SwiftData

// The whole journal as files a person can keep: one Markdown file per entry, `journal.json` with
// everything the app knows about each one, and the recordings and page photos beside them. It is
// the only backup there is until sync exists, so it leaves nothing out, drafts and hidden names
// included, each marked as such.
//
//   Mindlore Export 2026-09-22/
//     journal.json
//     entries/2026-09-21 Coffee with Maya.md
//     media/<entry id>.m4a
//     media/<entry id>-page-1.jpg
@MainActor
enum JournalExport {
    struct Summary: Equatable {
        let folder: URL
        let entries: Int
        let mediaFiles: Int
    }

    nonisolated struct Document: Codable, Equatable {
        var exportedAt: Date
        var entries: [ExportedEntry]
        var names: [ExportedName]
        var looseEnds: [ExportedLooseEnd]
    }

    nonisolated struct ExportedEntry: Codable, Equatable {
        var id: UUID
        var date: Date
        var createdAt: Date
        var updatedAt: Date
        var source: String
        var title: String
        var text: String
        // EntryFormatting JSON, so the JSON export keeps the layout the Markdown file shows.
        var formatting: String?
        var isDraft: Bool
        var summary: String?
        var mood: String?
        var otherMoods: [String]
        var areas: [String]
        var tags: [String]
        var names: [String]
        var file: String
        var audio: String?
        var pages: [String]
    }

    nonisolated struct ExportedName: Codable, Equatable {
        var id: UUID
        var name: String
        var kind: String
        var aliases: [String]
        var bio: String?
        var hidden: Bool
        var mentions: Int
    }

    nonisolated struct ExportedLooseEnd: Codable, Equatable {
        var text: String
        var status: String
        var createdAt: Date
        var dueDate: Date?
        var fromEntry: UUID?
        var names: [String]
    }

    // Writes the folder inside `parent` and returns it. The caller moves it where the user picks.
    static func write(from context: ModelContext, into parent: URL, now: Date = .now, calendar: Calendar = .current, diagnostics: DiagnosticsLog = .shared) throws -> Summary {
        let fileManager = FileManager.default
        let folder = parent.appendingPathComponent("Mindlore Export \(day(now, calendar: calendar))", isDirectory: true)
        try? fileManager.removeItem(at: folder)
        let entriesFolder = folder.appendingPathComponent("entries", isDirectory: true)
        let mediaFolder = folder.appendingPathComponent("media", isDirectory: true)
        try fileManager.createDirectory(at: entriesFolder, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: mediaFolder, withIntermediateDirectories: true)

        let entities = (try? context.fetch(FetchDescriptor<Entity>())) ?? []
        let byID = Dictionary(entities.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // A merged name is exported under the name it was merged into, like every screen shows it.
        func root(_ id: UUID) -> Entity? {
            var current = byID[id]
            var seen: Set<UUID> = []
            while let next = current?.mergedIntoID, seen.insert(next).inserted, let found = byID[next] { current = found }
            return current
        }
        var namesByEntry: [UUID: [String]] = [:]
        for link in (try? context.fetch(FetchDescriptor<EntityLink>())) ?? [] {
            guard let entryID = link.entryID, let entityID = link.entityID, let entity = root(entityID) else { continue }
            if !(namesByEntry[entryID] ?? []).contains(entity.name) { namesByEntry[entryID, default: []].append(entity.name) }
        }

        let entries = (try? context.fetch(FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.entryDate), SortDescriptor(\.createdAt)]))) ?? []
        var usedNames: Set<String> = []
        var mediaFiles = 0
        var exported: [ExportedEntry] = []
        for entry in entries {
            let file = uniqueFileName(for: entry, calendar: calendar, used: &usedNames)
            var audio: String?
            if let data = entry.audioData {
                let name = "\(entry.id.uuidString).\(TranscriptionCoordinator.fileExtension(for: data))"
                try data.write(to: mediaFolder.appendingPathComponent(name))
                audio = "media/\(name)"
                mediaFiles += 1
            }
            var pages: [String] = []
            for (position, page) in entry.sortedPages.enumerated() {
                guard let data = page.imageData else { continue }
                let name = "\(entry.id.uuidString)-page-\(position + 1).jpg"
                try data.write(to: mediaFolder.appendingPathComponent(name))
                pages.append("media/\(name)")
                mediaFiles += 1
            }
            let insights = entry.insights
            let item = ExportedEntry(
                id: entry.id,
                date: entry.entryDate,
                createdAt: entry.createdAt,
                updatedAt: entry.updatedAt,
                source: entry.sourceRaw,
                title: entry.title,
                text: entry.text,
                formatting: entry.formattingRaw,
                isDraft: entry.isDraft,
                summary: insights?.summary,
                mood: insights?.primaryMoodRaw,
                otherMoods: insights?.secondaryMoodsRaw ?? [],
                areas: insights?.areasRaw ?? [],
                tags: insights?.tags ?? [],
                names: namesByEntry[entry.id] ?? [],
                file: "entries/\(file)",
                audio: audio,
                pages: pages
            )
            try markdown(for: item, calendar: calendar).write(to: entriesFolder.appendingPathComponent(file), atomically: true, encoding: .utf8)
            exported.append(item)
        }

        let names = entities
            .filter { !$0.isMerged }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { ExportedName(id: $0.id, name: $0.name, kind: $0.kindRaw, aliases: $0.aliases, bio: $0.bio, hidden: $0.hidden, mentions: $0.linkCount) }
        let looseEnds = ((try? context.fetch(FetchDescriptor<LooseEnd>(sortBy: [SortDescriptor(\.createdAt)]))) ?? [])
            .map { end in
                ExportedLooseEnd(
                    text: end.text,
                    status: end.statusRaw,
                    createdAt: end.createdAt,
                    dueDate: end.dueDate,
                    fromEntry: end.sourceEntryID,
                    names: end.entityIDs.compactMap { root($0)?.name }
                )
            }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let document = Document(exportedAt: now, entries: exported, names: names, looseEnds: looseEnds)
        try encoder.encode(document).write(to: folder.appendingPathComponent("journal.json"))

        diagnostics.record("journal.exported", ["entries": .int(exported.count), "media": .int(mediaFiles), "names": .int(names.count)])
        return Summary(folder: folder, entries: exported.count, mediaFiles: mediaFiles)
    }

    // Front matter a Markdown app or a script can read, then the entry in the user's own words.
    nonisolated static func markdown(for entry: ExportedEntry, calendar: Calendar = .current) -> String {
        var lines = ["---"]
        lines.append("date: \(ISO8601DateFormatter().string(from: entry.date))")
        if !entry.title.isEmpty { lines.append("title: \(yamlString(entry.title))") }
        lines.append("source: \(entry.source)")
        if entry.isDraft { lines.append("draft: true") }
        if let mood = entry.mood { lines.append("mood: \(mood)") }
        if !entry.areas.isEmpty { lines.append("areas: [\(entry.areas.joined(separator: ", "))]") }
        if !entry.tags.isEmpty { lines.append("tags: [\(entry.tags.map(yamlString).joined(separator: ", "))]") }
        if !entry.names.isEmpty { lines.append("names: [\(entry.names.map(yamlString).joined(separator: ", "))]") }
        if let audio = entry.audio { lines.append("audio: ../\(audio)") }
        if !entry.pages.isEmpty { lines.append("pages: [\(entry.pages.map { "../\($0)" }.joined(separator: ", "))]") }
        lines.append("---")
        lines.append("")
        if !entry.title.isEmpty {
            lines.append("# \(entry.title)")
            lines.append("")
        }
        lines.append(MarkdownCodec.render(text: entry.text, formatting: EntryFormatting(raw: entry.formatting) ?? .empty))
        return lines.joined(separator: "\n") + "\n"
    }

    nonisolated static func yamlString(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: " ") + "\""
    }

    // "2026-09-21 Coffee with Maya.md", with a number added when two entries would share a name.
    private static func uniqueFileName(for entry: Entry, calendar: Calendar, used: inout Set<String>) -> String {
        let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let unsafe = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines).union(.controlCharacters)
        let cleaned = String(title.unicodeScalars.map { unsafe.contains($0) ? " " : Character($0) }).split(separator: " ").joined(separator: " ")
        let base = cleaned.isEmpty ? day(entry.entryDate, calendar: calendar) : "\(day(entry.entryDate, calendar: calendar)) \(cleaned.prefix(80))"
        var name = "\(base).md"
        var number = 2
        while !used.insert(name.lowercased()).inserted {
            name = "\(base) \(number).md"
            number += 1
        }
        return name
    }

    nonisolated static func day(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
