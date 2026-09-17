import Foundation

// Which insights to ask for, read from settings when a request is built.
nonisolated struct InsightSections: Equatable, Sendable {
    var summary = true
    var moods = true
    var lifeAreas = true
    var tags = true
    var mentions = true
    var openThreads = true
    var cleanedText = true
    var suggestEntryDates = true
    var customPrompts: [CustomInsightPrompt] = []

    var isEmpty: Bool {
        !summary && !moods && !lifeAreas && !tags && !mentions && !openThreads && !cleanedText && customPrompts.allSatisfy { !$0.enabled }
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
    // Exactly what went into the prompt after section toggles, cleaning, and caps, so the
    // disclosure screen can say what was sent rather than what the journal holds today.
    var vocabularySent: InsightsPromptBuilder.JournalVocabulary = .empty
}

nonisolated struct InsightsResult: Equatable, Sendable {
    var summary: String?
    var primaryMood: Mood?
    var secondaryMoods: [Mood] = []
    var areas: [LifeArea] = []
    var tags: [String] = []
    var mentions: [Mention] = []
    var openThreads: [String] = []
    var cleanedText: String?
    var writtenDate: Date?
    var custom: [CustomInsightResult] = []

    var sectionsReturned: Int {
        [summary != nil, primaryMood != nil, !areas.isEmpty, !tags.isEmpty, !mentions.isEmpty, !openThreads.isEmpty, cleanedText != nil].filter { $0 }.count + custom.count
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

    // Longer than any real name; anything past it is not a name worth steering towards.
    static let maxVocabularyItemCharacters = 60

    // What this journal already calls things. Sent so the model reuses the user's own words
    // instead of inventing a near-duplicate of a tag or person they already have.
    struct JournalVocabulary: Equatable, Sendable {
        var tags: [String] = []
        var named: [KnownEntity] = []

        static let empty = JournalVocabulary()
    }

    // A name and, when it is settled, what it is. An `other` nobody has pinned down goes
    // without a kind, so the model is free to say what the entry makes it.
    struct KnownEntity: Equatable, Sendable {
        let name: String
        let kind: MentionKind?
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

    static func plan(text fullText: String, source: EntrySource, sections: InsightSections, vocabulary: JournalVocabulary, model: String) -> InsightsRequestPlan {
        let text = String(fullText.prefix(maxInputCharacters))
        var properties: [JSONSchema.Property] = []
        var guidance: [String] = []
        var sent = JournalVocabulary.empty

        if sections.summary {
            properties.append(.init("summary", .string(description: "One or two sentences on what the entry is about, however short the entry is. Null only when the entry has no content at all.", nullable: true)))
        }
        if sections.moods {
            let moods = Mood.allCases.map(\.rawValue)
            // Always answered: every entry gets a mood, and neutral covers the ones that carry none.
            properties.append(.init("primaryMood", .enumeration(moods, description: "The strongest mood the writer expresses, including a quiet one. Use neutral when the entry carries no clear feeling, such as a list or a note to self.")))
            properties.append(.init("secondaryMoods", .array(.enumeration(moods), description: "Up to \(maxSecondaryMoods) other moods also present. Empty if the entry carries only one mood or none.")))
            let vocabulary = MoodCategory.allCases.map { category in
                "\(category.name): " + Mood.allCases.filter { $0.category == category }.map { "\($0.rawValue) (\($0.meaning))" }.joined(separator: ", ")
            }.joined(separator: "\n")
            guidance.append("Moods come only from this list. Leave moods empty rather than guess.\n\(vocabulary)")
        }
        if sections.lifeAreas {
            properties.append(.init("lifeAreas", .array(.enumeration(LifeArea.allCases.map(\.rawValue)), description: "The one or two areas of life this entry is about. Never empty for an entry with content.")))
            let areas = LifeArea.allCases.map { "- \($0.rawValue): \($0.meaning)" }.joined(separator: "\n")
            guidance.append("""
            Life areas come only from this list. Pick the one area the entry is mostly about; add a \
            second only when the entry is clearly about both. Pick mind only when the entry is about \
            the writer's inner life itself, not just because it is written reflectively.
            """ + "\n" + areas)
        }
        if sections.tags {
            properties.append(.init("tags", .array(.string(), description: "One to \(maxTags) short lowercase labels for grouping entries with others, like running or renovation. More specific than life areas; never repeat a life area as a tag.")))
            sent.tags = listed(vocabulary.tags, cap: maxExistingTags)
            if !sent.tags.isEmpty {
                guidance.append("Tags already used in this journal, one per line. Reuse one when it fits instead of inventing a near-duplicate.\n" + sent.tags.map { "- \($0)" }.joined(separator: "\n"))
            }
        }
        if sections.mentions {
            properties.append(.init("mentions", .array(.object([
                .init("name", .string(description: "The name as written.")),
                .init("kind", .enumeration(MentionKind.allCases.map(\.rawValue))),
            ]), description: "People, places, organizations, projects, events, and other named things in the entry. Empty if none.")))
            // Names stay as written: "sarah" is not rewritten to "Sarah Kim", because deciding
            // which Sarah is the graph's job, and the user's corrections are keyed on what the
            // entry actually says. The list only fixes spelling and settles kinds.
            var seen: Set<String> = []
            sent.named = vocabulary.named.compactMap { known in
                guard let name = promptSafe(known.name), seen.insert(name.lowercased()).inserted else { return nil }
                return KnownEntity(name: name, kind: known.kind)
            }.prefix(maxKnownEntities).map { $0 }
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
        if sections.openThreads {
            properties.append(.init("openThreads", .array(.string(), description: "Unresolved things the writer may want to come back to. Empty if none.")))
        }

        // Speech-to-text and handwriting both produce punctuation worth fixing; typed text is the
        // user's own keystrokes and is never rewritten.
        var skippedReason: String?
        let canCleanUp = sections.cleanedText && (source == .voice || source == .photo)
        let asksForCleanedText = canCleanUp && text.count <= maxCleanedTextCharacters
        if canCleanUp && !asksForCleanedText {
            skippedReason = "tooLong"
        }
        if asksForCleanedText {
            properties.append(.init("cleanedText", .string(description: "The entry with punctuation, capitalization, paragraph breaks, and obvious transcription mistakes fixed. Keep the writer's words, order, and meaning; do not summarize, shorten, or add anything. Null if it needs no changes.", nullable: true)))
        }

        let asksForWrittenDate = sections.suggestEntryDates && source == .typed
        if asksForWrittenDate {
            properties.append(.init("writtenDate", .string(description: "The date this entry itself was written on, as yyyy-MM-dd, only if the text states it with year, month, and day. Ignore other dates mentioned. Null otherwise.", nullable: true)))
        }

        var customKeys: [String: CustomInsightPrompt] = [:]
        var customKeyOrder: [String] = []
        for prompt in sections.customPrompts where prompt.enabled {
            let key = customKey(for: prompt.id, taken: Set(customKeys.keys))
            customKeys[key] = prompt
            customKeyOrder.append(key)
            properties.append(.init(key, .string(description: "\(prompt.name): \(prompt.instructions) Null if the entry gives nothing to say.", nullable: true)))
        }

        var system = """
        You organize a personal journal entry for the person who wrote it. Be direct and concise. \
        Observe and organize only: do not give advice, reassurance, encouragement, or therapy-style reflection, \
        and do not use diagnostic language. Do not restate the entry back. Use the writer's language.

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
            maxOutputTokens: min(16_000, 3_000 + (asksForCleanedText ? text.count / 2 : 0))
        )
        return InsightsRequestPlan(request: request, customKeys: customKeys, customKeyOrder: customKeyOrder, cleanedTextSkippedReason: skippedReason, asksForCleanedText: asksForCleanedText, asksForWrittenDate: asksForWrittenDate, vocabularySent: sent)
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
        result.tags = Array(unique(strings("tags").map { $0.lowercased() }).prefix(maxTags))
        result.openThreads = unique(strings("openThreads"))

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

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.lowercased()).inserted }
    }
}
