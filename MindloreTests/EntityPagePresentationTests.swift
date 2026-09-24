import Foundation
import SwiftData
import Testing
@testable import Mindlore

struct EntityPagePresentationTests {
    typealias P = EntityPagePresentation

    private let a = UUID()
    private let b = UUID()

    // MARK: - Routes

    @Test func aLiveEntityShowsItself() {
        #expect(P.resolve(EntityRoute(id: a), exists: true, mergedIntoID: nil) == .show(a))
    }

    @Test func aMergedEntityShowsItsWinnerUnlessTheRouteSaysNot() {
        #expect(P.resolve(EntityRoute(id: a), exists: true, mergedIntoID: b) == .show(b))
        #expect(P.resolve(EntityRoute(id: a, follow: false), exists: true, mergedIntoID: b) == .show(a))
    }

    @Test func aPrunedEntityIsGone() {
        #expect(P.resolve(EntityRoute(id: a), exists: false, mergedIntoID: nil) == .gone)
        #expect(P.resolve(EntityRoute(id: a, follow: false), exists: false, mergedIntoID: b) == .gone)
    }

    @Test func showsSpellingPromptOnlyForAFreshUnconfirmedMentionKind() {
        #expect(P.showsSpellingPrompt(confirmedByUser: false, linkCount: 1, kind: .person))
        #expect(P.showsSpellingPrompt(confirmedByUser: false, linkCount: 0, kind: .place))
        #expect(!P.showsSpellingPrompt(confirmedByUser: true, linkCount: 1, kind: .person), "confirmed already answered it")
        #expect(!P.showsSpellingPrompt(confirmedByUser: false, linkCount: 2, kind: .person), "a second mention is no longer a fresh guess")
        #expect(!P.showsSpellingPrompt(confirmedByUser: false, linkCount: 1, kind: .tag), "tags rarely appear word for word")
        #expect(!P.showsSpellingPrompt(confirmedByUser: false, linkCount: 1, kind: .tag))
    }

    @Test func aMergeFromAPageReplacesOnlyTheTopRouteForTheLoser() {
        let other = UUID()
        let path = [EntityRoute(id: a), EntityRoute(id: other), EntityRoute(id: a)]
        #expect(P.replacing(a, with: b, in: path) == [EntityRoute(id: a), EntityRoute(id: other), EntityRoute(id: b)])
        #expect(P.replacing(UUID(), with: b, in: path) == path)
    }

    // MARK: - Header

    @Test func countsReadNaturally() {
        #expect(P.mentionSummary(count: 0) == "Not mentioned in any entry")
        #expect(P.mentionSummary(count: 1) == "Mentioned in 1 entry")
        #expect(P.mentionSummary(count: 12) == "Mentioned in 12 entries")
    }

    @Test func oneDayIsOneDateAndTwoAreARange() {
        let first = Date(timeIntervalSince1970: 1_000_000)
        let last = Date(timeIntervalSince1970: 9_000_000)
        let firstText = first.formatted(date: .abbreviated, time: .omitted)
        #expect(P.dateRange(first: first, last: first) == firstText)
        #expect(P.dateRange(first: first, last: last) == "\(firstText) to \(last.formatted(date: .abbreviated, time: .omitted))")
        #expect(P.dateRange(first: nil, last: last) == nil)
    }

    // MARK: - Entries

    @Test func rowsAreNewestFirstWithTheSentenceThatNamesThem() {
        let old = UUID()
        let new = UUID()
        let guess = MentionRef(entryID: new, surface: "sarah", kind: .person)
        let rows = P.entryRows([
            .init(entryID: old, date: Date(timeIntervalSince1970: 1), title: "Walk", text: "Rain. Sarah came along.", surfaces: ["Sarah"], guessed: nil),
            .init(entryID: new, date: Date(timeIntervalSince1970: 2), title: "", text: "saw sarah at the market today and we talked for a while", surfaces: ["sarah"], guessed: guess),
        ])

        #expect(rows.map(\.id) == [new, old])
        #expect(rows[0].heading == "saw sarah at the market today and we…")
        #expect(rows[0].sentence == "saw sarah at the market today and we talked for a while")
        #expect(rows[0].guessed == guess)
        #expect(rows[1].heading == "Walk")
        #expect(rows[1].sentence == "Sarah came along.")
        #expect(rows[1].guessed == nil)
    }

    @Test func anEntryThatNoLongerNamesThemHasNoSentence() {
        let rows = P.entryRows([.init(entryID: a, date: .now, title: "", text: "", surfaces: ["Sarah"], guessed: nil)])
        #expect(rows[0].sentence == nil)
        #expect(rows[0].heading == "Untitled entry")
    }

    // MARK: - Bio

