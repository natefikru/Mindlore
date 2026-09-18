import Foundation

// A page on the navigation stack. `follow` shows where a merged entity went, which is what the
// user was looking at; a row listing a merged entity opts out so it shows that entity itself.
nonisolated struct EntityRoute: Hashable, Sendable {
    let id: UUID
    var follow = true
}

// One mention in one entry, by what it says rather than by link id: regenerating insights
// replaces links, and a sheet holding an old id would act on nothing.
nonisolated struct MentionRef: Hashable, Identifiable, Sendable {
    var id: Self { self }
    let entryID: UUID
    let surface: String
    let kind: EntityKind
}

// What an entity page shows, decided from plain values so it can be tested without a view.
nonisolated enum EntityPagePresentation {
    enum Resolution: Equatable {
        case show(UUID)
        case gone
    }

    // `mergedIntoID` is always one hop from a live root, so one step is enough.
    static func resolve(_ route: EntityRoute, exists: Bool, mergedIntoID: UUID?) -> Resolution {
        guard exists else { return .gone }
        if route.follow, let winner = mergedIntoID { return .show(winner) }
        return .show(route.id)
    }

    // A fresh, single-mention, never-touched name is worth double-checking: dictation is the
    // likeliest source of a wrong spelling, and nobody has confirmed this one is right yet.
    // Restricted to the kinds bio auto-drafting already limits itself to (5a): tags rarely
    // appear word for word, so a misspelling there isn't the scenario this is for.
    static func showsSpellingPrompt(confirmedByUser: Bool, linkCount: Int, kind: EntityKind) -> Bool {
        !confirmedByUser && linkCount <= 1 && EntityBioDrafter.automaticKinds.contains(kind)
    }

    // After a merge made from a page, the page's route names the winner itself, so undoing
    // that merge later doesn't flip the page back to the loser. Only the top route that shows
    // the loser is replaced.
    static func replacing(_ loserID: UUID, with winnerID: UUID, in path: [EntityRoute]) -> [EntityRoute] {
        guard let index = path.lastIndex(where: { $0.id == loserID }) else { return path }
        var path = path
        path[index] = EntityRoute(id: winnerID)
        return path
    }

    // MARK: - Header

    static func mentionSummary(count: Int) -> String {
        switch count {
        case 0: "Not mentioned in any entry"
        case 1: "Mentioned in 1 entry"
        default: "Mentioned in \(count) entries"
        }
    }

    static func dateRange(first: Date?, last: Date?) -> String? {
        guard let first, let last else { return nil }
        let firstText = first.formatted(date: .abbreviated, time: .omitted)
        let lastText = last.formatted(date: .abbreviated, time: .omitted)
        return firstText == lastText ? firstText : "\(firstText) to \(lastText)"
    }

    // MARK: - Entries

    struct EntryInput: Equatable {
        let entryID: UUID
        let date: Date
        let title: String
        let text: String
        let surfaces: [String]
        // The mention the resolver linked by guessing, which the row offers to correct.
        let guessed: MentionRef?
    }

    struct EntryRow: Equatable, Identifiable {
        let id: UUID
        let date: Date
        let heading: String
        // Where the entry names them, if it still does.
        let sentence: String?
        let guessed: MentionRef?
    }

    static let headingWords = 8

    static func entryRows(_ inputs: [EntryInput]) -> [EntryRow] {
        inputs.sorted { $0.date > $1.date }.map { input in
            EntryRow(
                id: input.entryID,
                date: input.date,
                heading: heading(title: input.title, text: input.text),
                sentence: BioExcerpts.sentences(in: input.text, naming: input.surfaces).first,
                guessed: input.guessed
            )
        }
    }

    static func heading(title: String, text: String) -> String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        guard !words.isEmpty else { return "Untitled entry" }
        let opening = words.prefix(headingWords).joined(separator: " ")
        return words.count > headingWords ? opening + "…" : opening
    }

    // MARK: - Bio

    enum BioState: Equatable {
        case userWritten(String)
        case drafted(String, disclosure: String, canRedraft: Bool)
        case drafting
        case failed(String, canRetry: Bool)
        // The model or the entries had too little to say.
        case notEnough(canDraft: Bool)
        case empty(canDraft: Bool)
    }

    struct BioInput: Equatable {
        var bio: String?
        var wasGenerated = false
        var editedByUser = false
        var draftedAt: Date?
        var sourceEntries = 0
        var modelUsed: String?
        var drafting = false
        var failure: AIJobFailure?
        var withoutExcerpts = false
        var textUsable = false
    }

    static func bioState(_ input: BioInput) -> BioState {
        if input.drafting { return .drafting }
        if let bio = input.bio {
            guard input.wasGenerated, !input.editedByUser else { return .userWritten(bio) }
            return .drafted(bio, disclosure: disclosure(entries: input.sourceEntries, model: input.modelUsed), canRedraft: input.textUsable)
        }
        if let failure = input.failure {
            return .failed(BioDraftPresentation.message(for: failure), canRetry: input.textUsable)
        }
        let triedAndFoundLittle = input.draftedAt != nil || input.withoutExcerpts
        if triedAndFoundLittle && !input.editedByUser {
            return .notEnough(canDraft: input.textUsable)
        }
        return .empty(canDraft: input.textUsable)
    }

    static func disclosure(entries: Int, model: String?) -> String {
        let sent = entries == 1 ? "1 entry sent to OpenAI" : "\(entries) entries sent to OpenAI"
        let model = model?.trimmingCharacters(in: .whitespaces) ?? ""
        return (["Drafted by AI", sent] + (model.isEmpty ? [] : [model])).joined(separator: " · ")
    }

    // MARK: - Mentioned with

    struct CoOccurrenceRow: Equatable, Identifiable {
        let id: UUID
        let name: String
        let kind: EntityKind
    }

    // GraphServices.mentionedWith already orders by weight and applies the limit; this only
    // drops the weight, which is ordering, not something the page shows as a number.
    static func coOccurrenceRows(_ inputs: [GraphServices.CoOccurrence]) -> [CoOccurrenceRow] {
        inputs.map { CoOccurrenceRow(id: $0.id, name: $0.name, kind: $0.kind) }
    }

    // MARK: - Merged in

    struct MergedInput: Equatable {
        let id: UUID
        let name: String
        let mergedIntoID: UUID?
        let mergedAt: Date?
    }

    static func mergedIn(_ inputs: [MergedInput], into id: UUID) -> [MergedInput] {
        inputs.filter { $0.mergedIntoID == id }
            .sorted { ($0.mergedAt ?? .distantPast) > ($1.mergedAt ?? .distantPast) }
    }
}

