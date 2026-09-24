import Foundation

// Turns what AskRetrieval.plan chose into prompt blocks, and holds the real budget while doing it.
//
// It no longer decides anything. The four tiers that used to live here each appended entries until
// the budget ran out, so the budget defined the list; now the plan defines the list and this spends
// the budget slice by slice, in order, each slice capped so an earlier one cannot eat the room the
// entries needed. Pure: the caller fetched, filtered for what may be sent, and hands the arrays
// over.
nonisolated enum AskContextBuilder {
    // Raised from 24,000 with the digest tier (owner, 2026-09-19). Twenty whole entries and a
    // hundred and fifty lines land near 60,000 characters, about 16,000 tokens, which is a question
    // worth its price on a journal of three hundred entries. The old number was set when Apple's
    // on-device model was the peer and a year's question came back answered from two weeks.
    static let openAIBudget = 64_000
    static let onDeviceBudget = 6_000
    // Held back from the on-device budget for the answer itself, whose tokens share the session.
    static let onDeviceAnswerHeadroom = 1_500
    static let maxEntryCharacters = 2_000
    static let maxLooseEndsPerEntity = 5
    static let maxAliasesPerEntity = 5

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
        var isCreative = false
        var isNote = false
        // A note's text with its layout, as Markdown, so a checklist reads as one and a note Chat
        // is asked to change keeps its shape. Nil for anything else, and for a note with no layout.
        var markdown: String?
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
        // Digests are in here too: a one-line entry went out the same as a whole one did.
        var entryIDs: [UUID] = []
        // Which of those went as a single line, so the privacy sheet can say "in full" against "in
        // one line" and the diagnostics can count the two apart.
        var digestEntryIDs: [UUID] = []
        // The entries whose every word went in: not a line, not an excerpt, not cut to fit. Only
        // one of these can be rewritten whole, which is what editing a note is.
        var wholeEntryIDs: Set<UUID> = []
        // How many entries matched before the cut, so the prompt and the cost line can own up to it.
        var matchedCount = 0
        var rollupMonthCount = 0

        var isEmpty: Bool { entryIDs.isEmpty }
        var wasCut: Bool { matchedCount > entryIDs.count }
        // The entries the model can read in full, which is what a quote may come from.
        var fullEntryCount: Int { entryIDs.count - digestEntryIDs.count }

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

        // The entry the conversation is about, first and whole: the plan already charged the budget
        // for it, so it takes no slice's room.
        if let id = plan.focusEntryID, let entry = entriesByID[id] {
            builder.beginSlice(cap: budget, budget: budget)
            builder.addEntry(entry, text: entry.text, limit: plan.focusTextLimit)
        }

        // Notes made or changed earlier in this conversation, whole, so "add butter to that list"
        // reaches the list. Charged by the plan like the focus.
        if !plan.noteEntryIDs.isEmpty {
            builder.beginSlice(cap: budget, budget: budget)
            for id in plan.noteEntryIDs {
                guard let entry = entriesByID[id] else { continue }
                builder.addEntry(entry, text: entry.text)
            }
        }

        builder.beginSlice(cap: plan.slices.about, budget: budget)
        for entity in selection.entities {
            builder.addEntity(entity)
        }

        builder.beginSlice(cap: plan.slices.rollups, budget: budget)
        var summarizedMonths = 0
        for rollup in rollups where builder.addFenced(rollup) {
            summarizedMonths = plan.rollupMonths.count
        }

        // The slice the plan actually spent, not the ceiling it chose from, so an over-reserved
        // digest block cannot hold room the entries needed.
        builder.beginSlice(cap: plan.digestCharacters, budget: budget)
        builder.addDigests(plan.digestEntryIDs.compactMap { entriesByID[$0] })

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
        // What went out, not what was planned. "What was sent" is the screen that has to be true
        // where the cost line is only an estimate, and a summary that failed its slice is not sent.
        context.rollupMonthCount = summarizedMonths
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
    // To a fixpoint, not once. A single pass is defeated by nesting: "entrentry>>>y>>>" has its
    // inner "entry>>>" removed and the outer halves close up into a live delimiter, and "[E[E3]3]"
    // does the same for a handle. One line closing the fence puts every line after it, in a digest
    // block of up to a hundred and fifty entries, outside the data fence at instruction level.
    static func sanitized(_ text: String) -> String {
        let handles = try? NSRegularExpression(pattern: "\\[\\s*[Ee]\\d+\\s*\\]")
        var cleaned = text
        // Each pass strictly shortens the string, so this terminates; the bound is belt and braces.
        for _ in 0..<maxSanitizePasses {
            let before = cleaned
            cleaned = cleaned
                .replacingOccurrences(of: openDelimiter, with: "")
                .replacingOccurrences(of: closeDelimiter, with: "")
            if let handles {
                cleaned = handles.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "")
            }
            if cleaned == before { return cleaned }
        }
        return cleaned
    }

    static let maxSanitizePasses = 8

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
        // "[E123] ", not "[E00] ": one aggregate question mints up to a hundred and fifty handles,
        // so the next turn of that conversation is handing out four-digit ones.
        let header = "[E1234] 2026-09-18 ".count + title.count + creativeMarker.count
        let fence = openDelimiter.count + closeDelimiter.count + 3
        return header + fence + min(text.count, maxEntryCharacters)
    }

    // Said on the block itself, so a lyric about Memphis never answers "have I been to Memphis?".
    static let creativeMarker = " (a creative piece the author wrote, not an account of events)"
    // A list or a plan is what the author kept, not what happened to them that day. Shorter than
    // the creative marker, which is what the character estimate above is sized on.
    static let noteMarker = " (a note the author kept, not an account of a day)"

    static func block(handle: String, date: Date, title: String, text: String, creative: Bool = false, note: Bool = false) -> String {
        var header = "[\(handle)] \(dateFormatter.string(from: date))"
        if let title = InsightsPromptBuilder.promptSafe(sanitized(title)) {
            header += " \(title)"
        }
        if creative {
            header += creativeMarker
        } else if note {
            header += noteMarker
        }
        return "\(header)\n\(openDelimiter)\n\(text)\n\(closeDelimiter)"
    }

    // The entry's own day, as the phone shows it, so "yesterday" in a question and the date on a
    // block mean the same thing.
    // Shared with AskDigests, so a whole block and a one-line digest of the same day can never
    // print two different dates.
    static let dateFormatter: DateFormatter = {
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
        @discardableResult
        mutating func addFenced(_ body: String) -> Bool {
            let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return false }
            return append(Block(text: "\(openDelimiter)\n\(sanitized(text))\n\(closeDelimiter)", entryID: nil))
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

        // Every digest in one fenced block, because the fence costs seventeen characters and says
        // the same thing a hundred and fifty times over. Lines are measured as they are added and
        // the block is appended once, so a line that doesn't fit is the only thing lost.
        mutating func addDigests(_ entries: [EntryInput]) {
            let separator = context.blocks.isEmpty ? 0 : 2
            var length = separator + openDelimiter.count + closeDelimiter.count + 2
            var lines: [String] = []
            var taken: [(handle: String, id: UUID)] = []
            var handle = nextHandle

            for entry in entries where !usedEntries.contains(entry.id) {
                let existing = context.handles.first { $0.value == entry.id }?.key
                let name = existing ?? "E\(handle)"
                let line = AskDigests.line(handle: name, date: entry.date, title: entry.title, text: entry.text)
                // A day with no title and no text renders as a bare handle and a date. It would
                // still take a handle, count towards "read as one line", and be citable.
                guard AskDigests.saysSomething(line) else { continue }
                let cost = line.count + (lines.isEmpty ? 0 : 1)
                guard context.characters + length + cost <= sliceEnd else { break }
                length += cost
                lines.append(line)
                taken.append((name, entry.id))
                if existing == nil { handle += 1 }
            }

            guard !lines.isEmpty else { return }
            let block = Block(text: "\(openDelimiter)\n\(lines.joined(separator: "\n"))\n\(closeDelimiter)", entryID: nil)
            guard append(block) else { return }
            nextHandle = handle
            for line in taken {
                usedEntries.insert(line.id)
                context.handles[line.handle] = line.id
                context.entryIDs.append(line.id)
                context.digestEntryIDs.append(line.id)
            }
        }

        // One entry goes in once, in whichever slice reached it first.
        mutating func addEntry(_ entry: EntryInput, text: String, limit: Int = maxEntryCharacters) {
            guard !usedEntries.contains(entry.id) else { return }
            // The entry's own text, not an excerpt of it, goes in with its layout when it has one.
            let isOwnText = text == entry.text
            let full = sanitized(isOwnText ? (entry.markdown ?? text) : text).trimmingCharacters(in: .whitespacesAndNewlines)
            let body = trimmed(full, to: limit)
            guard !body.isEmpty else { return }
            let existing = context.handles.first { $0.value == entry.id }?.key
            let handle = existing ?? "E\(nextHandle)"
            let rendered = block(handle: handle, date: entry.date, title: entry.title, text: body, creative: entry.isCreative, note: entry.isNote)
            // A block that doesn't fit is skipped whole; a smaller one later can still go in,
            // and the handle it would have taken stays free.
            guard append(Block(text: rendered, entryID: entry.id)) else { return }
            if existing == nil { nextHandle += 1 }
            usedEntries.insert(entry.id)
            context.handles[handle] = entry.id
            context.entryIDs.append(entry.id)
            if isOwnText, body == full { context.wholeEntryIDs.insert(entry.id) }
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