    @Test func bioStates() {
        typealias Input = P.BioInput
        let drafted = Date(timeIntervalSince1970: 5)
        let offline = AIJobFailure(.offline(.notConnectedToInternet))

        #expect(P.bioState(Input(textUsable: true)) == .empty(canDraft: true))
        #expect(P.bioState(Input()) == .empty(canDraft: false))
        #expect(P.bioState(Input(drafting: true)) == .drafting)
        #expect(P.bioState(Input(bio: "Mine.")) == .userWritten("Mine."))
        #expect(P.bioState(Input(bio: "Mine.", wasGenerated: true, editedByUser: true)) == .userWritten("Mine."))
        #expect(P.bioState(Input(bio: "A friend.", wasGenerated: true, draftedAt: drafted, sourceEntries: 3, modelUsed: "gpt-x", textUsable: true))
                == .drafted("A friend.", disclosure: "Drafted by AI · 3 entries sent to OpenAI · gpt-x", canRedraft: true))
        #expect(P.bioState(Input(bio: "A friend.", wasGenerated: true, sourceEntries: 1))
                == .drafted("A friend.", disclosure: "Drafted by AI · 1 entry sent to OpenAI", canRedraft: false))
        #expect(P.bioState(Input(wasGenerated: true, draftedAt: drafted, textUsable: true)) == .notEnough(canDraft: true))
        #expect(P.bioState(Input(withoutExcerpts: true)) == .notEnough(canDraft: false))
        #expect(P.bioState(Input(failure: offline, textUsable: true))
                == .failed("You're offline. Try again when you're connected.", canRetry: true))
        // Cleared by the user: nothing about the old draft shows, and Draft is on offer.
        #expect(P.bioState(Input(editedByUser: true, draftedAt: drafted, textUsable: true)) == .empty(canDraft: true))
    }

    @Test func failureWordingTalksAboutDescriptions() {
        typealias B = BioDraftPresentation
        #expect(B.message(for: AIJobFailure(raw: "settings.aiOff")) == "Turn on AI in Settings to draft a description.")
        #expect(B.message(for: AIJobFailure(.missingKey)) == "Add a working OpenAI key in AI settings to draft a description.")
        #expect(B.message(for: AIJobFailure(.invalidKey)) == "Add a working OpenAI key in AI settings to draft a description.")
        #expect(B.message(for: AIJobFailure(.rateLimited(retryAfter: nil))) == "OpenAI is busy right now. Try again in a moment.")
        #expect(B.message(for: AIJobFailure(.quotaExceeded)) == "Your OpenAI account is out of credit.")
        #expect(B.message(for: AIJobFailure(.invalidResponse)) == "Couldn't draft a description. Try again.")
    }

    // MARK: - Merged in

    @Test func mergedInListsOnlyThisEntitysLosersNewestFirst() {
        let winner = UUID()
        let early = P.MergedInput(id: UUID(), name: "Sarah K", mergedIntoID: winner, mergedAt: Date(timeIntervalSince1970: 1))
        let late = P.MergedInput(id: UUID(), name: "sarah", mergedIntoID: winner, mergedAt: Date(timeIntervalSince1970: 2))
        let elsewhere = P.MergedInput(id: UUID(), name: "Tom", mergedIntoID: UUID(), mergedAt: .now)
        let live = P.MergedInput(id: winner, name: "Sarah Kim", mergedIntoID: nil, mergedAt: nil)

        #expect(P.mergedIn([early, elsewhere, late, live], into: winner) == [late, early])
    }

    // MARK: - Mentioned with

    @Test func coOccurrenceRowsPreservesOrder() {
        let tom = GraphServices.CoOccurrence(id: a, name: "Tom", kind: .person, weight: 2, entries: 2)
        let ana = GraphServices.CoOccurrence(id: b, name: "Ana", kind: .person, weight: 1, entries: 1)

        #expect(P.coOccurrenceRows([tom, ana]) == [
            .init(id: a, name: "Tom", kind: .person, entries: 2),
            .init(id: b, name: "Ana", kind: .person, entries: 1),
        ])
    }

    @Test func coOccurrenceRowsIsEmptyForEmptyInput() {
        #expect(P.coOccurrenceRows([]).isEmpty)
    }
}

@MainActor
struct GraphServicesBioEditTests {
    let harness: BioHarness

    init() throws {
        harness = try BioHarness()
    }

    @Test func settingABioSavesItAsTheUsersAndMovesTheRevision() throws {
        let entry = try harness.entry("Sarah called.", mentions: [("Sarah", .person)])
        let sarah = try harness.entity("Sarah")
        let revision = harness.services.revision

        harness.services.setBio("  My sister. ", on: sarah.id, in: harness.context)

        #expect(sarah.bio == "My sister.")
        #expect(sarah.bioEditedByUser)
        #expect(sarah.confirmedByUser)
        #expect(!harness.context.hasChanges)
        #expect(harness.services.revision == revision + 1)
        #expect(entry.updatedAt == Date(timeIntervalSince1970: 42))
    }

    @Test func settingABioOnAGoneEntityDoesNothing() {
        harness.services.setBio("Anything", on: UUID(), in: harness.context)
        #expect(harness.services.revision == 0)
    }
}