// Wording for a bio that could not be drafted. The insights and title wording talks about
// entries and titles, which would be wrong here.
nonisolated enum BioDraftPresentation {
    static func message(for failure: AIJobFailure) -> String {
        if failure.raw == "settings.aiOff" { return "Turn on AI in Settings to draft a description." }
        switch failure.aiError {
        case .missingKey, .invalidKey, .permissionDenied:
            return "Add a working OpenAI key in AI settings to draft a description."
        case .offline:
            return "You're offline. Try again when you're connected."
        case .rateLimited:
            return "OpenAI is busy right now. Try again in a moment."
        case .quotaExceeded:
            return "Your OpenAI account is out of credit."
        default:
            return "Couldn't draft a description. Try again."
        }
    }
}

nonisolated extension EntityPagePresentation {
    // MARK: - Loose ends

    struct LooseEndItem: Equatable, Identifiable {
        let id: UUID
        let entityIDs: [UUID]
        let isOpen: Bool
        let lastMentionedAt: Date
        let statusChangedAt: Date?
    }

    // The loose ends about one entity, through merges: open ones by latest mention, then the
    // rest (settled, faded, let go) by when that happened.
    static func looseEnds(_ items: [LooseEndItem], about entityID: UUID, root: (UUID) -> UUID) -> (open: [UUID], earlier: [UUID]) {
        let about = items.filter { $0.entityIDs.contains { root($0) == entityID } }
        let open = about.filter(\.isOpen).sorted { $0.lastMentionedAt > $1.lastMentionedAt }
        let earlier = about.filter { !$0.isOpen }.sorted {
            ($0.statusChangedAt ?? $0.lastMentionedAt) > ($1.statusChangedAt ?? $1.lastMentionedAt)
        }
        return (open.map(\.id), earlier.map(\.id))
    }
}
