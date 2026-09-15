import Foundation

// Which insights to ask for, read from settings when a request is built.
nonisolated struct InsightSections: Equatable, Sendable {
    var summary = true
    var moods = true
    var themes = true
    var tags = true
    var mentions = true
    var openThreads = true
    var cleanedText = true
    var suggestEntryDates = true
    var customPrompts: [CustomInsightPrompt] = []

    var isEmpty: Bool {
        !summary && !moods && !themes && !tags && !mentions && !openThreads && !cleanedText && customPrompts.allSatisfy { !$0.enabled }
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
}

nonisolated struct InsightsResult: Equatable, Sendable {
    var summary: String?
    var primaryMood: Mood?
    var secondaryMoods: [Mood] = []
    var themes: [String] = []
    var tags: [String] = []
    var mentions: [Mention] = []
    var openThreads: [String] = []
    var cleanedText: String?
    var writtenDate: Date?
    var custom: [CustomInsightResult] = []

    var sectionsReturned: Int {
        [summary != nil, primaryMood != nil, !themes.isEmpty, !tags.isEmpty, !mentions.isEmpty, !openThreads.isEmpty, cleanedText != nil].filter { $0 }.count + custom.count
    }
}

// Builds one structured request per entry with a field for each enabled section. Every field may be
// empty, so the model reports nothing rather than inventing content.
nonisolated enum InsightsPromptBuilder {
    static let maxCleanedTextCharacters = 12_000
    static let maxExistingTags = 50
    static let maxThemes = 4
    static let maxTags = 8
    static let maxSecondaryMoods = 2

    static func plan(text: String, source: EntrySource, sections: InsightSections, existingTags: [String], model: String) -> InsightsRequestPlan {
        var properties: [JSONSchema.Property] = []
        var guidance: [String] = []

        if sections.summary {
            properties.append(.init("summary", .string(description: "One or two sentences on what the entry is actually about. Null if there is nothing to summarize.", nullable: true)))
        }
        if sections.moods {
            let moods = Mood.allCases.map(\.rawValue)
            properties.append(.init("primaryMood", .enumeration(moods, description: "The strongest mood the writer expresses. Null if the entry carries no emotional content.", nullable: true)))
            properties.append(.init("secondaryMoods", .array(.enumeration(moods), description: "Up to \(maxSecondaryMoods) other moods clearly present. Empty if none.")))
            let vocabulary = MoodCategory.allCases.map { category in
                "\(category.name): " + Mood.allCases.filter { $0.category == category }.map { "\($0.rawValue) (\($0.meaning))" }.joined(separator: ", ")
            }.joined(separator: "\n")
            guidance.append("Moods come only from this list. Leave moods empty rather than guess.\n\(vocabulary)")
        }
        if sections.themes {
            properties.append(.init("themes", .array(.string(), description: "Two to four short phrases naming what the entry is about. Empty if none.")))
        }
        if sections.tags {
            properties.append(.init("tags", .array(.string(), description: "Up to \(maxTags) short lowercase labels for grouping entries, like work or family. Empty if none.")))
            let tags = Array(existingTags.prefix(maxExistingTags))
            if !tags.isEmpty {
                guidance.append("Tags already used in this journal; reuse one when it fits instead of inventing a near-duplicate: \(tags.joined(separator: ", ")).")
            }
        }
        if sections.mentions {
            properties.append(.init("mentions", .array(.object([
                .init("name", .string(description: "The name as written.")),
                .init("kind", .enumeration(MentionKind.allCases.map(\.rawValue))),
            ]), description: "People, places, organizations, projects, events, and other named things in the entry. Empty if none.")))
        }
        if sections.openThreads {
            properties.append(.init("openThreads", .array(.string(), description: "Unresolved things the writer may want to come back to. Empty if none.")))
        }

        var skippedReason: String?
        let asksForCleanedText = sections.cleanedText && source == .voice && text.count <= maxCleanedTextCharacters
        if sections.cleanedText && source == .voice && !asksForCleanedText {
            skippedReason = "tooLong"
        }
        if asksForCleanedText {
            properties.append(.init("cleanedText", .string(description: "The entry with punctuation, capitalization, paragraph breaks, and obvious speech-to-text mistakes fixed. Keep the writer's words, order, and meaning; do not summarize, shorten, or add anything. Null if it needs no changes.", nullable: true)))
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
        and do not use diagnostic language. Do not restate the entry back. Use the writer's language. \
        Leave any field empty when the entry gives nothing for it.
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
        return InsightsRequestPlan(request: request, customKeys: customKeys, customKeyOrder: customKeyOrder, cleanedTextSkippedReason: skippedReason, asksForCleanedText: asksForCleanedText, asksForWrittenDate: asksForWrittenDate)
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
        result.themes = Array(unique(strings("themes")).prefix(maxThemes))
        result.tags = Array(unique(strings("tags").map { $0.lowercased() }).prefix(maxTags))
        result.openThreads = unique(strings("openThreads"))

        var mentions: [Mention] = []
        for item in (json["mentions"] as? [[String: Any]]) ?? [] {
            guard let name = (item["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                  let kind = (item["kind"] as? String).flatMap(MentionKind.init(rawValue:)) else { continue }
            let mention = Mention(name: name, kindRaw: kind.rawValue)
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