struct EntityPageLooseEndTests {
    private typealias Item = EntityPagePresentation.LooseEndItem

    @Test func openFirstByMentionThenEarlierThroughAMerge() {
        let sarah = UUID(), sara = UUID(), tom = UUID()
        func at(_ t: TimeInterval) -> Date { Date(timeIntervalSince1970: t) }
        let old = Item(id: UUID(), entityIDs: [sarah], isOpen: true, lastMentionedAt: at(10), statusChangedAt: nil)
        let recent = Item(id: UUID(), entityIDs: [sara], isOpen: true, lastMentionedAt: at(50), statusChangedAt: nil)
        let settled = Item(id: UUID(), entityIDs: [sarah], isOpen: false, lastMentionedAt: at(5), statusChangedAt: at(60))
        let faded = Item(id: UUID(), entityIDs: [sara, tom], isOpen: false, lastMentionedAt: at(70), statusChangedAt: nil)
        let other = Item(id: UUID(), entityIDs: [tom], isOpen: true, lastMentionedAt: at(90), statusChangedAt: nil)

        let split = EntityPagePresentation.looseEnds([old, recent, settled, faded, other], about: sarah) { $0 == sara ? sarah : $0 }
        #expect(split.open == [recent.id, old.id])
        #expect(split.earlier == [faded.id, settled.id])
    }

    // MARK: - Presence, feeling, area

    private typealias P = EntityPagePresentation

    @Test func namesAndThemesSplitInOrder() {
        let rows: [P.CoOccurrenceRow] = [
            .init(id: UUID(), name: "dating", kind: .tag, entries: 43),
            .init(id: UUID(), name: "Mom", kind: .person, entries: 11),
            .init(id: UUID(), name: "texting", kind: .tag, entries: 9),
            .init(id: UUID(), name: "Café Olmo", kind: .place, entries: 7),
        ]
        let split = P.partners(rows)
        #expect(split.names.map(\.name) == ["Mom", "Café Olmo"])
        #expect(split.themes.map(\.name) == ["dating", "texting"])
    }

    @Test func presenceHasAMonthPerJournalMonthAndSaysItsBusiest() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func day(_ y: Int, _ m: Int, _ d: Int) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }
        let presence = try #require(P.presence(
            entryDates: [day(2025, 11, 2), day(2025, 11, 20), day(2025, 11, 28), day(2026, 1, 5), day(2026, 3, 1), day(2026, 5, 1)],
            journalStart: day(2025, 10, 10),
            now: day(2026, 3, 15),
            calendar: calendar
        ))
        #expect(presence.months == [0, 3, 0, 1, 0, 1], "October to March; May is in the future")
        #expect(presence.total == 5)
        #expect(P.presenceWords(presence, calendar: calendar) == "5 entries · Nov 2025 to Mar 2026 · busiest in November 2025")

        let oneMonth = try #require(P.presence(entryDates: [day(2026, 3, 1), day(2026, 3, 2)], journalStart: day(2026, 3, 1), now: day(2026, 3, 15), calendar: calendar))
        #expect(oneMonth.busiest == nil)
        #expect(P.presenceWords(oneMonth, calendar: calendar) == "2 entries · Mar 2026")
        #expect(P.presence(entryDates: [], journalStart: nil, now: day(2026, 3, 15), calendar: calendar) == nil)
    }

    @Test func feelingNeedsFiveMoodsAndReadsAsCounts() throws {
        let usual: [MoodCategory: Int] = [.calm: 40, .anxious: 10, .joyful: 30]
        #expect(P.feeling(moods: [.anxious, .anxious, .calm, nil, nil, nil], usual: usual) == nil, "three with a mood is not a pattern")

        let feeling = try #require(P.feeling(moods: [.anxious, .anxious, .anxious, .anxious, .calm, nil, .low], usual: usual))
        #expect(feeling.total == 6)
        #expect(feeling.rows.map(\.mood) == [.anxious, .calm, .low])
        #expect(P.feelingWords(feeling.rows[0], total: feeling.total, usualTotal: feeling.usualTotal) == "Anxious in 4 of 6 · usually 1 in 8")
        #expect(P.feelingWords(feeling.rows[2], total: feeling.total, usualTotal: feeling.usualTotal) == "Low in 1 of 6 · rarely otherwise")
    }

    @Test func thePagesAreaIsTheMostCommonAcrossItsEntries() {
        let id = UUID()
        let at = Date(timeIntervalSince1970: 0)
        let entries: [(id: UUID, date: Date, areas: [LifeArea])] = [
            (UUID(), at, [.work]), (UUID(), at.addingTimeInterval(10), [.work, .friends]), (UUID(), at.addingTimeInterval(20), [.love]),
        ]
        #expect(P.primaryArea(entries, entityID: id) == .work)
        #expect(P.primaryArea([], entityID: id) == nil)
    }
}
