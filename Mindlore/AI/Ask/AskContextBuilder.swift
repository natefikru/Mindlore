import Foundation

// Picks what a question actually needs from the journal and turns it into prompt blocks, inside
// a character budget. Pure: the caller fetches, filters for what may be sent, and hands the
// arrays over. Every tier, the entity excerpts included, draws only from `entries`, so an entry
// the caller excluded can never reach a provider through a side door.
nonisolated enum AskContextBuilder {
    static let openAIBudget = 24_000
    static let onDeviceBudget = 6_000
    // Held back from the on-device budget for the answer itself, whose tokens share the session.
    static let onDeviceAnswerHeadroom = 1_500
    static let maxEntryCharacters = 2_000
    static let maxLooseEndsPerEntity = 5
    static let maxExcerptEntriesPerEntity = 10
    static let recentEntryCount = 5

    static let openDelimiter = "<<<entry"
    static let closeDelimiter = "entry>>>"

    nonisolated struct EntryInput: Equatable, Sendable {
        let id: UUID
        let date: Date
        let title: String
        let text: String
        var entityIDs: [UUID] = []
    }

    nonisolated struct EntityInput: Equatable, Sendable {
        let id: UUID
        let name: String
        var aliases: [String] = []
        var bio: String?
        var openLooseEnds: [String] = []
    }

    nonisolated struct Block: Equatable, Sendable {
        let text: String
        // The entry this block quotes, or nil for an entity's own block.
        let entryID: UUID?
    }

    nonisolated struct Context: Equatable, Sendable {
        var blocks: [Block] = []
        var handles: [String: UUID] = [:]
        var characters: Int = 0
        // The entries that actually went in, in the order they appear. What "What was sent" lists.
        var entryIDs: [UUID] = []

        var isEmpty: Bool { entryIDs.isEmpty }

        var text: String { blocks.map(\.text).joined(separator: "\n\n") }

        // The handle a block used for each included entry, so citations can be enumerated.
        func handle(for entryID: UUID) -> String? {
            handles.first { $0.value == entryID }?.key
        }

        // Only the handles this request actually carried. `handles` also holds earlier turns'
        // entries, which are not in this prompt: a model citing one of those would be pointing
        // at something it never read.
        var handlesSent: Set<String> {
            Set(entryIDs.compactMap(handle(for:)))
        }
    }

    static func build(
        question: String,
        entries: [EntryInput],
        entities: [EntityInput],
        handles: [String: UUID] = [:],
        now: Date,
        calendar: Calendar = .current,
        budget: Int
    ) -> Context {
        var builder = Builder(handles: handles, budget: budget)
        let newestFirst = entries.sorted { $0.date > $1.date }

        // 1. Entities the question names: who they are, what is still open about them, and the
        //    sentences the journal wrote about them.
        let named = entities.filter { entity in
            ([entity.name] + entity.aliases).contains { NameMatching.range(of: $0, in: question) != nil }
        }
        for entity in named {
            builder.addEntity(entity)
            let linked = newestFirst.filter { $0.entityIDs.contains(entity.id) }.prefix(maxExcerptEntriesPerEntity)
            for entry in linked {
                let sentences = BioExcerpts.sentences(in: entry.text, naming: [entity.name] + entity.aliases)
                guard !sentences.isEmpty else { continue }
                builder.addEntry(entry, text: sentences.joined(separator: " "))
            }
        }

        // 2. What the question's own words match.
        let keywords = Self.keywords(in: question)
        if !keywords.isEmpty {
            let scored = newestFirst
                .map { entry -> (entry: EntryInput, matches: Int) in
                    let haystack = entry.title + " " + entry.text
                    return (entry, keywords.filter { NameMatching.range(of: $0, in: haystack) != nil }.count)
                }
                .filter { $0.matches > 0 }
                .enumerated()
                .sorted { lhs, rhs in
                    lhs.element.matches == rhs.element.matches ? lhs.offset < rhs.offset : lhs.element.matches > rhs.element.matches
                }
            for scored in scored {
                builder.addEntry(scored.element.entry, text: scored.element.entry.text)
            }
        }

        // 3. A stretch of time the question names.
        if let range = AskDates.range(in: question, now: now, calendar: calendar) {
            // Half-open, as AskDates documents it: DateInterval.contains would include the
            // first instant of the next day.
            for entry in newestFirst where entry.date >= range.start && entry.date < range.end {
                builder.addEntry(entry, text: entry.text)
            }
        }

        // 4. Only when nothing above matched at all, an entity's own block included. A question
        //    the journal has nothing to say about shouldn't quietly send five entries and bill
        //    for them.
        if builder.context.blocks.isEmpty {
            for entry in newestFirst.prefix(recentEntryCount) {
                builder.addEntry(entry, text: entry.text)
            }
        }

        return builder.context
    }

    // MARK: - Keywords

    // Small, fixed, and English, like the date phrases. A word under three letters carries no
    // search value here, and a stop word matches half the journal.
    static let stopWords: Set<String> = [
        "the", "and", "but", "for", "was", "were", "with", "that", "this", "those", "these",
        "what", "when", "where", "who", "whom", "why", "how", "did", "does", "doing", "done",
        "have", "has", "had", "you", "your", "yours", "our", "ours", "her", "his", "him", "she",
        "they", "them", "their", "theirs", "about", "into", "from", "been", "being", "are",
        "any", "all", "some", "there", "here", "then", "than", "not", "just", "much", "many",
        "more", "most", "can", "could", "would", "should", "will", "shall", "may", "might",
        "tell", "say", "said", "know", "think", "thing", "things", "get", "got", "going", "go",
        "me", "my", "mine", "i", "it", "its", "am", "is", "be", "do", "of", "in", "on", "at",
        "to", "as", "by", "or", "if", "so", "up", "out", "over", "again", "still", "ever",
        "lately", "recently", "last", "next", "week", "weeks", "month", "months", "year",
        "years", "day", "days", "today", "yesterday", "time", "times", "anything", "everything",
        "something", "nothing", "happened", "happening", "happen",
    ]

    static func keywords(in question: String) -> [String] {
        var words: [String] = []
        var seen: Set<String> = []
        question.enumerateSubstrings(in: question.startIndex..., options: .byWords) { substring, _, _, _ in
            guard let word = substring?.lowercased(), word.count >= 3, !stopWords.contains(word) else { return }
            if seen.insert(word).inserted { words.append(word) }
        }
        return words
    }

    // MARK: - Safety

    // Nothing an entry contains may close its own block or hand itself a citation. Both
    // delimiter tokens and anything shaped like a handle are taken out before the text goes in.
    static func sanitized(_ text: String) -> String {
        var cleaned = text
            .replacingOccurrences(of: openDelimiter, with: "")
            .replacingOccurrences(of: closeDelimiter, with: "")
        if let regex = try? NSRegularExpression(pattern: "\\[\\s*[Ee]\\d+\\s*\\]") {
            cleaned = regex.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "")
        }
        return cleaned
    }

    // Cut at the end of the last whole sentence that fits, so a block never ends mid-thought.
    static func trimmed(_ text: String, to limit: Int = maxEntryCharacters) -> String {
        guard text.count > limit else { return text }
        var kept = ""
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { substring, _, _, stop in
            guard let substring else { return }
            guard kept.count + substring.count <= limit else {
                stop = true
                return
            }
            kept += substring
        }
        let body = kept.trimmingCharacters(in: .whitespacesAndNewlines)
        // A single sentence longer than the whole budget still has to be cut somewhere.
        return body.isEmpty ? String(text.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) : body
    }

    static func block(handle: String, date: Date, title: String, text: String) -> String {
        var header = "[\(handle)] \(dateFormatter.string(from: date))"
        if let title = InsightsPromptBuilder.promptSafe(sanitized(title)) {
            header += " \(title)"
        }
        return "\(header)\n\(openDelimiter)\n\(text)\n\(closeDelimiter)"
    }

    // The entry's own day, as the phone shows it, so "yesterday" in a question and the date on a
    // block mean the same thing.
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // MARK: - Building

    private struct Builder {
        var context: Context
        let budget: Int
        private var usedEntries: Set<UUID> = []
        private var usedEntities: Set<UUID> = []
        private var nextHandle: Int

        init(handles: [String: UUID], budget: Int) {
            context = Context(handles: handles)
            self.budget = budget
            let used = handles.keys.compactMap { Int($0.dropFirst()) }
            nextHandle = (used.max() ?? 0) + 1
        }

        mutating func addEntity(_ entity: EntityInput) {
            guard usedEntities.insert(entity.id).inserted else { return }
            var lines = ["About \(sanitized(entity.name)):"]
            if let bio = entity.bio?.trimmingCharacters(in: .whitespacesAndNewlines), !bio.isEmpty {
                lines.append(sanitized(bio))
            }
            let open = entity.openLooseEnds.prefix(maxLooseEndsPerEntity).map { "- \(sanitized($0))" }
            if !open.isEmpty {
                lines.append("Still open:")
                lines.append(contentsOf: open)
            }
            guard lines.count > 1 else { return }
            append(Block(text: lines.joined(separator: "\n"), entryID: nil))
        }

        // One entry goes in once, at the first tier that asked for it.
        mutating func addEntry(_ entry: EntryInput, text: String) {
            guard !usedEntries.contains(entry.id) else { return }
            let body = trimmed(sanitized(text).trimmingCharacters(in: .whitespacesAndNewlines))
            guard !body.isEmpty else { return }
            let existing = context.handles.first { $0.value == entry.id }?.key
            let handle = existing ?? "E\(nextHandle)"
            let rendered = block(handle: handle, date: entry.date, title: entry.title, text: body)
            // A block that doesn't fit is skipped whole; a smaller one later can still go in,
            // and the handle it would have taken stays free.
            guard append(Block(text: rendered, entryID: entry.id)) else { return }
            if existing == nil { nextHandle += 1 }
            usedEntries.insert(entry.id)
            context.handles[handle] = entry.id
            context.entryIDs.append(entry.id)
        }

        @discardableResult
        private mutating func append(_ block: Block) -> Bool {
            let separator = context.blocks.isEmpty ? 0 : 2
            guard context.characters + separator + block.text.count <= budget else { return false }
            context.blocks.append(block)
            context.characters += separator + block.text.count
            return true
        }
    }
}
