import Foundation
import SwiftData
import Testing
@testable import Mindlore

// TodaySource against a real store: the fetching, the merge walk, and what the user hid or muted.
// The rules about which card wins live in TodayComposerTests, which needs none of this.
@MainActor
struct TodayTests {
    private let container: ModelContainer
    private let settings: SettingsStore
    private var context: ModelContext { container.mainContext }
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    init() throws {
        container = try ModelContainerFactory.make(.inMemory)
        settings = SettingsStore(store: FakeKeyValueStore(), diagnostics: .disabled)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private var now: Date { date(2026, 9, 19) }

    @discardableResult
    private func entry(_ text: String = "an entry", on day: Date, summary: String? = nil) throws -> Entry {
        let entry = Entry(text: text)
        entry.entryDate = day
        context.insert(entry)
        if let summary {
            let insights = EntryInsights(generatedAt: day, modelUsed: "test")
            context.insert(insights)
            insights.entry = entry
            insights.summary = summary
        }
        try context.save()
        return entry
    }

    @discardableResult
    private func entity(_ name: String, links: Int = 4, lastSeen: Date? = nil) throws -> Entity {
        let entity = Entity(name: name, key: name.lowercased(), kind: .person)
        entity.linkCount = links
        entity.lastLinkedAt = lastSeen ?? date(2026, 6, 1)
        context.insert(entity)
        try context.save()
        return entity
    }

    @discardableResult
    private func looseEnd(_ text: String, opened: Date, about: [UUID] = []) throws -> LooseEnd {
        let end = LooseEnd(text: text, sourceEntryID: UUID(), sourceEntryDate: opened, entityIDs: about)
        context.insert(end)
        try context.save()
        return end
    }

    private func today(at moment: Date? = nil) -> Today {
        TodaySource.today(in: context, settings: settings, now: moment ?? now, calendar: utc)
    }

    // MARK: - Fetching

    @Test func theNewestEntrySummaryIsTheLastCard() throws {
        try entry("older", on: date(2026, 9, 1), summary: "older summary")
        try entry("newest", on: date(2026, 9, 18), summary: "the newest summary")

        #expect(TodayCopy.body(try #require(today().cards.last)) == "the newest summary")
    }

    // The composer filters future dates too, but it can only filter what it is handed: if the
    // fetch hands over a future entry as the newest, the label is already wrong.
    @Test func anEntryDatedNextYearIsNotTheLatestEntry() throws {
        try entry("real", on: date(2026, 9, 18), summary: "the real last entry")
        try entry("future", on: date(2027, 5, 1), summary: "from the future")

        let cards = today().cards
        #expect(cards.contains { TodayCopy.body($0) == "the real last entry" })
        #expect(!cards.contains { TodayCopy.body($0) == "from the future" })
    }

    @Test func anEntryFromAYearAgoIsFound() throws {
        try entry("last year", on: date(2025, 9, 19))

        #expect(today().cards.contains { $0.kind == .onThisDay })
    }

    @Test func aLeapDayEntryIsFoundOnTheTwentyEighth() throws {
        try entry("leap day", on: date(2024, 2, 29))

        #expect(today(at: date(2026, 2, 28)).cards.contains { $0.kind == .onThisDay })
    }

    @Test func thisWeeksEntriesFillTheirDots() throws {
        try entry("monday", on: date(2026, 9, 14))
        try entry("today", on: now)
        try entry("long ago", on: date(2025, 1, 1))

        #expect(today().week.filter(\.hasEntry).count == 2)
    }

    // MARK: - Hidden, muted, merged

    @Test func aHiddenPersonNeverResurfaces() throws {
        let maya = try entity("Maya", lastSeen: date(2026, 6, 1))
        try entry("an entry", on: now)
        #expect(today().cards.contains { $0.kind == .beenAWhile })

        maya.hidden = true
        try context.save()

        #expect(!today().cards.contains { $0.kind == .beenAWhile })
    }

    @Test func aMutedPersonNeverResurfaces() throws {
        let maya = try entity("Maya", lastSeen: date(2026, 6, 1))
        try entry("an entry", on: now)

        maya.resurfacingMuted = true
        try context.save()

        #expect(!today().cards.contains { $0.kind == .beenAWhile })
    }

    // The mute belongs to whoever the person is now, not to the id that lost a merge.
    @Test func aMuteFollowsAMergeToTheWinner() throws {
        let winner = try entity("Maya Okonkwo", lastSeen: date(2026, 6, 1))
        let loser = try entity("Maya", links: 9, lastSeen: date(2026, 6, 1))
        loser.mergedIntoID = winner.id
        winner.resurfacingMuted = true
        try context.save()
        try entry("an entry", on: now)

        #expect(!today().cards.contains { $0.kind == .beenAWhile })
    }

    @Test func aMergeLoserIsNeverItsOwnCard() throws {
        let winner = try entity("Maya Okonkwo", lastSeen: date(2026, 6, 1))
        let loser = try entity("Maya", links: 9, lastSeen: date(2026, 6, 1))
        loser.mergedIntoID = winner.id
        try context.save()
        try entry("an entry", on: now)

        let names = today().cards.compactMap { card -> String? in
            if case .beenAWhile(let who) = card { return who.name }
            return nil
        }
        #expect(names == ["Maya Okonkwo"])
    }

    @Test func aLooseEndAboutAHiddenPersonIsNotACard() throws {
        let maya = try entity("Maya")
        try entry("an entry", on: now)
        try looseEnd("ask Maya about the lease", opened: date(2026, 1, 4), about: [maya.id])
        #expect(today().cards.contains { $0.kind == .stillOpen })

        maya.hidden = true
        try context.save()

        #expect(!today().cards.contains { $0.kind == .stillOpen })
    }

    // A loose end is one sentence about everyone in it, so a hidden bystander takes the card
    // with them.
    @Test func oneHiddenSubjectSuppressesALooseEndAboutSeveralPeople() throws {
        let maya = try entity("Maya")
        let tom = try entity("Tom")
        maya.hidden = true
        try context.save()
        try entry("an entry", on: now)
        try looseEnd("call Maya and Tom back", opened: date(2026, 1, 4), about: [maya.id, tom.id])

        #expect(!today().cards.contains { $0.kind == .stillOpen })
    }

    @Test func aLooseEndAboutAMergedHiddenPersonIsStillSuppressed() throws {
        let winner = try entity("Maya Okonkwo")
        let loser = try entity("Maya")
        loser.mergedIntoID = winner.id
        winner.hidden = true
        try context.save()
        try entry("an entry", on: now)
        try looseEnd("ask Maya about the lease", opened: date(2026, 1, 4), about: [loser.id])

        #expect(!today().cards.contains { $0.kind == .stillOpen })
    }

    @Test func aLooseEndAboutNobodyInParticularStillShows() throws {
        try entry("an entry", on: now)
        try looseEnd("book the dentist", opened: date(2026, 1, 4))

        #expect(today().cards.contains { $0.kind == .stillOpen })
    }

    @Test func aFadedThreadIsNotStillOpen() throws {
        try entry("an entry", on: now)
        let end = try looseEnd("book the dentist", opened: date(2026, 1, 4))
        end.setStatus(.faded, at: now)
        try context.save()

        #expect(!today().cards.contains { $0.kind == .stillOpen })
    }

    // MARK: - Settings

    @Test func theResurfacingSwitchReachesTheCards() throws {
        try entity("Maya", lastSeen: date(2026, 6, 1))
        try entry("an entry", on: now)
        #expect(today().cards.contains { $0.kind == .beenAWhile })

        settings.resurfacingEnabled = false

        #expect(!today().cards.contains { $0.kind == .beenAWhile })
    }

    @Test func aDismissalReachesTheCardsAndExpiresWithTheDay() throws {
        try entry("an entry", on: now, summary: "a summary")
        let card = try #require(today().cards.first)

        settings.dismissTodayCard(card.id, on: TodayDismissal.stamp(now, calendar: utc))

        #expect(!today().cards.contains(card))
        #expect(today(at: date(2026, 9, 20)).cards.contains(card), "tomorrow it is back")
    }

    // MARK: - Privacy

    @Test func nothingTodayLogsCarriesAWordTheUserWrote() throws {
        let sentinel = DiagnosticsPrivacyTests.sentinel
        let maya = try entity(sentinel, lastSeen: date(2026, 6, 1))
        try entry(sentinel, on: now, summary: sentinel)
        try looseEnd(sentinel, opened: date(2026, 1, 4), about: [maya.id])
        settings.setUserName(sentinel)

        let composed = today()
        // Without this the privacy check below could pass while never touching the copy path.
        let words = composed.greeting + composed.cards.map { TodayCopy.title($0) + TodayCopy.body($0) }.joined()
        #expect(words.contains(sentinel), "the sentinel really is in what Today says")

        let file = URL.temporaryDirectory.appending(path: "today-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        let log = DiagnosticsLog(fileURL: file)
        log.record("today.shown", TodayCopy.shownFields(composed, milliseconds: 4.2))
        for (rank, card) in composed.cards.enumerated() {
            log.record("today.dismissed", TodayCopy.dismissedFields(card, rank: rank))
        }

        let written = try String(contentsOf: file, encoding: .utf8)
        #expect(written.contains("today.shown"))
        #expect(written.contains("today.dismissed"))
        #expect(!written.contains(sentinel))
    }
}
