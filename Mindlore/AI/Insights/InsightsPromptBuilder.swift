import Foundation

// Which insights to ask for, read from settings when a request is built.
nonisolated struct InsightSections: Equatable, Sendable {
    var summary = true
    var moods = true
    var lifeAreas = true
    var tags = true
    var mentions = true
    var looseEnds = true
    var cleanedText = true
    var suggestEntryDates = true
    var customPrompts: [CustomInsightPrompt] = []

    var isEmpty: Bool {
        !summary && !moods && !lifeAreas && !tags && !mentions && !looseEnds && !cleanedText && customPrompts.allSatisfy { !$0.enabled }
    }
}

// Everything about one insights request that is needed to read its answer.
nonisolated struct InsightsRequestPlan: Sendable {
    let request: TextRequest
    // Schema key for each enabled custom prompt, so results land on the right card even if prompts are
    // reordered or deleted while the request is out.
    let customKeys: [String: CustomInsightPrompt]
    // Keys in the user's prompt order, for showing cards in that order.
    let customKeyOrder: [String]
    let cleanedTextSkippedReason: String?
    let asksForCleanedText: Bool
    let asksForWrittenDate: Bool
    var asksForLifeAreas = false
    var asksForSections = false
    // Exactly what went into the prompt after section toggles, cleaning, and caps, so the
    // disclosure screen can say what was sent rather than what the journal holds today.
    var vocabularySent: InsightsPromptBuilder.JournalVocabulary = .empty
    // Short handles stand in for loose-end ids in the request, so no id is ever sent.
    var looseEndHandles: [String: UUID] = [:]
    // This entry's own earlier loose ends: the model may say a new one is the same, never that
    // the entry settled its own.
    var ownLooseEndIDs: Set<UUID> = []

    // Nothing was asked for, so there is nothing to send: a provider rejects an empty schema.
    // Read off the built request rather than off `InsightSections`, because which sections reach
    // the schema depends on the entry. `cleanedText` is only offered for voice and photo, and only
    // under the length cap; `writtenDate` only for typed. So the same toggles give a real schema
    // for one entry and an empty one for the next, and no settings-level predicate can see that.
    var asksForNothing: Bool {
        guard case .object(let properties, _, _) = request.schema else { return true }
        return properties.isEmpty
    }
}

// What one insights run says about loose ends, with handles already turned back into ids.
nonisolated struct LooseEndResult: Equatable, Sendable {
    struct New: Equatable, Sendable {
        var text: String
        var about: [String] = []
        var due: Date?
    }

    var new: [New] = []
    var mentioned: [UUID] = []
    var resolved: [UUID] = []

    var isEmpty: Bool { new.isEmpty && mentioned.isEmpty && resolved.isEmpty }
}

nonisolated struct InsightsResult: Equatable, Sendable {
    var summary: String?
    var primaryMood: Mood?
    var secondaryMoods: [Mood] = []
    var areas: [LifeArea] = []
    var tags: [String] = []
    var mentions: [Mention] = []
    var looseEnds = LooseEndResult()
    var cleanedText: String?
    var writtenDate: Date?
    var custom: [CustomInsightResult] = []
    var kind: EntryKind = .journal
    var sections: [EntrySection] = []

    var creative: Bool {
        get { kind == .creative }
        set { kind = newValue ? .creative : .journal }
    }

    var sectionsReturned: Int {
        [summary != nil, primaryMood != nil, !areas.isEmpty, !tags.isEmpty, !mentions.isEmpty, !looseEnds.isEmpty, cleanedText != nil, !sections.isEmpty].filter { $0 }.count + custom.count
    }

    // Drops what an entry of this kind never keeps: a lyric's names never reach the map, and a
    // list carries no mood. Applied before anything is written.
    mutating func restrict(to kind: EntryKind) {
        if !kind.keepsMoods {
            primaryMood = nil
            secondaryMoods = []
        }
        if !kind.keepsAreas { areas = [] }
        if !kind.keepsMentions { mentions = [] }
        if !kind.keepsLooseEnds { looseEnds = LooseEndResult() }
        if !kind.keepsSections { sections = [] }
    }
}

