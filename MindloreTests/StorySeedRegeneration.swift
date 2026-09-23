import Foundation
import SwiftData
import Testing
@testable import Mindlore

// Not a test: the tool that writes the story seed's insights (scripts/demo/regenerate-story.sh).
// It replays Teo's year one entry at a time through what the app itself runs when an entry's
// insights come back: the real request against OpenAI, with the vocabulary the graph built from
// every earlier entry and the loose ends still open, then the graph indexer and the loose-end
// writer. What comes out is the journal a real user with this text would have, parts included.
//
// Costs about 200 paid calls, so it needs the key and an explicit opt-in, and CI sets neither.
// Each finished entry is appended to `story-insights.jsonl` in the app's tmp directory in the
// story's own JSON shape, so a run that stops continues where it left off, replaying what was
// already written instead of paying for it again.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MINDLORE_OPENAI_KEY"]?.isEmpty == false
    && ProcessInfo.processInfo.environment["MINDLORE_REGENERATE_STORY"] == "1"))
struct StorySeedRegeneration {
    static let outputName = "story-insights.jsonl"

    private let container: ModelContainer
    private let indexer = GraphIndexer(diagnostics: .disabled)
    private let sections = InsightSections()
    private let generator = OpenAICompatibleTextGenerator(
        baseURL: URL(string: "https://api.openai.com/v1")!,
        apiKey: ProcessInfo.processInfo.environment["MINDLORE_OPENAI_KEY"] ?? "",
        http: URLSessionHTTPClient(),
        quirks: ProviderQuirks()
    )

    init() throws {
        container = try ModelContainerFactory.make(.inMemory)
    }

    @Test(.timeLimit(.minutes(60)))
    func regenerate() async throws {
        let context = container.mainContext
        let story = try DemoStory.entries()
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(Self.outputName)
        let written = try Self.recorded(at: output)
        print("REGEN output \(output.path) resuming after \(written.count)")

        // A trial run stops after this many new calls, keeping what it wrote.
        let limit = Int(ProcessInfo.processInfo.environment["MINDLORE_REGENERATE_STORY_LIMIT"] ?? "") ?? .max
        var called = 0
        var threadIDs: [UUID: String] = [:]
        var threadsByID: [String: UUID] = [:]
        for (index, entry) in story.enumerated() {
            if written[entry.date] == nil, called >= limit {
                print("REGEN stopped at the limit of \(limit) calls")
                return
            }
            let date = try #require(DemoStory.written(from: entry.date))
            LooseEnd.fade(in: context, now: date, diagnostics: .disabled)
            let record = Entry(createdAt: date, source: .typed, text: entry.text)
            record.title = entry.title
            record.titleWasGenerated = true
            record.automaticAIPassUsed = true
            context.insert(record)

            if let done = written[entry.date] {
                write(done, to: record, in: context)
                replayLooseEnds(done, on: record, threads: &threadsByID, ids: &threadIDs, in: context)
            } else {
                called += 1
                var result = try await insights(for: record, in: context)
                result.kind = CreativeSignals.decideKind(modelSays: result.kind, text: entry.text, onDevice: false, focused: nil)
                result.restrict(to: result.kind)
                let line = regenerated(entry, from: result)
                write(line, to: record, in: context)
                LooseEndWriter.apply(result.looseEnds, to: record, in: context, now: date)
                let final = recordLooseEnds(line, result: result, on: record, threads: &threadsByID, ids: &threadIDs, in: context)
                try append(final, to: output)
                print("REGEN \(index + 1)/\(story.count) kind \(final.kind.rawValue) parts \(final.sections.count) names \(final.mentions.count) tags \(final.tags.count) opens \(final.opens.count) resolves \(final.resolves.count) touches \(final.touches.count)")
            }
            try context.save()
        }

        let looseEnds = LooseEnd.all(in: context)
        print("REGEN done: threads \(looseEnds.count), open \(looseEnds.filter(\.isOpen).count), resolved \(looseEnds.filter { $0.status == .resolved }.count), faded \(looseEnds.filter { $0.status == .faded }.count)")
    }

    // MARK: - The request, as InsightsCoordinator makes it

