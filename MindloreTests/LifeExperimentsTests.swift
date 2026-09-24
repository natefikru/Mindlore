import Foundation
import SwiftData
import Testing
@testable import Mindlore

struct LifeSuggestionTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    // Twelve weeks: odd weeks light with running, even weeks heavy without it (one heavy week runs).
    private var facts: [LifeSignals.EntryFact] {
        (0..<12).flatMap { week -> [LifeSignals.EntryFact] in
            let light = week.isMultiple(of: 2) == false
            let start = now.addingTimeInterval(-Double(week) * 7 * 86_400 - 86_400)
            let tags = light || week == 4 ? ["running"] : ["deadline"]
            return (0..<2).map { day in
                LifeSignals.EntryFact(date: start.addingTimeInterval(-Double(day) * 3_600), areas: [light ? .play : .work], valence: light ? 1 : -1, tags: tags)
            }
        }
    }

    private var interval: DateInterval { DateInterval(start: now.addingTimeInterval(-90 * 86_400), end: now) }

    @Test func whatFillsTheLighterWeeksIsOffered() throws {
        let suggestion = try #require(LifeSignals.suggestion(facts, interval: interval, baseline: 0, calendar: utc))
        #expect(suggestion.subject == .tag("running"), "something done beats a whole area that did a little better")
        #expect(suggestion.lighterWith == suggestion.lighterWeeks)
        #expect(suggestion.heavierWith == 1)
    }

    @Test func somethingAlreadyOfferedIsSkipped() {
        let next = LifeSignals.suggestion(facts, interval: interval, baseline: 0, skipping: [.tag("running")], calendar: utc)
        #expect(next?.subject == .area(.play))
        #expect(LifeSignals.suggestion(facts, interval: interval, baseline: 0, skipping: [.tag("running")], hidden: [.play], calendar: utc) == nil)
    }

    @Test func tooFewLighterWeeksOffersNothing() {
        let few = Array(facts.suffix(6))
        #expect(LifeSignals.suggestion(few, interval: interval, baseline: 0, calendar: utc) == nil)
        #expect(LifeSignals.suggestion(facts, interval: interval, baseline: nil, calendar: utc) == nil)
    }

    @Test func theReportCountsWeeksWithItAndHowTheyFelt() {
        let start = now.addingTimeInterval(-21 * 86_400)
        let after = [
            LifeSignals.EntryFact(date: start.addingTimeInterval(2 * 86_400), valence: 1, tags: ["running"]),
            LifeSignals.EntryFact(date: start.addingTimeInterval(9 * 86_400), valence: -1, tags: ["deadline"]),
            LifeSignals.EntryFact(date: start.addingTimeInterval(16 * 86_400), valence: 1, tags: ["running"]),
        ]
        let tried = LifeSignals.tried(.tag("running"), since: start, entries: after, baseline: 0, now: now, calendar: utc)
        #expect(tried.weeksWith == 2)
        #expect(tried.weeksSince >= 3)
        #expect(tried.height == 1)
        #expect(LifeCopy.tried(tried, subject: .tag("running"), name: \.defaultName).hasSuffix("Those weeks were lighter than your usual."))
    }
}

@MainActor
struct LifeExperimentsTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        container = try ModelContainerFactory.make(.inMemory)
    }

    @Test func acceptingMakesALooseEndDueThisWeekWithNoEntryBehindIt() throws {
        let suggestion = LifeSignals.Suggestion(subject: .tag("running"), lighterWith: 5, lighterWeeks: 6, heavierWith: 1, heavierWeeks: 6)
        let thread = LifeExperiments.accept(suggestion, threadText: "Make room for some running this week", in: context)
        #expect(thread.sourceEntryID == nil)
        #expect(thread.isOpen)
        #expect((thread.dueDate ?? .distantPast) > .now)
        let saved = LifeExperiments.all(in: context)
        #expect(saved.map(\.state) == [.trying])
        #expect(saved.first?.looseEndID == thread.id)
        #expect(LooseEnd.all(in: context).count == 1)
    }

    @Test func decliningRemembersSoItIsNotOfferedAgain() {
        LifeExperiments.decline(.area(.play), in: context)
        #expect(LifeExperiments.offered(in: context) == [.area(.play)])
        #expect(LifeExperiments.all(in: context).first?.looseEndID == nil, "a declined one made no loose end")
        #expect(LooseEnd.all(in: context).isEmpty)
    }

    @Test func subjectsRoundTrip() {
        for subject in [LifeSignals.Suggestion.Subject.tag("long walks"), .area(.friends)] {
            #expect(LifeExperiments.decode(LifeExperiments.encode(subject)) == subject)
        }
        #expect(LifeExperiments.decode("area:nothing") == nil)
    }
}
