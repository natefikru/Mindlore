import Foundation
import Testing
@testable import Mindlore

struct ConnectionsPresentationTests {
    private typealias Row = ConnectionsPresentation.ConnectionRow

    private func row(_ name: String, _ kind: EntityKind = .person, aliases: [String] = [], links: Int = 1, last: Date? = nil) -> Row {
        .init(id: UUID(), name: name, aliases: aliases, kind: kind, linkCount: links, lastLinkedAt: last)
    }

    @Test func filterByKindKeepsOnlyThatKindWhenSet() {
        let sarah = row("Sarah", .person)
        let river = row("river", .tag)

        #expect(ConnectionsPresentation.filter([sarah, river], kind: .person, search: "").map(\.name) == ["Sarah"])
        #expect(ConnectionsPresentation.filter([sarah, river], kind: nil, search: "").count == 2)
    }

    @Test func filterBySearchMatchesNameOrAlias() {
        let sarah = row("Sarah Kim", .person, aliases: ["mom"])
        let tom = row("Tom", .person)

        #expect(ConnectionsPresentation.filter([sarah, tom], kind: nil, search: "kim").map(\.name) == ["Sarah Kim"])
        #expect(ConnectionsPresentation.filter([sarah, tom], kind: nil, search: "mom").map(\.name) == ["Sarah Kim"])
        #expect(ConnectionsPresentation.filter([sarah, tom], kind: nil, search: "  ").count == 2, "whitespace-only search matches everything")
    }

    @Test func sortByNameIsAlphabetical() {
        let rows = [row("Tom"), row("Amy"), row("sarah")]
        #expect(ConnectionsPresentation.sort(rows, by: .name).map(\.name) == ["Amy", "sarah", "Tom"])
    }

    @Test func sortByMostMentionedBreaksTiesByName() {
        let rows = [row("Tom", links: 2), row("Amy", links: 5), row("Zoe", links: 5)]
        #expect(ConnectionsPresentation.sort(rows, by: .mostMentioned).map(\.name) == ["Amy", "Zoe", "Tom"])
    }

    // What Connections sorts on for "recent": an entity that has never been linked has no
    // lastLinkedAt and must not sort as if it were the most recent thing in the journal.
    @Test func sortByRecentPutsNeverLinkedLast() {
        let a = row("a", last: Date(timeIntervalSince1970: 100))
        let b = row("b", last: Date(timeIntervalSince1970: 50))
        let c = row("c", last: Date(timeIntervalSince1970: 900))
        let d = row("d", last: nil)

        #expect(ConnectionsPresentation.sort([a, b, c, d], by: .recent).map(\.name) == ["c", "a", "b", "d"])
    }

    @Test func sortByRecentBreaksNilTiesByName() {
        let rows = [row("Zoe", last: nil), row("Amy", last: nil)]
        #expect(ConnectionsPresentation.sort(rows, by: .recent).map(\.name) == ["Amy", "Zoe"])
    }
}