    private func insights(for entry: Entry, in context: ModelContext) async throws -> InsightsResult {
        var vocabulary = indexer.vocabulary(in: context, sections: sections)
            ?? .init(tags: InsightsCoordinator.topTags(in: context))
        vocabulary.looseEnds = LooseEndWriter.candidates(for: entry, in: context)
        let plan = InsightsPromptBuilder.plan(text: entry.text, source: entry.source, sections: sections, vocabulary: vocabulary, model: ProviderDefaults.textModel, entryDate: entry.entryDate)
        var lastError: Error?
        for attempt in 1...3 {
            do {
                let response = try await generator.generate(plan.request)
                return try InsightsPromptBuilder.parse(response.text, plan: plan)
            } catch {
                lastError = error
                print("REGEN attempt \(attempt) failed: \(AIJobFailure(any: error).raw)")
                try await Task.sleep(for: .seconds(5 * attempt))
            }
        }
        throw lastError ?? CancellationError()
    }

    // The coordinator's write (InsightsCoordinator, after restrict), then the graph's.
    private func write(_ line: DemoStory.StoryEntry, to entry: Entry, in context: ModelContext) {
        entry.kind = line.kind
        let insights = EntryInsights(generatedAt: entry.createdAt.addingTimeInterval(60), modelUsed: "demo", sourceTextHash: TextHash.of(entry.text))
        context.insert(insights)
        insights.entry = entry
        insights.summary = line.summary
        insights.setMoods(primary: line.mood, secondary: line.secondaryMood.map { [$0] } ?? [], editedByUser: false)
        insights.areas = line.areas
        insights.tags = line.tags
        insights.mentions = line.mentions.map { Mention(name: $0.name, kindRaw: $0.kind.rawValue, writtenSurface: $0.writtenSurface) }
        insights.sections = line.sections
        indexer.index(entry, in: context)
        indexer.recount(in: context)
    }

    // MARK: - Loose ends, in the seed's own terms

    // A line already on disk goes through the writer the way `DemoStory.seed` sends it.
    private func replayLooseEnds(_ line: DemoStory.StoryEntry, on entry: Entry, threads: inout [String: UUID], ids: inout [UUID: String], in context: ModelContext) {
        var result = LooseEndResult()
        result.new = line.opens.map { .init(text: $0.text, about: $0.about, due: $0.due.flatMap { DemoStory.written(from: $0) }) }
        result.resolved = line.resolves.compactMap { threads[$0] }
        result.mentioned = line.touches.compactMap { threads[$0] }
        guard !result.isEmpty else { return }
        LooseEndWriter.apply(result, to: entry, in: context, now: entry.createdAt)
        let entryID = entry.id
        let created = LooseEnd.all(in: context).filter { $0.sourceEntryID == entryID }
        // By text, as `DemoStory.seed` matches them: threads one entry opens share a creation
        // date, so their order says nothing.
        for open in line.opens {
            guard let looseEnd = created.first(where: { $0.text == open.text }) else { continue }
            threads[open.id] = looseEnd.id
            ids[looseEnd.id] = open.id
        }
    }