// Builds one structured request per entry with a field for each enabled section. Every field may be
// empty, so the model reports nothing rather than inventing content.
nonisolated enum InsightsPromptBuilder {
    // A pasted book chapter shouldn't become one enormous paid request.
    static let maxInputCharacters = 40_000
    static let maxCleanedTextCharacters = 12_000
    static let maxExistingTags = 50
    static let maxKnownEntities = 50
    static let maxTags = 8
    static let maxSecondaryMoods = 2
    static let maxNewLooseEnds = 2
    static let maxKnownLooseEnds = 15
    static let maxLooseEndCharacters = 200
    static let maxSections = 6
    static let maxSectionTopicCharacters = 60
    static let maxSectionSummaryCharacters = 240
    static let maxSectionTags = 5
    static let maxSectionNames = 8

    static let creativeRule = """
    What this entry is. creative: the entry is itself a poem, song lyrics, or a story, which shows \
    as short lines broken like verse, rhyme, a repeated refrain, or characters in a scene, with no \
    account of the author's own day. note: the entry is kept for use rather than telling what \
    happened: a list, a plan, a recipe, a draft message, a reference, notes taken from a meeting, a \
    book, or a lecture, with no account of the author's own day or feelings. life: everything \
    else, the author telling about their own day, plans, people, or feelings, including notes about \
    a song they are working on or a dream they had. When unsure between note and life, say life.
    """

    // Sections are asked for whenever the request carries the fields they refine. The small model
    // has no room for them.
    static let sectionsRule = """
    The entry divided by what it talks about, in the order written, only when it clearly moves \
    between two or more different things (a morning at work, then a call with a sister, then a plan \
    for the weekend). Each part names its topic in a few words, quotes the first four to six words \
    of the part exactly as the entry writes them, says in one sentence what that part is about, and \
    carries the life areas, tags, and names from the entry that belong to that part. An entry about \
    one thing has no parts, and an empty list is the normal answer.
    """

    // Longer than any real name; anything past it is not a name worth steering towards.
    static let maxVocabularyItemCharacters = 60

    // How much one request may carry. The cloud budget is what the provider comfortably takes. The
    // on-device model has about 4,096 tokens for instructions, schema, entry, and answer together,
    // so it reads the first few thousand characters of an entry, sees a short vocabulary, and skips
    // the two sections whose answers are as long as the entry (cleaned text) or unbounded (custom
    // prompts). The mood list goes without its glosses, since guided generation already keeps the
    // answer to the allowed values.
    nonisolated struct Budget: Sendable, Equatable {
        var inputCharacters: Int
        var existingTags: Int
        var knownEntities: Int
        var knownLooseEnds: Int
        var cleanedText: Bool
        var customPrompts: Bool
        var moodMeanings: Bool
        // Worked examples in the guidance. The small model copies them into its answer: shown
        // "waiting to hear back from the clinic", it filed that as a loose end of an entry about coffee.
        var examples: Bool
        // "The date the entry states it was written" came back as the entry's own date every time.
        var writtenDate: Bool
        // The entry divided by topic. As long as the entry's own tags and names again, so only
        // the cloud model has room for it.
        var sections: Bool
        var maxOutputTokens: Int?

        static let cloud = Budget(
            inputCharacters: maxInputCharacters, existingTags: maxExistingTags, knownEntities: maxKnownEntities,
            knownLooseEnds: maxKnownLooseEnds, cleanedText: true, customPrompts: true, moodMeanings: true, examples: true, writtenDate: true, sections: true, maxOutputTokens: nil
        )
        static let onDevice = Budget(
            inputCharacters: 4_000, existingTags: 15, knownEntities: 15,
            knownLooseEnds: 5, cleanedText: false, customPrompts: false, moodMeanings: false, examples: false, writtenDate: false, sections: false, maxOutputTokens: 700
        )
    }

    // What this journal already calls things. Sent so the model reuses the user's own words
    // instead of inventing a near-duplicate of a tag or person they already have.
    struct JournalVocabulary: Equatable, Sendable {
        var tags: [String] = []
        var named: [KnownEntity] = []
        var looseEnds: [KnownLooseEnd] = []

        static let empty = JournalVocabulary()
    }

    // A name and, when it is settled, what it is. An `other` nobody has pinned down goes
    // without a kind, so the model is free to say what the entry makes it.
    struct KnownEntity: Equatable, Sendable {
        let name: String
        let kind: MentionKind?
    }

    // An open loose end from another entry, or one of this entry's own from an earlier run.
    struct KnownLooseEnd: Equatable, Sendable {
        let id: UUID
        let text: String
        let own: Bool
    }

    // One line, trimmed, capped. Names can be typed by the user, so a newline or a stray
    // comma must not be able to reshape the prompt around it.
    static func promptSafe(_ value: String) -> String? {
        let collapsed = value.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(maxVocabularyItemCharacters))
    }

    private static func listed(_ items: [String], cap: Int) -> [String] {
        var seen: Set<String> = []
        return items.compactMap(promptSafe).filter { seen.insert($0.lowercased()).inserted }.prefix(cap).map { $0 }
    }

    static func plan(text fullText: String, source: EntrySource, sections: InsightSections, vocabulary: JournalVocabulary, model: String, entryDate: Date? = nil, voice: PromptVoice = .default, calendar: Calendar = .current, budget: Budget = .cloud) -> InsightsRequestPlan {
        let text = String(fullText.prefix(budget.inputCharacters))
        var properties: [JSONSchema.Property] = []
        var guidance: [String] = []
        var sent = JournalVocabulary.empty
        var handles: [String: UUID] = [:]
        var ownIDs: Set<UUID> = []

        // First, so guided generation decides it before it fills the fields it changes. Strict on
        // purpose: a real entry wrongly filed as creative quietly loses its names and threads. A
        // choice between two named kinds, not a boolean: told "true only when… false when…", the
        // on-device model called "worked on the Memphis song tonight" creative, the very example
        // the rule gave for false.
        if sections.lifeAreas || sections.mentions || sections.looseEnds {
            properties.append(.init("entryKind", .enumeration(EntryKind.allCases.map(\.promptValue), description: Self.creativeRule)))
        }
        if sections.summary {
            // The small model answered "A personal journal entry." to the cloud wording, so it is told
            // what a summary is made of rather than what it is for.
            let summary = budget.examples
                ? "One or two sentences on what the entry is about, however short the entry is. Null only when the entry has no content at all."
                : "One short sentence, in your own words and far shorter than the entry, saying what happened and naming who was involved. Never copy the entry, and never a label like 'a journal entry'."
            properties.append(.init("summary", .string(description: summary, nullable: true)))
        }
        if sections.moods {
            let moods = Mood.allCases.map(\.rawValue)
            // Always answered: every entry gets a mood, and neutral covers the ones that carry none.
            properties.append(.init("primaryMood", .enumeration(moods, description: "The strongest mood the author expresses, including a quiet one. Use neutral when the entry carries no clear feeling, such as a list or a note to self.")))
            properties.append(.init("secondaryMoods", .array(.enumeration(moods), description: "Up to \(maxSecondaryMoods) other moods also present. Empty if the entry carries only one mood or none.")))
            let vocabulary = MoodCategory.allCases.map { category in
                "\(category.name): " + Mood.allCases.filter { $0.category == category }
                    .map { budget.moodMeanings ? "\($0.rawValue) (\($0.meaning))" : $0.rawValue }.joined(separator: ", ")
            }.joined(separator: "\n")
            guidance.append("Moods come only from this list. Leave moods empty rather than guess.\n\(vocabulary)")
        }
        if sections.lifeAreas {
            // Guided generation reads a field's own description as it writes the field, so the small
            // model gets the list right there; told it once in the instructions, it answered "mind"
            // for coffee with a friend and a job offer.
            let areasDescription = budget.examples
                ? "The one or two areas of life this entry is about. Never empty for an entry with content."
                : "The one or two areas this entry is mostly about: " + LifeArea.allCases.map { "\($0.rawValue) (\($0.meaning))" }.joined(separator: "; ") + "."
            properties.append(.init("lifeAreas", .array(.enumeration(LifeArea.allCases.map(\.rawValue)), description: areasDescription)))
            let areas = LifeArea.allCases.map { "- \($0.rawValue): \($0.meaning)" }.joined(separator: "\n")
            guidance.append("""
            Life areas come only from this list. Pick the one area the entry is mostly about; add a \
            second only when the entry is clearly about both. Pick mind only when the entry is about \
            the author's inner life itself, not just because it is written reflectively.
            """ + "\n" + areas)
        }
        if sections.tags {
            properties.append(.init("tags", .array(.string(), description: "One to \(maxTags) short lowercase labels for grouping entries with others, like running or renovation. More specific than life areas; never repeat a life area as a tag" + (budget.examples ? "." : ", and never a person's name."))))
            sent.tags = listed(vocabulary.tags, cap: budget.existingTags)
            if !sent.tags.isEmpty {
                guidance.append("Tags already used in this journal, one per line. Reuse one when it fits instead of inventing a near-duplicate.\n" + sent.tags.map { "- \($0)" }.joined(separator: "\n"))
            }
        }
        if sections.mentions {
            properties.append(.init("mentions", .array(.object([
                .init("name", .string(description: "The name as written.")),
                .init("kind", .enumeration(MentionKind.allCases.map(\.rawValue))),
            ]), description: budget.examples
                ? "People, places, organizations, projects, events, and other named things in the entry. Empty if none."
                : "Every person, place, organization, and project the entry names, each once. Empty if none.")))
            // Names stay as written: "sarah" is not rewritten to "Sarah Kim", because deciding
            // which Sarah is the graph's job, and the user's corrections are keyed on what the
            // entry actually says. The list only fixes spelling and settles kinds.
            var seen: Set<String> = []
            sent.named = vocabulary.named.compactMap { known in
                guard let name = promptSafe(known.name), seen.insert(name.lowercased()).inserted else { return nil }
                return KnownEntity(name: name, kind: known.kind)
            }.prefix(budget.knownEntities).map { $0 }
            if !sent.named.isEmpty {
                let lines = sent.named.map { known in known.kind.map { "- \(known.name) (\($0.rawValue))" } ?? "- \(known.name)" }
                guidance.append("""
                Names already in this journal, one per line, with their kind where it is known. \
                Write every name the way the entry writes it; do not lengthen or complete it. \
                If the entry misspells one of these, or a transcription garbled it, use the spelling listed here. \
                Include only names that actually appear in this entry. \
                Use the listed kind unless the entry clearly says otherwise.
                """ + "\n" + lines.joined(separator: "\n"))
            }
        }
        if sections.looseEnds {
            var seen: Set<UUID> = []
            sent.looseEnds = vocabulary.looseEnds.compactMap { known in
                guard seen.insert(known.id).inserted, let text = promptSafe(known.text) else { return nil }
                return KnownLooseEnd(id: known.id, text: String(text.prefix(maxLooseEndCharacters)), own: known.own)
            }.prefix(budget.knownLooseEnds).map { $0 }
            var lines: [String] = []
            for (index, known) in sent.looseEnds.enumerated() {
                let handle = "L\(index + 1)"
                handles[handle] = known.id
                if known.own { ownIDs.insert(known.id) }
                lines.append("- \(handle): \(known.text)" + (known.own ? " (written from this entry before; use only as sameAs)" : ""))
            }
            let handleList = Array(handles.keys).sorted { $0.count == $1.count ? $0 < $1 : $0.count < $1.count }
            properties.append(.init("looseEnds", .array(.object([
                .init("text", .string(description: "What is left open, in a few words, in the author's language.")),
                .init("about", .array(.string(), description: "Names from mentions this concerns. Empty if none.")),
                .init("due", .string(description: "Its date as yyyy-MM-dd, only if the entry gives one. Null otherwise.", nullable: true)),
                .init("sameAs", handleList.isEmpty
                      ? .string(description: "Always null.", nullable: true)
                      : .enumeration(handleList, description: "The handle of a known loose end this is, instead of writing it again. Null for a new one.", nullable: true)),
            ]), description: "Loose ends: concrete things a later entry could settle. Usually empty.")))
            if !handleList.isEmpty {
                properties.append(.init("resolved", .array(.enumeration(handleList), description: "Handles of known loose ends this entry clearly settles. Usually empty.")))
            }
            var guide = budget.examples ? """
            A loose end is a commitment: a plan to make, a task to do, a decision not yet made, or \
            something being waited on. It has to still be open when the entry ends, be worth keeping \
            for days or weeks, and be something a later entry could settle.

            Yes: call the landlord about the lease. Decide whether to take the Denver job. Waiting to \
            hear back from the clinic. Book flights before the wedding.

            No: a feeling or a mood. An intention to think about something more. Anything already done \
            by the end of the entry, such as grabbing coffee after this or finishing a page. Anything \
            that settles itself within the day.

            Most entries have none, and an empty list is the normal answer. Write at most \
            \(maxNewLooseEnds) new ones.
            """ : """
            A loose end is something this entry says the author still has to do, decide, or hear \
            back about. Only write one the entry states in its own words; never add one it doesn't. \
            Give a due date only when the entry names a day. Most entries have none. Write at most \
            \(maxNewLooseEnds).
            """
            if let entryDate {
                guide += " This entry was written on \(Self.day(entryDate, calendar: calendar)); read relative dates from that day."
            }
            if !lines.isEmpty {
                guide += """
                \n\nKnown loose ends, one per line with its handle. When the entry mentions one again, \
                give its handle as sameAs instead of writing a new one. Put a handle in resolved only \
                when this entry clearly settles it.
                """ + "\n" + lines.joined(separator: "\n")
            }
            guidance.append(guide)
        }

        // The entry divided by topic, so a long entry's tags and names come from every part of it
        // rather than whichever the model read first. Grouped with the fields it refines: asked for
        // only when at least one of tags, mentions, and areas is on, and never on device.
        let asksForSections = budget.sections && (sections.tags || sections.mentions || sections.lifeAreas)
        if asksForSections {
            var fields: [JSONSchema.Property] = [
                .init("topic", .string(description: "What this part is about, in two to six words.")),
                .init("startsWith", .string(description: "The first four to six words of this part, exactly as the entry writes them.")),
                .init("summary", .string(description: "One sentence on what this part says.", nullable: true)),
            ]
            if sections.lifeAreas {
                fields.append(.init("lifeAreas", .array(.enumeration(LifeArea.allCases.map(\.rawValue)), description: "The one or two life areas this part is about.")))
            }
            if sections.tags {
                fields.append(.init("tags", .array(.string(), description: "Short lowercase labels for this part, like the entry's tags.")))
            }
            if sections.mentions {
                fields.append(.init("names", .array(.string(), description: "Names from mentions that appear in this part.")))
            }
            properties.append(.init("sections", .array(.object(fields), description: "The entry's parts by topic, in order. Empty when the entry is about one thing.")))
            guidance.append(Self.sectionsRule)
        }

        // Speech-to-text and handwriting both produce punctuation worth fixing; typed text is the
        // user's own keystrokes and is never rewritten.
        var skippedReason: String?
        let canCleanUp = sections.cleanedText && (source == .voice || source == .photo)
        let asksForCleanedText = canCleanUp && budget.cleanedText && text.count <= maxCleanedTextCharacters
        if canCleanUp && !asksForCleanedText {
            skippedReason = budget.cleanedText ? "tooLong" : "onDevice"
        }
        if asksForCleanedText {
            properties.append(.init("cleanedText", .string(description: "The entry with punctuation, capitalization, paragraph breaks, and obvious transcription mistakes fixed. Keep the author's words, order, and meaning; do not summarize, shorten, or add anything. Null if it needs no changes.", nullable: true)))
        }

        // Typed entries and photographed pages state their own date often enough to ask; a
        // recording never does. The page transcriber already reads a date off the page itself;
        // asking here as well catches one it missed. Either only applies a date on its own while
        // the entry has no picked day; otherwise it is offered.
        let asksForWrittenDate = sections.suggestEntryDates && (source == .typed || source == .photo) && budget.writtenDate
        if asksForWrittenDate {
            properties.append(.init("writtenDate", .string(description: "The date this entry itself was written on, as yyyy-MM-dd, only if the text states it with year, month, and day" + (source == .photo ? ", usually at the top of the first page" : "") + ". Ignore other dates mentioned. Null otherwise.", nullable: true)))
        }

        var customKeys: [String: CustomInsightPrompt] = [:]
        var customKeyOrder: [String] = []
        for prompt in sections.customPrompts where prompt.enabled && budget.customPrompts {
            let key = customKey(for: prompt.id, taken: Set(customKeys.keys))
            customKeys[key] = prompt
            customKeyOrder.append(key)
            properties.append(.init(key, .string(description: "\(prompt.name): \(prompt.instructions) Null if the entry gives nothing to say.", nullable: true)))
        }

        var system = """
        You organize a personal journal entry for the person who wrote it. Be direct and concise. \
        Observe and organize only: do not give advice, reassurance, encouragement, or therapy-style reflection, \
        and do not use diagnostic language. Do not restate the entry back. Use the author's language.

        \(voice.instruction)

        Fill in every field the entry supports, however short it is: a one-line entry still has a summary, \
        usually a mood, a life area, and often a tag. Leave a field empty only when the entry genuinely \
        contains nothing for it, such as no named people for mentions.
        """
        if !guidance.isEmpty {
            system += "\n\n" + guidance.joined(separator: "\n\n")
        }

        let request = TextRequest(
            model: model,
            system: system,
            user: text,
            schema: .object(properties),
            schemaName: "journal_insights",
            maxOutputTokens: budget.maxOutputTokens ?? min(16_000, 3_000 + (asksForCleanedText ? text.count / 2 : 0))
        )
        return InsightsRequestPlan(request: request, customKeys: customKeys, customKeyOrder: customKeyOrder, cleanedTextSkippedReason: skippedReason, asksForCleanedText: asksForCleanedText, asksForWrittenDate: asksForWrittenDate, asksForLifeAreas: sections.lifeAreas, asksForSections: asksForSections, vocabularySent: sent, looseEndHandles: handles, ownLooseEndIDs: ownIDs)
    }

    static func day(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    // Derived from the prompt's id, so the key stays the same when prompts move or others are deleted.
    static func customKey(for id: UUID, taken: Set<String>) -> String {
        let hex = id.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        var length = 8
        var key = "custom_" + hex.prefix(length)
        while taken.contains(key), length < hex.count {
            length += 4
            key = "custom_" + hex.prefix(length)
        }
        return key
    }

    // Reads the model's JSON tolerantly: unknown moods and kinds are dropped, text is trimmed, lists are capped.
    // A name the model returns is cut back to what the entry actually says. Told to write names as
    // written, the real model still completes a dictated "sarah" to a known "Sarah Kim", which
    // would skip the graph's own first-name guess and sit beside a link the user corrected.
    //
    // If the whole name is in the entry, it stays. If only its first words are, the entry's own
    // spelling of those words is used. If none of it is, the model fixed a garbled name ("sara
    // kym" to "Sarah Kim"), and that is kept, which is what the journal's names are sent for;
    // `wasCorrected` tells the caller that happened, so it can look for what was actually written.
    static func grounded(_ name: String, in text: String) -> (surface: String, wasCorrected: Bool) {
        let words = name.split(separator: " ").map(String.init)
        for count in stride(from: words.count, through: 1, by: -1) {
            let phrase = words.prefix(count).joined(separator: " ")
            if let range = NameMatching.range(of: phrase, in: text) {
                return (String(text[range]), false)
            }
        }
        return (name, true)
    }

    static func parse(_ text: String, plan: InsightsRequestPlan, calendar: Calendar = .current) throws -> InsightsResult {
        guard let data = StructuredOutputParser.jsonObjectData(in: text),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.invalidResponse
        }

        func string(_ key: String) -> String? {
            guard let value = json[key] as? String else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        func strings(_ key: String) -> [String] {
            ((json[key] as? [Any]) ?? []).compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }

        var result = InsightsResult()
        result.kind = EntryKind.fromPromptValue(json["entryKind"] as? String)
        result.summary = string("summary")
        result.primaryMood = string("primaryMood").flatMap(Mood.init(rawValue:))
        var secondary: [Mood] = []
        for mood in strings("secondaryMoods").compactMap(Mood.init(rawValue:)) where mood != result.primaryMood && !secondary.contains(mood) {
            secondary.append(mood)
        }
        result.secondaryMoods = Array(secondary.prefix(maxSecondaryMoods))
        var areas: [LifeArea] = []
        for area in strings("lifeAreas").compactMap({ LifeArea(rawValue: $0.lowercased()) }) where !areas.contains(area) {
            areas.append(area)
        }
        result.areas = Array(areas.prefix(LifeArea.maxPerEntry))
        // A tag that is a life area's name duplicates the area; models write them anyway.
        let areaNames = plan.asksForLifeAreas ? Set(LifeArea.allCases.map(\.rawValue)) : []
        if plan.asksForSections {
            result.sections = parseSections(in: json, text: plan.request.user, areaNames: areaNames)
        }
        // The entry's own tags first, then what its parts added, so a long entry's later topics
        // still reach the list; the cap stays the entry's.
        let sectionTags = result.sections.flatMap(\.tags)
        result.tags = Array(unique((strings("tags") + sectionTags).map { $0.lowercased() }).filter { !areaNames.contains($0) }.prefix(maxTags))
        result.looseEnds = looseEnds(in: json, plan: plan, calendar: calendar)

        var mentions: [Mention] = []
        for item in (json["mentions"] as? [[String: Any]]) ?? [] {
            guard let written = (item["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !written.isEmpty,
                  let kind = (item["kind"] as? String).flatMap(MentionKind.init(rawValue:)) else { continue }
            let grounding = grounded(written, in: plan.request.user)
            let name = grounding.surface
            let writtenSurface = grounding.wasCorrected ? NameMatching.nearestWord(to: name, in: plan.request.user) : nil
            let mention = Mention(name: name, kindRaw: kind.rawValue, writtenSurface: writtenSurface)
            if !mentions.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame && $0.kindRaw == mention.kindRaw }) {
                mentions.append(mention)
            }
        }
        result.mentions = mentions

        if plan.asksForCleanedText {
            result.cleanedText = string("cleanedText")
        }
        if plan.asksForWrittenDate {
            result.writtenDate = string("writtenDate").flatMap { EntryDates.parseDay($0, calendar: calendar) }
        }
        result.custom = plan.customKeyOrder.compactMap { key in
            guard let prompt = plan.customKeys[key], let content = string(key) else { return nil }
            return CustomInsightResult(promptID: prompt.id, name: prompt.name, content: content)
        }
        return result
    }

    // Unknown handles are dropped, whole items with them: a made-up handle means the model
    // meant something it can't name, and a guess would duplicate or close the wrong thing.
    // A handle in resolved wins over the same handle in sameAs, and an entry never settles
    // its own loose ends.
    private static func looseEnds(in json: [String: Any], plan: InsightsRequestPlan, calendar: Calendar) -> LooseEndResult {
        var result = LooseEndResult()
        for handle in (json["resolved"] as? [Any] ?? []).compactMap({ $0 as? String }) {
            guard let id = plan.looseEndHandles[handle], !plan.ownLooseEndIDs.contains(id), !result.resolved.contains(id) else { continue }
            result.resolved.append(id)
        }
        var seenText: Set<String> = []
        for item in (json["looseEnds"] as? [[String: Any]]) ?? [] {
            if let handle = (item["sameAs"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !handle.isEmpty {
                guard let id = plan.looseEndHandles[handle] else { continue }
                if !result.resolved.contains(id), !result.mentioned.contains(id) { result.mentioned.append(id) }
                continue
            }
            guard let raw = (item["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
                  result.new.count < maxNewLooseEnds else { continue }
            let text = String(raw.prefix(maxLooseEndCharacters))
            guard seenText.insert(text.lowercased()).inserted else { continue }
            let about = unique(((item["about"] as? [Any]) ?? []).compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
            let due = (item["due"] as? String).flatMap { EntryDates.parseDay($0, calendar: calendar) }
            result.new.append(.init(text: text, about: about, due: due))
        }
        return result
    }

    // Parts by topic, read as tolerantly as the rest: a part with no topic is dropped, its opening
    // words are looked up in the entry (a part that can't be placed still counts, without an
    // offset), and every list is capped. Offsets are kept in order, so a part the model put out
    // of sequence loses its offset rather than pointing backwards.
    static func parseSections(in json: [String: Any], text: String, areaNames: Set<String>) -> [EntrySection] {
        var result: [EntrySection] = []
        var searchFrom = text.startIndex
        for item in (json["sections"] as? [[String: Any]]) ?? [] {
            guard result.count < maxSections,
                  let rawTopic = (item["topic"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !rawTopic.isEmpty else { continue }
            var section = EntrySection(topic: String(rawTopic.prefix(maxSectionTopicCharacters)))
            if let summary = (item["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
                section.summary = String(summary.prefix(maxSectionSummaryCharacters))
            }
            var areas: [String] = []
            for area in ((item["lifeAreas"] as? [Any]) ?? []).compactMap({ ($0 as? String)?.lowercased() })
            where LifeArea(rawValue: area) != nil && !areas.contains(area) {
                areas.append(area)
            }
            section.areasRaw = Array(areas.prefix(LifeArea.maxPerEntry))
            section.tags = Array(unique(((item["tags"] as? [Any]) ?? []).compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty && !areaNames.contains($0) }).prefix(maxSectionTags))
            section.names = Array(unique(((item["names"] as? [Any]) ?? []).compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }).prefix(maxSectionNames))
            if let opening = (item["startsWith"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !opening.isEmpty,
               let range = text.range(of: opening, options: [.caseInsensitive, .diacriticInsensitive], range: searchFrom..<text.endIndex) {
                section.offset = text.distance(from: text.startIndex, to: range.lowerBound)
                searchFrom = range.upperBound
            }
            result.append(section)
        }
        return result
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.lowercased()).inserted }
    }
}
