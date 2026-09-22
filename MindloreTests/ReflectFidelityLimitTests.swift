import Foundation
import Testing
@testable import Mindlore

// The on-device model's context is about 4,096 tokens, so a period's prompt is fitted to a
// character limit before it goes: a long week, or a busy month, must not overflow it.
struct ReflectFidelityLimitTests {
    private func entry(_ day: Int, words: Int) -> ReflectFidelity.WeekEntry {
        ReflectFidelity.WeekEntry(
            id: UUID(),
            date: Date(timeIntervalSince1970: 1_790_000_000 + Double(day) * 86_400),
            title: "Day \(day)",
            text: Array(repeating: "word", count: words).joined(separator: " ")
        )
    }

    @Test func aLongWeekFitsTheLimitAndKeepsEveryEntry() {
        let entries = (0..<7).map { entry($0, words: 400) }
        let prompt = ReflectFidelity.weekPrompt(entries, characterLimit: 3_600)
        #expect(prompt.count <= 3_600 + 7 * 40)
        for day in 0..<7 {
            #expect(prompt.contains("Day \(day)"))
        }
        #expect(prompt.contains("\u{2026}"))
    }

    @Test func withoutALimitNothingIsCut() {
        let entries = [entry(0, words: 400)]
        #expect(!ReflectFidelity.weekPrompt(entries).contains("\u{2026}"))
    }

    @Test func aCutEndsOnAWholeWord() {
        #expect(ReflectFidelity.opening(of: "one two three four", characters: 9) == "one two\u{2026}")
        #expect(ReflectFidelity.opening(of: "short", characters: 9) == "short")
    }

    // Lines are spread across the month, ends included, not the first days only.
    @Test func digestLinesAreSpreadWhenTheyDoNotAllFit() {
        let lines = (1...30).map { String(format: "line %02d %@", $0, String(repeating: "x", count: 50)) }
        let kept = ReflectFidelity.spread(lines, within: 600)
        #expect(kept.count > 1 && kept.count < 30)
        #expect(kept.first == lines.first)
        #expect(kept.last == lines.last)
        #expect(kept.joined(separator: "\n").count <= 600)
    }

    @Test func aMonthPromptKeepsItsWeekSummariesAndFitsTheLimit() {
        let week = [ReflectQueueItem(id: "generated:0", source: .generated, title: "This week", body: "Danny opened the truck.", prompt: "What next?")]
        let lines = (1...200).map { "line \($0) " + String(repeating: "y", count: 80) }
        let prompt = ReflectFidelity.monthPrompt(cachedWeekItems: [week], digestLines: lines, characterLimit: 3_600)
        #expect(prompt.contains("Danny opened the truck."))
        #expect(prompt.count <= 3_600 + 40)
    }
}
