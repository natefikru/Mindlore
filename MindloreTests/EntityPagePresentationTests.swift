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
        let rows = P.entryRows([
            .init(entryID: old, date: Date(timeIntervalSince1970: 1), title: "Walk", text: "Rain. Sarah came along.", surfaces: ["Sarah"], guessed: false),
            .init(entryID: new, date: Date(timeIntervalSince1970: 2), title: "", text: "saw sarah at the market today and we talked for a while", surfaces: ["sarah"], guessed: true),
        ])

        #expect(rows.map(\.id) == [new, old])
        #expect(rows[0].heading == "saw sarah at the market today and we…")
        #expect(rows[0].sentence == "saw sarah at the market today and we talked for a while")
        #expect(rows[0].guessed)
        #expect(rows[1].heading == "Walk")
        #expect(rows[1].sentence == "Sarah came along.")
        #expect(!rows[1].guessed)
    }

    @Test func anEntryThatNoLongerNamesThemHasNoSentence() {
        let rows = P.entryRows([.init(entryID: a, date: .now, title: "", text: "", surfaces: ["Sarah"], guessed: false)])
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
