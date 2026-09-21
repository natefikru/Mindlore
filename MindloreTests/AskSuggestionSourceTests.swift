import Foundation
import SwiftData
import Testing
@testable import Mindlore

// AskSuggestionSource against a real store: what may be named on the empty Ask screen. The rules
// are Today's, because they answer the same question: a name the user put away never shows up.
@MainActor
struct AskSuggestionSourceTests {
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

    private var now: Date { date(2026, 9, 21) }

    @discardableResult
    private func entity(_ name: String, kind: EntityKind = .person, lastSeen: Date? = nil) throws -> Entity {
        let entity = Entity(name: name, key: name.lowercased(), kind: kind)
        entity.linkCount = 3
        entity.lastLinkedAt = lastSeen ?? date(2026, 9, 1)
        context.insert(entity)
        try context.save()
        return entity
    }

    @discardableResult
    private func looseEnd(_ text: String, opened: Date? = nil, about: [UUID] = []) throws -> LooseEnd {
        let end = LooseEnd(text: text, sourceEntryID: UUID(), sourceEntryDate: opened ?? date(2026, 8, 1), entityIDs: about)
        context.insert(end)
        try context.save()
        return end
    }

    private func entry(on day: Date, areas: [LifeArea]) throws {
        let entry = Entry(text: "an entry")
        entry.entryDate = day
        context.insert(entry)
        let insights = EntryInsights(generatedAt: day, modelUsed: "test")
        context.insert(insights)
        insights.entry = entry
        insights.areas = areas
        try context.save()
    }

    // Every text the source could produce over a week, so a test isn't pinned to one day's window.
    private func week() -> Set<String> {
        Set((0..<7).flatMap { offset in
            AskSuggestionSource.suggestions(
                in: context, settings: settings, now: now.addingTimeInterval(Double(offset) * 86_400), calendar: utc
            ).map(\.text)
        })
    }

    // MARK: - Names

    @Test func theMostRecentNamesAreSuggested() throws {
        try entity("Maya", lastSeen: date(2026, 9, 20))
        try entity("Theo", lastSeen: date(2026, 9, 19))
        try entity("Old friend", lastSeen: date(2025, 1, 1))

        let texts = week()
        #expect(texts.contains("What's been going on with Maya?"))
        #expect(texts.contains("What's been going on with Theo?"))
        #expect(!texts.contains { $0.contains("Old friend") })
    }

    @Test func aHiddenNameIsNeverSuggested() throws {
        try entity("Maya", lastSeen: date(2026, 9, 20)).hidden = true
        try context.save()

        #expect(!week().contains { $0.contains("Maya") })
    }

    // The gap this fixes: the old suggestions checked hidden and merged, never muted.
    @Test func aMutedNameIsNeverSuggested() throws {
        try entity("Maya", lastSeen: date(2026, 9, 20)).resurfacingMuted = true
        try context.save()

        #expect(!week().contains { $0.contains("Maya") })
    }

    @Test func aMergedNameIsNotSuggestedTwice() throws {
        let winner = try entity("Maya", lastSeen: date(2026, 9, 19))
        try entity("Maya R", lastSeen: date(2026, 9, 20)).mergedIntoID = winner.id
        try context.save()

        #expect(!week().contains { $0.contains("Maya R") })
        #expect(week().contains("What's been going on with Maya?"))
    }

    @Test func aTagIsNotAName() throws {
        try entity("running", kind: .tag, lastSeen: date(2026, 9, 20))

        #expect(!week().contains { $0.contains("running") })
    }

    // MARK: - Threads

    @Test func anOpenThreadIsSuggested() throws {
        try looseEnd("Call the landlord")

        #expect(week().contains { $0.contains("Call the landlord") })
    }

    @Test func aClosedOrFadedThreadIsNot() throws {
        try looseEnd("Settled one").setStatus(.resolved, at: date(2026, 9, 10))
        try looseEnd("Faded one").setStatus(.faded, at: date(2026, 9, 10))
        try looseEnd("Let go").setStatus(.dismissed, at: date(2026, 9, 10))
        try context.save()

        let texts = week()
        #expect(!texts.contains { $0.contains("Settled one") || $0.contains("Faded one") || $0.contains("Let go") })
    }

    // A thread names everyone it's about in one sentence, so one concealed subject drops it whole.
    @Test func aThreadAboutAHiddenOrMutedNameIsDropped() throws {
        let hidden = try entity("Maya")
        hidden.hidden = true
        let muted = try entity("Theo")
        muted.resurfacingMuted = true
        try context.save()
        try looseEnd("Hear back from Maya", about: [hidden.id])
        try looseEnd("Decide on Theo's offer", about: [muted.id])

        let texts = week()
        #expect(!texts.contains { $0.contains("Hear back from Maya") })
        #expect(!texts.contains { $0.contains("Theo's offer") })
    }

    @Test func aThreadAboutSomeoneMergedIntoAHiddenNameIsDropped() throws {
        let winner = try entity("Maya")
        winner.hidden = true
        let loser = try entity("Maya R")
        loser.mergedIntoID = winner.id
        try context.save()
        try looseEnd("Hear back from Maya", about: [loser.id])

        #expect(!week().contains { $0.contains("Hear back from Maya") })
    }

    // MARK: - Areas

    @Test func theAreaTheLastMonthLeanedOnIsSuggested() throws {
        try entry(on: date(2026, 9, 10), areas: [.work])
        try entry(on: date(2026, 9, 12), areas: [.work, .health])
        try entry(on: date(2026, 9, 14), areas: [.work])

        #expect(week().contains("How has Work been lately?"))
    }

    @Test func oneEntryIsNotALean() throws {
        try entry(on: date(2026, 9, 10), areas: [.health])

        #expect(!week().contains { $0.hasPrefix("How has") })
    }

    @Test func entriesOlderThanAMonthDontCount() throws {
        try entry(on: date(2026, 6, 1), areas: [.money])
        try entry(on: date(2026, 6, 2), areas: [.money])

        #expect(!week().contains("How has Money been lately?"))
    }

    @Test func aHiddenAreaIsNeverSuggested() throws {
        settings.setHidden(.work, true)
        try entry(on: date(2026, 9, 10), areas: [.work])
        try entry(on: date(2026, 9, 12), areas: [.work])

        #expect(!week().contains { $0.contains("Work") })
    }

    @Test func aRenamedAreaIsCalledWhatTheUserCallsIt() throws {
        settings.rename(.work, to: "The studio")
        try entry(on: date(2026, 9, 10), areas: [.work])
        try entry(on: date(2026, 9, 12), areas: [.work])

        #expect(week().contains("How has The studio been lately?"))
    }

    // MARK: - Nothing yet

    @Test func anEmptyJournalStillOffersSomething() {
        let shown = AskSuggestionSource.suggestions(in: context, settings: settings, now: now, calendar: utc)
        #expect(!shown.isEmpty)
        #expect(shown.allSatisfy { $0.source == .time })
    }
}
