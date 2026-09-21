import Foundation
import Testing
@testable import Mindlore

// The decider is pure, so every rule is a plain function call: no container, no view, no clock.
// What may be named at all is AskSuggestionSourceTests' job.
struct AskSuggestionsTests {
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func input(
        names: [AskSuggestions.Name] = [],
        threads: [String] = [],
        area: AskSuggestions.Area? = nil,
        on day: Date? = nil
    ) -> AskSuggestions.Input {
        AskSuggestions.Input(names: names, threads: threads, area: area, now: day ?? date(2026, 9, 21), calendar: utc)
    }

    private let maya = AskSuggestions.Name(name: "Maya", kind: .person)
    private let river = AskSuggestions.Name(name: "the river", kind: .place)
    private let work = AskSuggestions.Area(area: .work, name: "Work")

    private var full: AskSuggestions.Input {
        input(names: [maya, river], threads: ["Send Maya the photos"], area: work)
    }

    // MARK: - Phrasing

    @Test func eachKindOfNameGetsItsOwnQuestion() {
        let cases: [(EntityKind, String)] = [
            (.person, "What's been going on with X?"),
            (.place, "What happened at X?"),
            (.organization, "What's been happening at X?"),
            (.project, "How is X going?"),
            (.event, "How did X go?"),
        ]
        for (kind, expected) in cases {
            let suggestion = AskSuggestions.question(about: .init(name: "X", kind: kind))
            #expect(suggestion.text == expected)
            #expect(suggestion.source == .name(kind))
        }
    }

    // A thread is written as an imperative ("Send Maya the photos"), so it is quoted rather than
    // grafted into a sentence it would break.
    @Test func aThreadIsQuotedInTheUsersOwnWords() {
        let all = (0..<5).flatMap { offset in
            AskSuggestions.suggestions(input(threads: ["Send Maya the photos"], on: date(2026, 9, 21 + offset)))
        }
        #expect(all.contains(AskSuggestion(text: "What happened with \u{201C}Send Maya the photos\u{201D}?", source: .thread)))
    }

    @Test func theAreaQuestionUsesTheUsersNameForIt() {
        let renamed = AskSuggestions.Area(area: .work, name: "The studio")
        let texts = AskSuggestions.suggestions(input(area: renamed)).map(\.text)
        #expect(texts.contains("How has The studio been lately?"))
    }

    // MARK: - Choosing three

    @Test func threeAreShownWhenThereIsEnoughToGoOn() {
        #expect(AskSuggestions.suggestions(full).count == AskSuggestions.limit)
    }

    @Test func theThreeHaveDifferentShapesOnAnyDay() {
        for offset in 0..<10 {
            let shown = AskSuggestions.suggestions(input(names: [maya, river], threads: ["Send Maya the photos"], area: work, on: date(2026, 9, 1 + offset)))
            let kinds = Set(shown.map { suggestion -> String in
                switch suggestion.source {
                case .name: "name"
                case .thread: "thread"
                case .area: "area"
                case .time: "time"
                }
            })
            // Five slots, two of them names: a window of three always holds at least two kinds.
            #expect(kinds.count >= 2)
            #expect(Set(shown).count == shown.count, "nothing appears twice")
        }
    }

    @Test func theSameDayGivesTheSameThree() {
        let morning = AskSuggestions.suggestions(input(names: [maya, river], threads: ["Send Maya the photos"], area: work, on: date(2026, 9, 21, hour: 7)))
        let night = AskSuggestions.suggestions(input(names: [maya, river], threads: ["Send Maya the photos"], area: work, on: date(2026, 9, 21, hour: 23)))
        #expect(morning == night)
    }

    @Test func theChoiceTurnsFromOneDayToTheNext() {
        let today = AskSuggestions.suggestions(input(names: [maya, river], threads: ["Send Maya the photos"], area: work, on: date(2026, 9, 21)))
        let tomorrow = AskSuggestions.suggestions(input(names: [maya, river], threads: ["Send Maya the photos"], area: work, on: date(2026, 9, 22)))
        #expect(today != tomorrow)
    }

    @Test func everySlotGetsShownOverAWeek() {
        let week = Set((0..<7).flatMap { offset in
            AskSuggestions.suggestions(input(names: [maya, river], threads: ["Send Maya the photos"], area: work, on: date(2026, 9, 21 + offset)))
                .map(\.text)
        })
        #expect(week.contains("What's been going on with Maya?"))
        #expect(week.contains("What happened at the river?"))
        #expect(week.contains("How has Work been lately?"))
        #expect(week.contains { $0.contains("Send Maya the photos") })
    }

    // MARK: - Thin journals

    @Test func anEmptyJournalStillOffersSomething() {
        let shown = AskSuggestions.suggestions(input())
        #expect(shown.count == 2)
        #expect(shown.allSatisfy { $0.source == .time })
        #expect(shown.contains(AskSuggestions.fallback))
    }

    @Test func threeSlotsAreShownAsTheyAre() {
        let shown = AskSuggestions.suggestions(input(names: [maya], area: work))
        #expect(shown.count == 3)
        #expect(!shown.contains(AskSuggestions.fallback))
    }

    // A long thread makes a question nobody would type. It is skipped for the next one, not cut.
    @Test func aLongThreadIsSkippedForAShorterOne() {
        let long = String(repeating: "a very long thread ", count: 5)
        let shown = (0..<5).flatMap { offset in
            AskSuggestions.suggestions(input(threads: [long, "Call the landlord"], on: date(2026, 9, 21 + offset)))
        }
        #expect(!shown.contains { $0.text.contains("a very long thread") })
        #expect(shown.contains { $0.text.contains("Call the landlord") })
    }

    // MARK: - The day

    @Test func theDayTurnsAtLocalMidnight() {
        let before = AskSuggestions.dayOrdinal(date(2026, 9, 21, hour: 23), calendar: utc)
        let after = AskSuggestions.dayOrdinal(date(2026, 9, 22, hour: 0), calendar: utc)
        #expect(after == before + 1)
    }
}
