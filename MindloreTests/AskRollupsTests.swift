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

    // Everything sendable counts as matched unless a test says otherwise, which is the shape the
    // plan hands over.
    private func months(_ intervals: [DateInterval], in index: AskIndex, matching: Set<UUID>? = nil) -> [AskRollups.Month] {
        AskRollups.months(
            for: intervals,
            matching: matching ?? Set(index.documents.map(\.id)),
            in: index,
            calendar: calendar
        )
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
        let months = months([month(daysAgo: 1)], in: index(documents))
        let first = try #require(months.first)

        #expect(first.count == 3)
        let line = AskRollups.line(for: first, calendar: calendar)
        #expect(line.hasPrefix("September 2026: 3 entries"))
        #expect(line.contains("to"))
    }

    @Test func aMonthWithNothingInItIsNotALine() {
        let months = months([month(daysAgo: 400)], in: index([document(daysAgo: 1)]))
        #expect(months.isEmpty)
    }

    @Test func oneEntryInAMonthNamesTheDayOnce() throws {
        let months = months([month(daysAgo: 1)], in: index([document(daysAgo: 1)]))
        let line = AskRollups.line(for: try #require(months.first), calendar: calendar)
        // The fixture's document() always writes mood "tired" (category drained) and area "Work".
        #expect(line == "September 2026: 1 entry, 13 September (mood: drained 1; areas: work 1)")
    }

    // MARK: - Mood and area distribution

    @Test func aMonthLineNamesTheHighestCountMoodsAndAreasFirst() throws {
        let documents = [
            AskIndex.DocumentInput(id: UUID(), date: now.addingTimeInterval(-1 * 86_400), tags: [], areas: ["Work"], mood: "calm"),
            AskIndex.DocumentInput(id: UUID(), date: now.addingTimeInterval(-2 * 86_400), tags: [], areas: ["Work"], mood: "calm"),
            AskIndex.DocumentInput(id: UUID(), date: now.addingTimeInterval(-3 * 86_400), tags: [], areas: ["Health"], mood: "anxious"),
        ]
        let months = months([month(daysAgo: 1)], in: index(documents))
        let line = AskRollups.line(for: try #require(months.first), calendar: calendar)
        #expect(line.contains("mood: calm 2, anxious 1"))
        #expect(line.contains("areas: work 2, health 1"))
    }

    @Test func aDistributionLineCapsAtTheMaximumAndDropsTheRest() throws {
        let moods = ["joyful", "calm", "connected", "reflective", "anxious", "angry", "sad", "tired"]
        let documents = moods.enumerated().map { index, mood in
            AskIndex.DocumentInput(id: UUID(), date: now.addingTimeInterval(-1 * 86_400), tags: [], areas: [], mood: mood)
        }
        let months = months([month(daysAgo: 1)], in: index(documents))
        let period = try #require(months.first).period
        #expect(period.moodCounts.count > AskRollups.maxDistributionEntriesInLine, "the fixture covers more categories than the cap")
        let line = AskRollups.line(for: months.first!, calendar: calendar)
        let moodSegment = try #require(line.range(of: "mood: [^;)]+", options: .regularExpression))
        #expect(line[moodSegment].components(separatedBy: ", ").count == AskRollups.maxDistributionEntriesInLine)
    }

    @Test func anEntryAskMayNotSendDoesNotContributeToTheDistribution() throws {
        let documents = [
            AskIndex.DocumentInput(id: UUID(), date: now.addingTimeInterval(-1 * 86_400), tags: [], areas: ["Work"], mood: "calm"),
            AskIndex.DocumentInput(id: UUID(), date: now.addingTimeInterval(-1 * 86_400), tags: [], areas: ["Health"], mood: "angry", isSendable: false),
        ]
        let months = months([month(daysAgo: 1)], in: index(documents))
        let period = try #require(months.first).period
        #expect(period.moodCounts[.angry] == nil)
        #expect(period.areaCounts[.health] == nil)
    }

    @Test func rollingUpToYearsMergesTheDistributionAcrossMonths() {
        let documents = (0..<36).map { i in
            AskIndex.DocumentInput(id: UUID(), date: now.addingTimeInterval(-Double(i * 31) * 86_400), tags: [], areas: ["Work"], mood: "calm")
        }
        let intervals = (0..<36).map { month(daysAgo: $0 * 31) }
        let blocks = AskRollups.lines(for: months(intervals, in: index(documents)), calendar: calendar)
        #expect(blocks.allSatisfy { $0.contains("mood: calm") && $0.contains("areas: work") })
    }

    // MARK: - The gate

    @Test func anEntryAskMayNotSendIsNotCounted() throws {
        let documents = [document(daysAgo: 1), document(daysAgo: 2, isSendable: false)]
        let months = months([month(daysAgo: 1)], in: index(documents))
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
        let months = months([month(daysAgo: 0)], in: index(documents))
        let blocks = AskRollups.lines(for: months, calendar: calendar)

        // Counts and coverage only (owner, 2026-09-18): mood, area, and tag distributions are
        // Reflect's data, and a rollup here names nobody and quotes nothing.
        #expect(blocks.count == 1)
        #expect(blocks[0].contains(sentinel) == false)
    }

    // MARK: - Rolling up by year

    @Test func pastTwoYearsTheMonthsBecomeYears() {
        let documents = (0..<36).map { document(daysAgo: $0 * 31) }
        let intervals = (0..<36).map { month(daysAgo: $0 * 31) }
        let months = months(intervals, in: index(documents))
        #expect(months.count > AskRollups.maxMonthsBeforeRollingUpByYear)

        let blocks = AskRollups.lines(for: months, calendar: calendar)
        // Thirty-six lines saying "3 entries" each is more lines than it is information.
        #expect(blocks.count < 5)
        #expect(blocks.allSatisfy { $0.contains("entries across") })
        #expect(blocks[0].hasPrefix("2026"), "newest year first")
    }

    @Test func twoYearsOrFewerStayAsMonths() {
        let documents = (0..<12).map { document(daysAgo: $0 * 31) }
        let intervals = (0..<12).map { month(daysAgo: $0 * 31) }
        let blocks = AskRollups.lines(for: months(intervals, in: index(documents)), calendar: calendar)
        #expect(blocks.count == 12)
        #expect(blocks.allSatisfy { $0.contains("entries across") == false })
    }

    // MARK: - Counting the matched set, not the month

    // The finding that made this whole file worth re-reading. The prompt tells the model the block
    // summarizes everything that matched, so counting every entry in the month instead turns "what
    // happened with the deadline?" into "you wrote about the deadline 214 times in March", which is
    // the confident wrong answer the rollup exists to prevent, wearing the rollup's own clothes.
    @Test func aMonthCountsWhatMatchedAndNotTheWholeMonth() throws {
        let matched = document(daysAgo: 1)
        let alsoMatched = document(daysAgo: 3)
        let unrelated = (0..<20).map { document(daysAgo: $0 + 5) }
        let journal = index([matched, alsoMatched] + unrelated)

        let counted = months(
            [month(daysAgo: 1)],
            in: journal,
            matching: [matched.id, alsoMatched.id]
        )
        #expect(counted.first?.count == 2)

        // And it agrees with the number the prompt puts beside it.
        #expect(counted.reduce(0) { $0 + $1.count } == 2)
    }

    // MARK: - What reserving room for these costs

    @Test func theEstimateKnowsAboutTheYearPath() {
        // Twenty-four month lines and thirty-six months are not the same cost, and reserving as
        // though they were is how the year path came to be unreachable.
        #expect(AskRollups.estimatedCharacters(monthCount: 0) == 0)
        let twelve = AskRollups.estimatedCharacters(monthCount: 12)
        let thirtySix = AskRollups.estimatedCharacters(monthCount: 36)
        #expect(twelve > AskRollups.estimatedCharacters(monthCount: 6))
        #expect(thirtySix < twelve, "thirty-six months is three year lines, which is cheaper than twelve month lines")
    }

    @Test func aBlockIsOneFenceNotOnePerMonth() throws {
        let documents = (0..<6).map { document(daysAgo: $0 * 31) }
        let intervals = (0..<6).map { month(daysAgo: $0 * 31) }
        let block = try #require(AskRollups.block(for: months(intervals, in: index(documents)), calendar: calendar))
        #expect(block.components(separatedBy: "\n").count == 6)
    }

    @Test func noMonthsMeansNoBlockAtAll() {
        #expect(AskRollups.block(for: [], calendar: calendar) == nil)
    }
}
