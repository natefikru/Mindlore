import Foundation

// Turns what AskRetrieval.plan chose into prompt blocks, and holds the real budget while doing it.
//
// It no longer decides anything. The four tiers that used to live here each appended entries until
// the budget ran out, so the budget defined the list; now the plan defines the list and this spends
// the budget slice by slice, in order, each slice capped so an earlier one cannot eat the room the
// entries needed. Pure: the caller fetched, filtered for what may be sent, and hands the arrays
// over.
nonisolated enum AskContextBuilder {
    static let openAIBudget = 24_000
    static let onDeviceBudget = 6_000
    // Held back from the on-device budget for the answer itself, whose tokens share the session.
    static let onDeviceAnswerHeadroom = 1_500
    static let maxEntryCharacters = 2_000
    static let maxLooseEndsPerEntity = 5
    static let maxAliasesPerEntity = 5
    static let maxExcerptEntriesPerEntity = 10

    // The fence, the "About <name>" line, and the "Still open:" header an About block always pays.
    static let aboutBlockOverhead = 40

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
        // How many entries matched before the cut, so the prompt and the cost line can own up to it.
        var matchedCount = 0
        var rollupMonthCount = 0

        var isEmpty: Bool { entryIDs.isEmpty }
        var wasCut: Bool { matchedCount > entryIDs.count }

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

    // Renders in prompt order: who the question is about, then any summary, then the entries the
    // conversation was already discussing, then the best matches. Best matches go last on purpose,
    // nearest the question.
    static func render(
        plan: AskRetrieval.Plan,
        selection: AskSources.Selection,
        rollups: [String] = [],
        // What the question asked, so an excerpt keeps the sentences that answer it and not only
        // the ones naming the person.
        terms: [String] = [],
        handles: [String: UUID] = [:],
        budget: Int
    ) -> Context {
        var builder = Builder(handles: handles)
        let entriesByID = Dictionary(selection.entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        builder.beginSlice(cap: plan.slices.about, budget: budget)
        for entity in selection.entities {
            builder.addEntity(entity)
        }

        builder.beginSlice(cap: plan.slices.rollups, budget: budget)
        for rollup in rollups {
            builder.addFenced(rollup)
        }

        builder.beginSlice(cap: plan.slices.continuity, budget: budget)
        for id in plan.continuityEntryIDs {
            guard let entry = entriesByID[id] else { continue }
            builder.addEntry(entry, text: text(for: entry, plan: plan, entities: selection.entities, terms: terms))
        }

        // Everything left, so a slice that went unused is not wasted.
        builder.beginSlice(cap: budget, budget: budget)
        for id in plan.rankedEntryIDs {
            guard let entry = entriesByID[id] else { continue }
            builder.addEntry(entry, text: text(for: entry, plan: plan, entities: selection.entities, terms: terms))
        }

        var context = builder.context
        context.matchedCount = max(plan.matchedCount, context.entryIDs.count)
        context.rollupMonthCount = plan.rollupMonths.count
        return context
    }

    // An entry reached because the question is about someone is quoted at the sentences that concern
    // them, which is what the old tier 1 did and why ten of them fit where three whole blocks would.
    // The question's own words count as well as the name: "what did Maya say about the move" should
    // keep the sentence about the move, not only the ones spelling Maya.
    private static func text(for entry: EntryInput, plan: AskRetrieval.Plan, entities: [EntityInput], terms: [String]) -> String {
        guard plan.excerptEntryIDs.contains(entry.id) else { return entry.text }
        let names = entities
            .filter { entry.entityIDs.contains($0.id) }
            .flatMap { [$0.name] + $0.aliases }
        let wanted = names + terms
        guard !wanted.isEmpty else { return entry.text }
        let sentences = BioExcerpts.sentences(in: entry.text, naming: wanted)
        // An entry linked to her that never spells her name, and whose words the question does not
        // use either, has no sentences to pick. It goes in whole rather than not at all.
        return sentences.isEmpty ? entry.text : sentences.joined(separator: " ")
    }

    // MARK: - Stop words

    // Small, fixed, and English, like the date phrases. A stop word matches half the journal.
    // AskRetrievalQuery.terms is the only reader now, and it keeps two-letter words: this list
    // already covers the two-letter English noise, and the old three-letter floor cost "AI".
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

    // What rendering this entry would cost, without rendering it. The index stores this per document
    // so a plan can divide a budget with no entry text in hand, which is what makes the line under
    // the field free. Deliberately an upper bound: sanitizing only ever removes characters, so the
    // estimate never promises more room than there is.
    static func blockCharacterEstimate(title: String, text: String) -> Int {
        let header = "[E00] 2026-09-18 ".count + title.count
        let fence = openDelimiter.count + closeDelimiter.count + 3
        return header + fence + min(text.count, maxEntryCharacters)
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
        private var usedEntries: Set<UUID> = []
        private var usedEntities: Set<UUID> = []
        private var nextHandle: Int
        // Where the slice being filled has to stop. The budget is spent in order, and a slice that
        // goes unused leaves its room to whatever comes after it, which is why ranked is last.
        private var sliceEnd = 0

        init(handles: [String: UUID]) {
            context = Context(handles: handles)
            let used = handles.keys.compactMap { Int($0.dropFirst()) }
            nextHandle = (used.max() ?? 0) + 1
        }

        mutating func beginSlice(cap: Int, budget: Int) {
            sliceEnd = min(budget, context.characters + max(0, cap))
        }

        // A rollup is generated from entries, so it is no more trusted than one and goes inside the
        // same fence.
        mutating func addFenced(_ body: String) {
            let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            append(Block(text: "\(openDelimiter)\n\(sanitized(text))\n\(closeDelimiter)", entryID: nil))
        }

        // A bio and a loose end are written from entry text, which can come from a photographed
        // page, so they are no more trusted than an entry and go inside the same fence.
        mutating func addEntity(_ entity: EntityInput) {
            guard usedEntities.insert(entity.id).inserted else { return }
            let name = InsightsPromptBuilder.promptSafe(sanitized(entity.name)) ?? "Someone"
            var lines = ["About \(name)"]
            // The entries spell a renamed or corrected name the way they were written ("Lewis"
            // for a Luis the user renamed). Without this the model reads the two as different
            // people and says so in the answer.
            let otherSpellings = entity.aliases
                .compactMap { InsightsPromptBuilder.promptSafe(sanitized($0)) }
                .filter { $0.caseInsensitiveCompare(name) != .orderedSame }
                .prefix(maxAliasesPerEntity)
            if !otherSpellings.isEmpty {
                lines.append("Also written in the journal as: \(otherSpellings.joined(separator: ", "))")
            }
            if let bio = entity.bio?.trimmingCharacters(in: .whitespacesAndNewlines), !bio.isEmpty {
                lines.append(sanitized(bio))
            }
            let open = entity.openLooseEnds.prefix(maxLooseEndsPerEntity).map { "- \(sanitized($0))" }
            if !open.isEmpty {
                lines.append("Still open:")
                lines.append(contentsOf: open)
            }
            guard lines.count > 1 else { return }
            let fenced = "\(openDelimiter)\n\(lines.joined(separator: "\n"))\n\(closeDelimiter)"
            append(Block(text: fenced, entryID: nil))
        }

        // One entry goes in once, in whichever slice reached it first.
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
            guard context.characters + separator + block.text.count <= sliceEnd else { return false }
            context.blocks.append(block)
            context.characters += separator + block.text.count
            return true
        }
    }
}
