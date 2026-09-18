import Foundation
import Testing
@testable import Mindlore

struct AskRollupsTests {
    // Monday 14 September 2026, 14:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_789_394_400)

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    private func index(_ inputs: [AskIndex.DocumentInput]) -> AskIndex {
        AskIndex.build(from: inputs)
    }

    private func document(daysAgo: Int, text: String = "an ordinary day", isSendable: Bool = true) -> AskIndex.DocumentInput {
        AskIndex.DocumentInput(
            id: UUID(),
            date: now.addingTimeInterval(-Double(daysAgo) * 86_400),
            text: text,
            tags: ["deadline"],
            areas: ["Work"],
            mood: "tired",
            isSendable: isSendable
        )
    }

    private func month(daysAgo: Int) -> DateInterval {
        calendar.dateInterval(of: .month, for: now.addingTimeInterval(-Double(daysAgo) * 86_400))!
    }

    // MARK: - Counting

    @Test func aMonthCountsTheEntriesInItAndSaysWhatItCovers() throws {
        let documents = [document(daysAgo: 1), document(daysAgo: 5), document(daysAgo: 9)]
        let months = AskRollups.months(for: [month(daysAgo: 1)], in: index(documents), calendar: calendar)
        let first = try #require(months.first)

        #expect(first.count == 3)
        let line = AskRollups.line(for: first, calendar: calendar)
        #expect(line.hasPrefix("September 2026: 3 entries"))
        #expect(line.contains("to"))
    }

    @Test func aMonthWithNothingInItIsNotALine() {
        let months = AskRollups.months(for: [month(daysAgo: 400)], in: index([document(daysAgo: 1)]), calendar: calendar)
        #expect(months.isEmpty)
    }

    @Test func oneEntryInAMonthNamesTheDayOnce() throws {
        let months = AskRollups.months(for: [month(daysAgo: 1)], in: index([document(daysAgo: 1)]), calendar: calendar)
        let line = AskRollups.line(for: try #require(months.first), calendar: calendar)
        #expect(line == "September 2026: 1 entry, 13 September")
    }

    // MARK: - The gate

    @Test func anEntryAskMayNotSendIsNotCounted() throws {
        let documents = [document(daysAgo: 1), document(daysAgo: 2, isSendable: false)]
        let months = AskRollups.months(for: [month(daysAgo: 1)], in: index(documents), calendar: calendar)
        // The number the model reasons about has to match the corpus it was handed. An entry still
        // awaiting text is not part of that corpus.
        #expect(months.first?.count == 1)
    }

    // MARK: - What a block may carry

    @Test func aBlockCarriesNumbersAndDatesAndNothingElse() throws {
        let sentinel = "PRIVATE-SENTINEL-7Q2X"
        let documents = [
            AskIndex.DocumentInput(
                id: UUID(),
                date: now,
                title: sentinel,
                text: sentinel,
                entityNames: [sentinel],
                tags: [sentinel],
                areas: [sentinel],
                mood: sentinel
            ),
        ]
        let months = AskRollups.months(for: [month(daysAgo: 0)], in: index(documents), calendar: calendar)
        let blocks = AskRollups.blocks(for: months, calendar: calendar)

        // Counts and coverage only (owner, 2026-09-18): mood, area, and tag distributions are
        // Reflect's data, and a rollup here names nobody and quotes nothing.
        #expect(blocks.count == 1)
        #expect(blocks[0].contains(sentinel) == false)
    }

    // MARK: - Rolling up by year

    @Test func pastTwoYearsTheMonthsBecomeYears() {
        let documents = (0..<36).map { document(daysAgo: $0 * 31) }
        let intervals = (0..<36).map { month(daysAgo: $0 * 31) }
        let months = AskRollups.months(for: intervals, in: index(documents), calendar: calendar)
        #expect(months.count > AskRollups.maxMonthsBeforeRollingUpByYear)

        let blocks = AskRollups.blocks(for: months, calendar: calendar)
        // Thirty-six lines saying "3 entries" each is more lines than it is information.
        #expect(blocks.count < 5)
        #expect(blocks.allSatisfy { $0.contains("entries across") })
        #expect(blocks[0].hasPrefix("2026"), "newest year first")
    }

    @Test func twoYearsOrFewerStayAsMonths() {
        let documents = (0..<12).map { document(daysAgo: $0 * 31) }
        let intervals = (0..<12).map { month(daysAgo: $0 * 31) }
        let blocks = AskRollups.blocks(for: AskRollups.months(for: intervals, in: index(documents), calendar: calendar), calendar: calendar)
        #expect(blocks.count == 12)
        #expect(blocks.allSatisfy { $0.contains("entries across") == false })
    }
}