    // After the writer ran on a live answer: what it created, settled, and touched, as the seed
    // spells them. `about` is kept to this entry's own mention names, which is what the writer
    // matched against, so seeding resolves it to the same entities.
    private func recordLooseEnds(_ line: DemoStory.StoryEntry, result: InsightsResult, on entry: Entry, threads: inout [String: UUID], ids: inout [UUID: String], in context: ModelContext) -> DemoStory.StoryEntry {
        let entryID = entry.id
        let all = LooseEnd.all(in: context)
        let created = all.filter { $0.sourceEntryID == entryID }.sorted { $0.createdAt < $1.createdAt }
        let links = ((try? context.fetch(FetchDescriptor<EntityLink>(predicate: #Predicate { $0.entryID == entryID }))) ?? [])
        let mentionNames = Set(line.mentions.map(\.name))
        let openIDs = created.indices.map { String(format: "t%03d", threads.count + $0 + 1) }
        let opens = zip(openIDs, created).map { id, looseEnd -> [String: Any] in
            let about = links.filter { link in link.entityID.map(looseEnd.entityIDs.contains) == true && mentionNames.contains(link.surface) }.map(\.surface)
            var open: [String: Any] = ["id": id, "text": looseEnd.text]
            if !about.isEmpty { open["about"] = Array(Set(about)).sorted() }
            if let due = looseEnd.dueDate { open["due"] = Self.day(due) }
            return open
        }
        for (id, looseEnd) in zip(openIDs, created) {
            threads[id] = looseEnd.id
            ids[looseEnd.id] = id
        }
        let resolves = all.filter { $0.resolvedByEntryID == entryID && $0.status == .resolved }.compactMap { ids[$0.id] }.sorted()
        let touches = result.looseEnds.mentioned.filter { id in !all.contains { $0.id == id && $0.resolvedByEntryID == entryID } }.compactMap { ids[$0] }.sorted()

        var object = Self.object(line)
        if !opens.isEmpty { object["opens"] = opens }
        if !resolves.isEmpty { object["resolves"] = resolves }
        if !touches.isEmpty { object["touches"] = touches }
        // Round-trips through the seed's own decoder, so what lands on disk is what seeding reads.
        return try! JSONDecoder().decode(DemoStory.StoryEntry.self, from: JSONSerialization.data(withJSONObject: object))
    }

    // MARK: - The line

    private func regenerated(_ entry: DemoStory.StoryEntry, from result: InsightsResult) -> DemoStory.StoryEntry {
        var object: [String: Any] = [
            "date": entry.date,
            "title": entry.title,
            "text": entry.text,
            "summary": result.summary ?? "",
            "areas": result.areas.map(\.rawValue),
            "tags": result.tags,
            "mentions": result.mentions.map { mention -> [String: Any] in
                var object: [String: Any] = ["name": mention.name, "kind": mention.kindRaw]
                if let written = mention.writtenSurface { object["writtenSurface"] = written }
                return object
            },
        ]
        if let mood = result.primaryMood { object["mood"] = mood.rawValue }
        if let secondary = result.secondaryMoods.first { object["secondaryMood"] = secondary.rawValue }
        if result.kind != .journal { object["kind"] = result.kind.rawValue }
        if !result.sections.isEmpty {
            object["sections"] = result.sections.map { Self.jsonObject(encoding: $0) }
        }
        return try! JSONDecoder().decode(DemoStory.StoryEntry.self, from: JSONSerialization.data(withJSONObject: object))
    }

    static func object(_ entry: DemoStory.StoryEntry) -> [String: Any] {
        var object: [String: Any] = [
            "date": entry.date,
            "title": entry.title,
            "text": entry.text,
            "summary": entry.summary,
            "areas": entry.areas.map(\.rawValue),
            "tags": entry.tags,
            "mentions": entry.mentions.map { mention -> [String: Any] in
                var object: [String: Any] = ["name": mention.name, "kind": mention.kind.rawValue]
                if let written = mention.writtenSurface { object["writtenSurface"] = written }
                return object
            },
        ]
        if let mood = entry.mood { object["mood"] = mood.rawValue }
        if let secondary = entry.secondaryMood { object["secondaryMood"] = secondary.rawValue }
        if entry.kind != .journal { object["kind"] = entry.kind.rawValue }
        if !entry.sections.isEmpty { object["sections"] = entry.sections.map { jsonObject(encoding: $0) } }
        if !entry.opens.isEmpty {
            object["opens"] = entry.opens.map { open -> [String: Any] in
                var object: [String: Any] = ["id": open.id, "text": open.text]
                if !open.about.isEmpty { object["about"] = open.about }
                if let due = open.due { object["due"] = due }
                return object
            }
        }
        if !entry.resolves.isEmpty { object["resolves"] = entry.resolves }
        if !entry.touches.isEmpty { object["touches"] = entry.touches }
        return object
    }

    private static func jsonObject<T: Encodable>(encoding value: T) -> Any {
        (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(value))) ?? [:]
    }

    private static func day(_ date: Date) -> String {
        // The same zone `DemoStory.written` reads it back in, so a due date near midnight keeps its day.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.current.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - The file

    private static func recorded(at url: URL) throws -> [String: DemoStory.StoryEntry] {
        guard let data = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var lines: [String: DemoStory.StoryEntry] = [:]
        for line in data.split(separator: "\n") where !line.isEmpty {
            let entry = try JSONDecoder().decode(DemoStory.StoryEntry.self, from: Data(line.utf8))
            lines[entry.date] = entry
        }
        return lines
    }

    private func append(_ entry: DemoStory.StoryEntry, to url: URL) throws {
        var data = try JSONSerialization.data(withJSONObject: Self.object(entry), options: [.sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: url) {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } else {
            try data.write(to: url)
        }
    }
}
