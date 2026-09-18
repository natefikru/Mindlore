import Foundation
import Testing
@testable import Mindlore

struct EntitySearchTests {
    private typealias Row = EntitySearch.Row

    private func row(_ name: String, _ kind: EntityKind = .person, aliases: [String] = [], last: Date? = nil) -> Row {
        Row(id: UUID(), name: name, aliases: aliases, kind: kind, lastMentioned: last)
    }

    private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

    @Test func segmentsKeepTheirKindsAndAllKeepsEverything() {
        let rows = [row("Sarah"), row("Cedar Park", .place), row("Acme", .organization), row("Retreat", .event),
                    row("Novel", .project), row("river", .tag), row("Thing", .other)]

        #expect(EntitySearch.filter(rows, segment: .all, query: "").count == rows.count)
        #expect(EntitySearch.filter(rows, segment: .people, query: "").map(\.name) == ["Sarah"])
        #expect(EntitySearch.filter(rows, segment: .places, query: "").map(\.name) == ["Cedar Park"])
        #expect(EntitySearch.filter(rows, segment: .projects, query: "").map(\.name) == ["Novel"])
        #expect(EntitySearch.filter(rows, segment: .tags, query: "").map(\.name) == ["river"])
    }

    @Test func searchMatchesNameOrAlias() {
        let sarah = row("Sarah Kim", aliases: ["mom"])
        let tom = row("Tom")

        #expect(EntitySearch.filter([sarah, tom], segment: .all, query: "kim").map(\.name) == ["Sarah Kim"])
        #expect(EntitySearch.filter([sarah, tom], segment: .all, query: "mom").map(\.name) == ["Sarah Kim"])
        #expect(EntitySearch.filter([sarah, tom], segment: .all, query: "  ").count == 2, "whitespace-only search matches everything")
        #expect(EntitySearch.filter([sarah, tom], segment: .tags, query: "kim").isEmpty)
    }

    @Test func withoutAQueryTheMostRecentComeFirstAndNeverMentionedLast() {
        let rows = [row("a", last: at(100)), row("d"), row("b", last: at(50)), row("c", last: at(900)), row("Amy")]
        #expect(EntitySearch.rank(rows, query: "").map(\.name) == ["c", "a", "b", "Amy", "d"])
    }

    @Test func aQueryRanksNameStartsThenWordStartsThenTheRest() {
        let inside = row("Marisa", last: at(900))
        let alias = row("Mom", aliases: ["Rissa"], last: at(800))
        let wordStart = row("Anna Rios", last: at(10))
        let start = row("Riley", last: at(5))
        let laterStart = row("Rivera", last: at(20))

        let ranked = EntitySearch.rank([inside, alias, wordStart, start, laterStart], query: "ri")
        #expect(ranked.map(\.name) == ["Rivera", "Riley", "Anna Rios", "Marisa", "Mom"])
    }
}
